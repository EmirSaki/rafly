const pool = require('../config/db');
const jwt = require('jsonwebtoken');
const ExcelJS = require('exceljs');
const { parseStudentsFromWorkbook } = require('./student.controller');
const { buildPromotionPlan, identity, snapshot } = require('../services/studentPromotion');
const { ensureStudentsUniqueIndex } = require('../config/studentsIndex');

function authorizePromotion(req, res, next) {
  if (!process.env.JWT_SECRET) return res.status(503).json({ success: false, message: 'Sınıf atlatma için güvenli oturum yapılandırması gerekiyor.' });
  try {
    const user = jwt.verify((req.headers.authorization || '').replace(/^Bearer /, ''), process.env.JWT_SECRET);
    if (!['teacher', 'admin'].includes(user.role) || String(user.school_code) !== String(req.query.schoolCode)) {
      return res.status(403).json({ success: false, message: 'Bu okul için personel yetkisi gerekiyor.' });
    }
    req.promotionUser = user;
    next();
  } catch {
    res.status(401).json({ success: false, message: 'Oturum geçersiz. Yeniden giriş yapın.' });
  }
}

function accountIds(student, accounts) {
  return accounts.filter(a => identity({ student_number: a.student_id, full_name: `${a.user_name} ${a.user_surname}` }) === identity(student)
    && (a.school_level || '') === (student.school_level || '')).map(a => a.user_id);
}

// Mevcut DB'deki mukerrer (ayni ad+soyad+numara) roster satirlarini, yeni listede
// kalan (survivor) kayda BIRLESTIRIR: eski satirlarin odunc/rezervasyon gecmisini
// ve giris/sifre hesabini survivor'a tasir, ardindan eski satirlari siler.
// reservations.student_local_id ve users.user_id FK'leri ON DELETE CASCADE oldugu
// icin tasima HER ZAMAN silmeden once yapilir. `accounts` bellek icinde guncellenir
// ki sonraki promotion adimlari (plan.updated) dogru hesabi bulabilsin.
async function mergeDuplicates(client, schema, merges, accounts) {
  for (const { survivor, duplicates } of merges) {
    const survivorId = survivor.student_id;
    const dupIds = duplicates.map(d => d.student_id);

    // 1) Eski satirlara bagli odunc gecmisini survivor satirina tasi (cascade'den once)
    await client.query(
      `UPDATE ${schema}.reservations SET student_local_id = $1 WHERE student_local_id = ANY($2::int[])`,
      [survivorId, dupIds]
    );

    // 2) Bu ogrencinin (kimlik = ad+soyad+numara) tum giris hesaplari (seviye bagimsiz)
    const groupUserIds = [...new Set(accounts
      .filter(a => identity({ student_number: a.student_id, full_name: `${a.user_name} ${a.user_surname}` }) === identity(survivor))
      .map(a => a.user_id))];
    const survivorUser = accountIds(survivor, accounts)[0] ?? groupUserIds[0] ?? null;

    if (survivorUser) {
      const extra = groupUserIds.filter(id => id !== survivorUser);
      if (extra.length) {
        // Fazla hesaplarin gecmisini survivor hesabina tasi, sonra fazla hesaplari sil
        await client.query(`UPDATE ${schema}.reservations SET user_id = $1 WHERE user_id = ANY($2::int[])`, [survivorUser, extra]);
        await client.query(`UPDATE public.reservations SET user_id = $1 WHERE user_id = ANY($2::int[])`, [survivorUser, extra]);
        await client.query(`DELETE FROM public.users WHERE user_id = ANY($1::int[])`, [extra]); // ${schema}.users ON DELETE CASCADE
      }
      // Survivor hesabini survivor satirinin seviye/sinifina hizala (promotion sonra dogru seviyeye tasir)
      await client.query(`UPDATE ${schema}.users SET school_level = $1, user_class = $2, user_class_code = $3 WHERE user_id = $4`,
        [survivor.school_level, survivor.class_name, survivor.class_code, survivorUser]);
      await client.query(`UPDATE public.users SET school_level = $1, user_class = $2, user_class_code = $3 WHERE user_id = $4`,
        [survivor.school_level, survivor.class_name, survivor.class_code, survivorUser]);
      // Bellek icindeki accounts'u da guncelle
      for (let i = accounts.length - 1; i >= 0; i--) {
        if (extra.includes(accounts[i].user_id)) accounts.splice(i, 1);
        else if (accounts[i].user_id === survivorUser) {
          accounts[i].school_level = survivor.school_level;
          accounts[i].user_class = survivor.class_name;
          accounts[i].user_class_code = survivor.class_code;
        }
      }
    }

    // 3) Eski mukerrer roster satirlarini sil
    await client.query(`DELETE FROM ${schema}.students WHERE student_id = ANY($1::int[])`, [dupIds]);
  }
}

