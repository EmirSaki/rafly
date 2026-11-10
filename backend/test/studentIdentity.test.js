const { test } = require('node:test');
const assert = require('node:assert/strict');
const { resolveActiveStudent } = require('../src/controllers/reservation.controller');

// Sahte client: students tablosunu bellekten döndürür ve SQL'in arşivlileri
// (mezunları) elediğini doğrular.
function fakeClient(rows) {
  return {
    async query(sql, params) {
      assert.match(sql, /archived_at IS NULL/);
      return {
        rows: rows
          .filter((r) => r.student_number === params[0] && !r.archived_at)
          .sort((a, b) => a.student_id - b.student_id),
      };
    },
  };
}

const row = (student_id, student_number, full_name, school_level, class_name, archived_at = null) => ({
  student_id, student_number, full_name, school_level, class_name, archived_at,
});

const students = [
  row(1, '10', 'Mezun Lise', 'lise', '12A', '2026-06-20'),
  row(2, '10', 'Ali Ortaokul', 'ortaokul', '6A'),
  row(3, '10', 'Ece Lise', 'lise', '9B'),
  row(4, '55', 'Tek Öğrenci', 'ortaokul', '7C'),
  row(5, '77', 'Sadece Mezun', 'lise', '12B', '2026-06-20'),
  row(6, '88', 'Seviyesiz Eski', null, '5A'),
];
const resolve = (studentNumber, level, className) =>
  resolveActiveStudent(fakeClient(students), 'school_1', { studentNumber, level, className });

test('aynı numara: seviye ortaokul ise ortaokul öğrencisi seçilir', async () => {
  assert.equal((await resolve('10', 'ortaokul')).student.student_id, 2);
});

test('aynı numara: seviye lise ise aktif lise öğrencisi seçilir, mezun asla', async () => {
  assert.equal((await resolve('10', 'lise')).student.student_id, 3);
});

test('seviye verilmez ve numara birden fazla aktif öğrencide varsa tahmin edilmez', async () => {
  const r = await resolve('10', null);
  assert.equal(r.student, undefined);
  assert.deepEqual(r.ambiguous.map((c) => c.school_level), ['ortaokul', 'lise']);
});

test('seviye verilmese de numara tek aktif öğrencideyse o seçilir', async () => {
  assert.equal((await resolve(' 55 ', null)).student.student_id, 4);
});

test('yanlış seviye başka seviyedeki aynı numaralı öğrenciye düşmez', async () => {
  assert.equal((await resolve('55', 'lise')).notFound, true);
});

test('yalnızca mezun kaydı olan numaraya kitap verilemez', async () => {
  assert.equal((await resolve('77', 'lise')).notFound, true);
  assert.equal((await resolve('77', null)).notFound, true);
});

test('seviyesi girilmemiş eski kayıt, tam eşleşme yoksa kabul edilir', async () => {
  assert.equal((await resolve('88', 'ortaokul')).student.student_id, 6);
});
