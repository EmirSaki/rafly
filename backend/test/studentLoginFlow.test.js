const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const bcrypt = require('bcrypt');

// Sahte veritabanı: yalnızca giriş akışının kullandığı sorguları bellekten yanıtlar.
const db = { passwordSet: false, hash: null, calls: [] };
const dbPath = require.resolve('../src/config/db');
require.cache[dbPath] = {
  id: dbPath, filename: dbPath, loaded: true,
  exports: {
    async query(sql, params) {
      db.calls.push({ sql, params });
      if (/information_schema\.schemata/.test(sql)) return { rows: [{ schema_name: 'school_1' }] };
      if (/FROM school_1\.students|FROM school_1\.students/.test(sql) && /student_number = \$1/.test(sql)) {
        return { rows: [{ student_id: 1, student_number: '55', full_name: 'Ali Veli', class_name: '6A', class_code: '6A', school_level: 'ortaokul' }] };
      }
      if (/FROM public\.schools/.test(sql)) return { rows: [{ school_id: 9, school_code: '1', school_name: 'Test' }] };
      if (/FROM school_1\.users u/.test(sql)) {
        return { rows: [{ user_id: 42, user_name: 'Ali', user_surname: 'Veli', user_class: '6A', student_id: '55', user_role: 'student', school_level: 'ortaokul' }] };
      }
      if (/SELECT password, COALESCE\(password_set/.test(sql)) return { rows: [{ password: db.hash, password_set: db.passwordSet }] };
      if (/^\s*UPDATE public\.users\s+SET password = \$1, password_set = TRUE/.test(sql)) {
        if (db.passwordSet) return { rows: [] };
        db.hash = params[0]; db.passwordSet = true;
        return { rows: [{ user_id: 42, school_id: 9 }] };
      }
      return { rows: [] };
    },
    connect: async () => { throw new Error('beklenmiyor'); },
  },
};

const { loginStudent, setStudentPassword } = require('../src/controllers/student.controller');
const { signSetupToken } = require('../src/utils/studentPassword');

function call(handler, body, ip = '1.1.1.1') {
  return new Promise((resolve, reject) => {
    const res = {
      statusCode: 200,
      status(c) { this.statusCode = c; return this; },
      json(b) { resolve({ status: this.statusCode, body: b }); return this; },
    };
    handler({ body, ip }, res, reject).catch?.(reject);
  });
}
const login = (password, ip) => call(loginStudent, { schoolCode: '1', student_number: '55', school_level: 'ortaokul', password }, ip);

test('şifresi belirlenmemiş öğrenci 1234 ile TAM OTURUM alamaz, kurulum anahtarı alır', async () => {
  db.passwordSet = false; db.hash = null;
  const r = await login('1234', '10.0.0.1');
  assert.equal(r.body.success, false);
  assert.equal(r.body.code, 'PASSWORD_SETUP_REQUIRED');
  assert.ok(r.body.setup_token);
  assert.equal(r.body.token, undefined);
});

test('belirlenmemiş öğrenci başka şifreyle giremez', async () => {
  db.passwordSet = false;
  const r = await login('baska', '10.0.0.2');
  assert.equal(r.status, 401);
});

test('şifre belirleme: zayıf şifre reddedilir, güçlü şifre kaydedilir, sonra 1234 ile girilemez', async () => {
  db.passwordSet = false; db.hash = null;
  const setup_token = signSetupToken({ user_id: 42 });

  const weak = await call(setStudentPassword, { setup_token, new_password: '1234' });
  assert.equal(weak.status, 400);

  const bad = await call(setStudentPassword, { setup_token: 'sahte', new_password: 'kitap-2026' });
  assert.equal(bad.status, 401);

  const ok = await call(setStudentPassword, { setup_token, new_password: 'kitap-2026' });
  assert.equal(ok.status, 200);
  assert.equal(db.passwordSet, true);
  assert.ok(await bcrypt.compare('kitap-2026', db.hash));

  // Aynı anahtarla ikinci kez şifre değiştirilemez (hesap ele geçirme koruması)
  const again = await call(setStudentPassword, { setup_token, new_password: 'baska-sifre-1' });
  assert.equal(again.status, 409);

  const old = await login('1234', '10.0.0.3');
  assert.equal(old.status, 401);
  assert.equal(old.body.token, undefined);

  const good = await login('kitap-2026', '10.0.0.4');
  assert.equal(good.body.success, true);
  assert.ok(good.body.token);
});

test('çok sayıda hatalı deneme 429 ile engellenir', async () => {
  db.passwordSet = true; db.hash = await bcrypt.hash('dogru-sifre', 4);
  let last;
  for (let i = 0; i < 9; i++) last = await login('yanlis' + i, '10.9.9.9');
  assert.equal(last.status, 429);
  const stillBlocked = await login('dogru-sifre', '10.9.9.9');
  assert.equal(stillBlocked.status, 429);
});
