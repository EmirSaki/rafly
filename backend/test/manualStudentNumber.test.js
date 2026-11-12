const { test } = require('node:test');
const assert = require('node:assert/strict');

// Sahte veritabanı: createManualStudent'in sorgularını bellekten yanıtlar.
const state = { calls: [], nextNo: '10012' };
const dbPath = require.resolve('../src/config/db');
require.cache[dbPath] = {
  id: dbPath, filename: dbPath, loaded: true,
  exports: {
    query: async () => ({ rows: [] }),
    connect: async () => ({
      release() {},
      async query(sql, params) {
        state.calls.push({ sql, params });
        if (/information_schema\.schemata/.test(sql)) return { rows: [{ schema_name: 'school_764135' }] };
        if (/AS next_no/.test(sql)) return { rows: [{ next_no: state.nextNo }] };
        if (/INSERT INTO school_\d+\.students/.test(sql)) {
          return { rows: [{ student_id: 1, student_number: params[0], school_level: params[4] }] };
        }
        return { rows: [] }; // mevcut öğrenci yok, okul satırı yok, ALTER/BEGIN/COMMIT
      },
    }),
  },
};

const { createManualStudent } = require('../src/controllers/student.controller');

function call(body) {
  state.calls = [];
  return new Promise((resolve, reject) => {
    const res = {
      statusCode: 200,
      status(c) { this.statusCode = c; return this; },
      json(b) { resolve({ status: this.statusCode, body: b }); return this; },
    };
    createManualStudent({ body }, res, reject).catch?.(reject);
  });
}

const base = { schoolCode: '764135', full_name: 'Test Öğretmen', class_name: 'ÖĞRETMEN' };

test('"diğer": istemcinin gönderdiği numara (10003) yok sayılır, sunucu boş numarayı atar', async () => {
  const r = await call({ ...base, student_number: '10003', school_level: 'diğer' });
  assert.equal(r.status, 201);
  assert.equal(r.body.data.student_number, '10012');
  assert.match(r.body.message, /No: 10012/);
  assert.ok(state.calls.some((c) => /pg_advisory_xact_lock/.test(c.sql)), 'eşzamanlı kayıt kilidi alınmalı');
});

test('"diğer": numara hiç gönderilmese de kayıt olur', async () => {
  const r = await call({ ...base, school_level: 'diğer' });
  assert.equal(r.status, 201);
  assert.equal(r.body.data.student_number, '10012');
});

test('normal seviyede (lise) davranış değişmez: gönderilen numara kullanılır, kilit alınmaz', async () => {
  const r = await call({ ...base, student_number: '512', school_level: 'lise' });
  assert.equal(r.status, 201);
  assert.equal(r.body.data.student_number, '512');
  assert.equal(r.body.message, 'Öğrenci başarıyla eklendi');
  assert.ok(!state.calls.some((c) => /pg_advisory_xact_lock|AS next_no/.test(c.sql)));
});

test('normal seviyede numara zorunlu olmaya devam eder', async () => {
  const r = await call({ ...base, school_level: 'lise' });
  assert.equal(r.status, 400);
});