const secret = () => {
  if (!process.env.JWT_SECRET) throw new Error('Güvenli oturum yapılandırması gerekiyor.');
  return process.env.JWT_SECRET;
};
function checkToken(token, digest, req, phase) {
  let payload;
  try { payload = jwt.verify(token || '', secret(), { audience: 'student-promotion' }); }
  catch { throw new Error('Önizlemenin süresi doldu. Dosyaları yeniden kontrol edin.'); }
  if (payload.digest !== digest || payload.actor !== req.promotionUser.user_id || payload.school !== String(req.query.schoolCode) || payload.phase !== phase) {
    throw new Error('Liste veya öğrenci kayıtları değişti. Önizlemeyi yeniden oluşturup Excel yedeğini tekrar indirin.');
  }
}
function signToken(digest, req, phase) {
  return jwt.sign({ digest, actor: req.promotionUser.user_id, school: String(req.query.schoolCode), phase }, secret(), { audience: 'student-promotion', expiresIn: '30m' });
}

async function promotion(req, res, next) {
  let client;
  try {
    const schoolCode = String(req.query.schoolCode || '');
    if (!/^\d+$/.test(schoolCode)) throw new Error('Geçersiz okul kodu.');
    const scope = req.body.scope;
    if (!req.files?.length) throw new Error('Yeni dönemin tüm Excel dosyalarını seçin.');
    const incoming = [];
    for (const file of req.files) {
      if (!/\.xlsx?$/i.test(file.originalname)) throw new Error('Yalnızca .xls ve .xlsx dosyaları desteklenir.');
      try { incoming.push(...await parseStudentsFromWorkbook(file.buffer, file.originalname, { strict: true })); }
      catch (error) { throw new Error(`${file.originalname}: ${error.message}`); }
    }
    if (incoming.length > 20000) throw new Error('En fazla 20.000 öğrenci yüklenebilir.');
    client = await pool.connect();
    await client.query('BEGIN');
    const schema = `school_${schoolCode}`;
    // Stabilize identity/class and reservation state between validation and commit.
    // archived_at sutunu + AKTIF ogrenciler icin kismi unique index (arsivliler haric).
    await ensureStudentsUniqueIndex(client, schema);
    await client.query(`LOCK TABLE ${schema}.students, ${schema}.users, ${schema}.reservations, public.users, public.reservations IN SHARE ROW EXCLUSIVE MODE`);
    const students = (await client.query(`SELECT * FROM ${schema}.students ORDER BY student_id`)).rows;
    const accounts = (await client.query(`SELECT user_id, student_id, user_name, user_surname, school_level, user_class, user_class_code FROM public.users WHERE school_id = (SELECT school_id FROM public.schools WHERE school_code = $1) AND user_role = 'student' ORDER BY user_id`, [schoolCode])).rows;
    const plan = buildPromotionPlan(students, incoming, scope, accounts);
    const digest = snapshot({ students, incoming, scope }, accounts);
    const removedIds = plan.removed.map(s => s.student_id);
    const removedUsers = [...new Set(plan.removed.flatMap(s => accountIds(s, accounts)))];
    const active = (await client.query(`SELECT reservation_id FROM ${schema}.reservations WHERE (student_local_id = ANY($1::int[]) OR user_id = ANY($2::int[])) AND status IN ('loaned', 'reserved', 'pending')`, [removedIds, removedUsers])).rows;
    const publicActive = (await client.query(`SELECT reservation_id FROM public.reservations WHERE user_id = ANY($1::int[]) AND reservation_status IN ('loaned', 'reserved', 'pending')`, [removedUsers])).rows;
    const merged = plan.merges.reduce((n, m) => n + m.duplicates.length, 0);
    const summary = { updated: plan.updated.length, added: plan.added.length, removed: plan.removed.length, merged, activeReservations: active.length + publicActive.length };
    const phase = req.params.phase;
    if (phase === 'preview') {
      await client.query('COMMIT');
      return res.json({ success: true, summary, removed: plan.removed, changes: plan.updated.map(s => ({ student_number: s.before.student_number, full_name: s.before.full_name, old_class: s.before.class_name, new_class: s.after.class_name })), token: signToken(digest, req, 'preview') });
    }
    checkToken(req.body.token, digest, req, phase === 'report' ? 'preview' : 'report');
    if (phase === 'report') {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet('Eski Öğrencilere Taşınacaklar');
      sheet.columns = [
        { header: 'Öğrenci No', key: 'student_number', width: 18 },
        { header: 'Ad Soyad', key: 'full_name', width: 44 },
        { header: 'Eski Sınıf', key: 'class_name', width: 18 },
        { header: 'Seviye', key: 'school_level', width: 18 },
        { header: 'Taşınma Nedeni', key: 'reason', width: 36 },
      ];
      sheet.addRows(plan.removed);
      sheet.views = [{ state: 'frozen', ySplit: 1 }];
      sheet.autoFilter = 'A1:E1';
      sheet.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } };
      sheet.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF152E63' } };
      const history = (await client.query(`SELECT r.*, b.book_name AS book_title FROM ${schema}.reservations r LEFT JOIN public.books b ON b.book_id = r.book_id WHERE r.student_local_id = ANY($1::int[]) OR r.user_id = ANY($2::int[]) ORDER BY r.reservation_id`, [removedIds, removedUsers])).rows;
      const historySheet = workbook.addWorksheet('Rezervasyon Geçmişi');
      historySheet.columns = ['student_number', 'book_title', 'status', 'reserved_at', 'due_date', 'returned_at'].map(key => ({ header: key, key, width: 25 }));
      historySheet.addRows(history);
      const buffer = await workbook.xlsx.writeBuffer();
      await client.query('COMMIT');
      return res.json({ success: true, file: Buffer.from(buffer).toString('base64'), filename: `sinif-atlatma-eski-ogrenciler-${schoolCode}.xlsx`, token: signToken(digest, req, 'report') });
    }
    if (phase !== 'commit' || req.body.confirm !== 'true') throw new Error('İşlem onayı gerekiyor.');
    // Yeni listede kalan ogrencilerin mevcut mukerrer kayitlarini (ayni ad+soyad+numara)
    // gecmis ve sifre korunarak tek kayda birlestir. accounts bellek icinde guncellenir.
    await mergeDuplicates(client, schema, plan.merges, accounts);
    // Yeni listede olmayanlari SILME yerine "Eski Ogrenciler"e arsivle: kayit, hesap,
    // sifre ve odunc gecmisi korunur; ogrenci uygulamaya girmeye devam edebilir, sadece
    // panelde ayri kategoride durur. Aktif odunc olsa bile arsivlenir (veri kaybi yok).
    await client.query(`UPDATE ${schema}.students SET archived_at = now() WHERE student_id = ANY($1::int[]) AND archived_at IS NULL`, [removedIds]);
    // Avoid transient unique conflicts when students exchange classes.
    const ids = plan.updated.map(s => s.before.student_id);
    await client.query(`UPDATE ${schema}.students SET class_name = NULL WHERE student_id = ANY($1::int[])`, [ids]);
    for (const { before, after } of plan.updated) {
      // Yeni listede oldugu icin guncellenir; arsivdeyse (Eski Ogrenci) tekrar aktiflesir.
      await client.query(`UPDATE ${schema}.students SET class_name=$1, class_code=$2, school_level=$3, archived_at = NULL WHERE student_id=$4`, [after.class_name, after.class_code, after.school_level, before.student_id]);
      const userIds = accountIds(before, accounts);
      for (const table of ['public.users', `${schema}.users`]) {
        await client.query(`UPDATE ${table} SET user_class=$1, user_class_code=$2, school_level=$3 WHERE user_id = ANY($4::int[])`, [after.class_name, after.class_code, after.school_level, userIds]);
      }
    }
    for (const row of plan.added) {
      await client.query(`INSERT INTO ${schema}.students (student_number, full_name, class_name, class_code, school_level) VALUES ($1,$2,$3,$4,$5)`, [row.student_number, row.full_name, row.class_name, row.class_code, row.school_level]);
    }
    await client.query('COMMIT');
    return res.json({ success: true, summary, message: 'Sınıf atlatma tamamlandı.' });
  } catch (error) {
    if (client) await client.query('ROLLBACK');
    if (!error.code) return res.status(400).json({ success: false, message: error.message });
    next(error);
  } finally { client?.release(); }
}

module.exports = { promotion, authorizePromotion, mergeDuplicates };

