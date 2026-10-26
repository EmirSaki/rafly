const { test } = require('node:test');
process.env.JWT_SECRET = 'promotion-test-only-key';
const assert = require('node:assert/strict');
const ExcelJS = require('exceljs');
const jwt = require('jsonwebtoken');
const pool = require('../src/config/db');
const { promotion, authorizePromotion } = require('../src/controllers/studentPromotion.controller');
const { parseStudentsFromWorkbook } = require('../src/controllers/student.controller');

async function file(name = 'Ali', surname = 'Ak') {
  const book = new ExcelJS.Workbook();
  const sheet = book.addWorksheet('Liste');
  sheet.addRow(['7. Sınıf / B Şubesi']);
  sheet.addRow(['Öğrenci No', 'Adı', 'Soyadı']);
  sheet.addRow(['15', name, surname]);
  return { originalname: '7B.xlsx', buffer: Buffer.from(await book.xlsx.writeBuffer()) };
}
function response() {
  return { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
}

test('strict parser accepts the existing Excel format and rejects incomplete students', async () => {
  const f = await file();
  const rows = await parseStudentsFromWorkbook(f.buffer, f.originalname, { strict: true });
  assert.equal(rows[0].class_name, '7B');
  const broken = await file('Ali', '');
  await assert.rejects(parseStudentsFromWorkbook(broken.buffer, broken.originalname, { strict: true }), /eksik/);
});

for (const format of ['xls', 'xlsx']) {
  for (const layout of ['merged-name', 'high-school']) {
    test(`strict ${format} parser handles ${layout} layout without losing students`, async () => {
      const XLSX = require('xlsx');
      const high = layout === 'high-school';
      const rows = [['6. Sınıf / A Şubesi'], [],
        high ? ['S.No', 'Öğrenci No', '', '', 'Adı', '', '', '', 'Soyadı']
          : ['S.No', '', 'Öğrenci No', '', '', 'Adı', '', '', '', 'Soyadı'],
        high ? ['1', '20', '', '', 'Test', '', '', '', 'Öğrenci']
          : ['1', '', '20', '', 'Test', '', '', '', '', 'Öğrenci'], [],
        ['', 'Kız Öğrenci Sayısı :', '', '', '1', '', 'Erkek Öğrenci Sayısı :', '', '', '0', '', 'Toplam Öğrenci Sayısı :', '', '', '', '1']];
      const buffer = () => {
        const book = XLSX.utils.book_new();
        const sheet = XLSX.utils.aoa_to_sheet(rows);
        sheet['!merges'] = [{ s: { r: 3, c: 4 }, e: { r: 3, c: 7 } }];
        XLSX.utils.book_append_sheet(book, sheet, 'Liste');
        return XLSX.write(book, { type: 'buffer', bookType: format === 'xls' ? 'biff8' : 'xlsx' });
      };
      const students = await parseStudentsFromWorkbook(buffer(), `6A.${format}`, { strict: true });
      assert.equal(students.length, 1);
      assert.equal(students[0].full_name, 'Test Öğrenci');
      assert.equal(students[0].student_number, '20');
      rows[3][4] = '';
      await assert.rejects(parseStudentsFromWorkbook(buffer(), `6A.${format}`, { strict: true }), /4\. satırda.*eksik/);
    });
  }
  test(`strict ${format} parser skips e-Okul totals and reports physical row numbers`, async () => {
    const XLSX = require('xlsx');
    const rows = [[], ['5. Sınıf / A Şubesi'], [],
      ['S.No', '', 'Öğrenci No', '', '', 'Adı', '', '', '', 'Soyadı'],
      ['1', '', '213', '', '', 'Test', '', '', '', 'Öğrenci'], [],
      ['', 'Kız Öğrenci Sayısı :', '', '', '1', '', 'Erkek Öğrenci Sayısı :', '', '', '0', '', 'Toplam Öğrenci Sayısı :', '', '', '', '1']];
    const buffer = () => {
      const book = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(book, XLSX.utils.aoa_to_sheet(rows), 'Liste');
      return XLSX.write(book, { type: 'buffer', bookType: format === 'xls' ? 'biff8' : 'xlsx' });
    };
    assert.equal((await parseStudentsFromWorkbook(buffer(), `5A.${format}`, { strict: true })).length, 1);
    rows.push([], ['2', '', '214', '', '', 'Test']);
    await assert.rejects(parseStudentsFromWorkbook(buffer(), `5A.${format}`, { strict: true }), /9\. satırda.*eksik/);
    rows[8] = ['2', '', '', '', '', 'Test', '', '', '', 'Öğrenci'];
    await assert.rejects(parseStudentsFromWorkbook(buffer(), `5A.${format}`, { strict: true }), /9\. satırda.*eksik/);
    rows[8][2] = 'invalid';
    await assert.rejects(parseStudentsFromWorkbook(buffer(), `5A.${format}`, { strict: true }), /9\. satırda geçersiz/);
  });
}

test('staff authorization rejects cross-school and student tokens', () => {
  for (const claims of [{ role: 'student', school_code: '123' }, { role: 'teacher', school_code: '999' }]) {
    const token = jwt.sign(claims, process.env.JWT_SECRET || 'dev_secret');
    const res = response();
    authorizePromotion({ headers: { authorization: `Bearer ${token}` }, query: { schoolCode: '123' } }, res, () => assert.fail('must reject'));
    assert.equal(res.statusCode, 403);
  }
});

test('preview and report do not mutate; commit preserves matched identity and reservations; stale tokens abort', async () => {
  const oldConnect = pool.connect;
  const queries = [];
  const existing = [{ student_id: 77, student_number: '15', full_name: 'Ali Ak', class_name: '6A', class_code: '6A', school_level: 'ortaokul' }];
  pool.connect = async () => ({ release() {}, async query(sql, args) {
    queries.push({ sql, args });
    if (sql.startsWith('SELECT * FROM')) return { rows: existing };
    return { rows: [] };
  } });
  try {
    const req = { query: { schoolCode: '123' }, body: { scope: 'all' }, files: [await file()], params: { phase: 'preview' }, promotionUser: { user_id: 1 } };
    const call = async () => { const res = response(); await promotion(req, res, error => { throw error; }); return res; };
    const p = await call();
    assert.equal(p.body.summary.updated, 1);
    req.params.phase = 'report'; req.body.token = p.body.token;
    const r = await call();
    assert.ok(r.body.file);
    assert.ok(!queries.some(q => /^(DELETE|UPDATE|INSERT)/.test(q.sql)));
    req.params.phase = 'commit'; req.body.token = r.body.token; req.body.confirm = 'true';
    assert.equal((await call()).body.success, true);
    assert.ok(queries.some(q => q.sql.startsWith('UPDATE school_123.students SET class_name=$1') && q.args[3] === 77));
    assert.ok(!queries.some(q => /^(DELETE|UPDATE|INSERT).*reservations/.test(q.sql)));
    existing[0].class_name = '7B';
    queries.length = 0;
    assert.equal((await call()).statusCode, 400);
    assert.ok(queries.some(q => q.sql === 'ROLLBACK'));
    assert.ok(!queries.some(q => /^(DELETE|UPDATE|INSERT)/.test(q.sql)));
  } finally { pool.connect = oldConnect; }
});
