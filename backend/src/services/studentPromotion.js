const crypto = require('node:crypto');

const text = value => String(value ?? '').normalize('NFC').trim().replace(/\s+/g, ' ');
const name = value => text(value).toLocaleUpperCase('tr-TR');
const identity = student => JSON.stringify([text(student.student_number), name(student.full_name)]);

function uniqueIndex(rows, label) {
  const map = new Map();
  for (const row of rows) {
    if (!text(row.student_number) || !text(row.full_name)) throw new Error(`${label}: eksik öğrenci bilgisi.`);
    const key = identity(row);
    if (map.has(key)) throw new Error(`${label}: ${row.student_number} / ${row.full_name} birden fazla kayıtla eşleşiyor. Önce mükerrer kayıtları düzeltin.`);
    map.set(key, row);
  }
  return map;
}

// Mevcut listedeki (DB) mukerrer kayitlari HATA vermek yerine birlestirmeye hazirlar:
// ayni ad+soyad+numaradan birden fazla satir varsa birini "survivor" secip
// (varsa hesabi/sifresi olan satiri, yoksa en eskisini) digerlerini "duplicates"
// olarak isaretler. Boylece plan tek kimlik uzerinden kurulur; gercek birlestirme
// (gecmis + hesap tasima, eski satir silme) commit asamasinda yapilir.
function collapseExisting(existing, accounts = []) {
  const hasAccount = row => accounts.some(a =>
    identity({ student_number: a.student_id, full_name: `${a.user_name} ${a.user_surname}` }) === identity(row)
    && (a.school_level || '') === (row.school_level || ''));
  const groups = new Map();
  for (const row of existing) {
    if (!text(row.student_number) || !text(row.full_name)) throw new Error('Mevcut liste: eksik öğrenci bilgisi.');
    const key = identity(row);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  const deduped = [];
  const duplicatesByKey = new Map();
  for (const [key, rows] of groups) {
    const survivor = rows.find(hasAccount) || rows[0];
    deduped.push(survivor);
    const dups = rows.filter(r => r !== survivor);
    if (dups.length) duplicatesByKey.set(key, dups);
  }
  return { deduped, duplicatesByKey };
}

// Scope is explicit: a single class file must never implicitly replace a school.
function buildPromotionPlan(existing, incoming, scope, accounts = []) {
  if (!['all', 'ilkokul', 'ortaokul', 'lise', 'hazırlık'].includes(scope)) throw new Error('İşlem kapsamını seçin.');
  if (!incoming.length) throw new Error('Yeni liste boş olamaz.');
  if (scope !== 'all' && incoming.some(s => s.school_level !== scope)) throw new Error('Dosyalardaki sınıflar seçilen kademeyle uyuşmuyor.');
  const { deduped, duplicatesByKey } = collapseExisting(existing, accounts);
  const oldMap = new Map(deduped.map(r => [identity(r), r]));
  const newMap = uniqueIndex(incoming, 'Yeni liste');
  const reasonFor = row => /^(8|12)(?!\d)/.test(text(row.class_name)) ? 'Mezun sınıf; yeni listede yok' : 'Yeni listede yok';
  const updated = [], added = [], removed = [], merges = [];
  for (const [key, survivor] of oldMap) {
    const incomingRow = newMap.get(key);
    const dups = duplicatesByKey.get(key) || [];
    if (incomingRow) {
      if (scope !== 'all' && survivor.school_level !== scope) throw new Error('Kademe değiştiren öğrenci var. Okulun tamamı kapsamında işlem yapın.');
      // Yeni listede olan (arsivde olsa bile) -> guncellenir ve aktiflestirilir
      updated.push({ before: survivor, after: incomingRow });
      // survivor yeni listede -> mukerrerleri buna birlestirilecek (silinmeyecek)
      if (dups.length) merges.push({ survivor, duplicates: dups });
    } else {
      // survivor yeni listede yok -> Eski Ogrenciler'e tasinir (arsivlenir).
      // Zaten arsivlenmis olanlari tekrar listeye ekleme.
      if ((scope === 'all' || survivor.school_level === scope) && !survivor.archived_at) removed.push({ ...survivor, reason: reasonFor(survivor) });
      for (const d of dups) if ((scope === 'all' || d.school_level === scope) && !d.archived_at) removed.push({ ...d, reason: reasonFor(d) });
    }
  }
  for (const [key, row] of newMap) if (!oldMap.has(key)) added.push(row);
  // Arsivli (Eski Ogrenci) satirlar aktif slot isgal etmez; catisma kontrolunden haric.
  const finalRows = [...deduped.filter(s => !s.archived_at && !removed.some(r => r.student_id === s.student_id) && !newMap.has(identity(s))), ...incoming];
  const slots = new Set();
  for (const row of finalRows) {
    const slot = JSON.stringify([row.school_level, row.class_name, text(row.student_number)]);
    if (slots.has(slot)) throw new Error('Aynı sınıfta aynı numarayla birden fazla öğrenci oluşuyor. Listeyi düzeltin.');
    slots.add(slot);
  }
  return { updated, added, removed, merges };
}

function snapshot(rows, accounts) {
  return crypto.createHash('sha256').update(JSON.stringify({ rows, accounts })).digest('hex');
}

module.exports = { buildPromotionPlan, collapseExisting, identity, snapshot, text };
