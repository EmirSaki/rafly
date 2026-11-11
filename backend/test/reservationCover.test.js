const { test } = require('node:test');
const assert = require('node:assert/strict');
const pool = require('../src/config/db');
const { getAllReservations } = require('../src/controllers/reservation.controller');
const { getMyReservations } = require('../src/controllers/student.controller');

function response() {
  return {
    code: 200,
    status(code) { this.code = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

test('staff reservation response includes the cover used by list cards', async () => {
  const oldQuery = pool.query;
  const cover = 'https://example.test/book.jpg';
  let sql;
  pool.query = async (query) => {
    sql = query;
    return { rows: [{ reservation_id: 1, cover_url: cover }] };
  };
  try {
    const res = response();
    await getAllReservations({ query: { schoolCode: '123456' } }, res, (error) => { throw error; });
    assert.equal(res.code, 200);
    assert.equal(res.body.data[0].cover_url, cover);
    assert.match(sql, /b\.cover_url/);
  } finally {
    pool.query = oldQuery;
  }
});

test('student reservation response includes the active book cover', async () => {
  const oldQuery = pool.query;
  const cover = 'https://example.test/student-book.jpg';
  let sql;
  pool.query = async (query) => {
    sql = query;
    return { rows: [{ reservation_id: 2, cover_url: cover }] };
  };
  try {
    const res = response();
    await getMyReservations({ user: { user_id: 7, school_code: '123456' } }, res, (error) => { throw error; });
    assert.equal(res.code, 200);
    assert.equal(res.body.data[0].cover_url, cover);
    assert.match(sql, /b\.cover_url/);
  } finally {
    pool.query = oldQuery;
  }
});
