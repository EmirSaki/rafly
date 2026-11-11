const { test } = require('node:test');
const assert = require('node:assert/strict');
const { wrapPool, isIdempotentDdl } = require('../src/utils/ddlOnce');

function fakePool() {
  const calls = [];
  const pool = {
    calls,
    failNext: false,
    async query(text, ...rest) {
      calls.push(text);
      if (pool.failNext) { pool.failNext = false; throw new Error('boom'); }
      return { rows: [{ ok: 1 }], rowCount: 1 };
    },
    async connect() {
      return { async query(text) { calls.push('client:' + text); return { rows: [], rowCount: 0 }; } };
    },
  };
  return pool;
}

const ALTER = 'ALTER TABLE school_1.users ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)';

test('hangi komutlar idempotent sayılır', () => {
  assert.ok(isIdempotentDdl(ALTER));
  assert.ok(isIdempotentDdl('\n  ALTER TABLE public.users\n  ADD COLUMN IF NOT EXISTS password_set BOOLEAN DEFAULT FALSE\n'));
  assert.ok(!isIdempotentDdl('ALTER TABLE a.b DROP COLUMN x'));
  assert.ok(!isIdempotentDdl('ALTER TABLE a.b ADD COLUMN IF NOT EXISTS x INT, DROP COLUMN y'));
  assert.ok(!isIdempotentDdl('ALTER TABLE a.b ALTER COLUMN x TYPE TEXT'));
  assert.ok(!isIdempotentDdl('SELECT 1'));
  assert.ok(!isIdempotentDdl(undefined));
});

test('aynı ALTER ikinci kez veritabanına gitmez, normal sorgular her zaman gider', async () => {
  const pool = wrapPool(fakePool());
  await pool.query(ALTER);
  await pool.query(ALTER);
  await pool.query(ALTER);
  assert.equal(pool.calls.filter((c) => c === ALTER).length, 1);
  await pool.query('SELECT 1');
  await pool.query('SELECT 1');
  assert.equal(pool.calls.filter((c) => c === 'SELECT 1').length, 2);
});

test('hata verirse işaretlenmez, tekrar denenir', async () => {
  const pool = wrapPool(fakePool());
  pool.failNext = true;
  await assert.rejects(() => pool.query(ALTER));
  await pool.query(ALTER);
  await pool.query(ALTER);
  assert.equal(pool.calls.filter((c) => c === ALTER).length, 2);
});

test('farklı şema aynı komut sayılmaz', async () => {
  const pool = wrapPool(fakePool());
  await pool.query(ALTER);
  await pool.query(ALTER.replace('school_1', 'school_2'));
  assert.equal(pool.calls.length, 2);
});

test('parametreli sorgu ve client: client yalnızca pool ile yapılmış komutu atlar', async () => {
  const pool = wrapPool(fakePool());
  const client = await pool.connect();
  await client.query(ALTER);              // henüz yapılmadı -> çalışır (transaction içinde olabilir)
  await client.query(ALTER);              // client yolu asla işaretlemez -> yine çalışır
  assert.equal(pool.calls.filter((c) => c === 'client:' + ALTER).length, 2);
  await pool.query(ALTER);                // pool ile başarıyla yapıldı
  await client.query(ALTER);              // artık atlanır
  assert.equal(pool.calls.filter((c) => c === 'client:' + ALTER).length, 2);
});
