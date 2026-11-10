const { test } = require('node:test');
process.env.JWT_SECRET = 'staff-auth-test-only-key';
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const {
  requireAdminKey,
  requireAdminKeyIfConfigured,
  requireStaff,
  staffCanAccessSchool,
} = require('../src/middlewares/staff.middleware');

function run(mw, headers = {}) {
  const req = { headers };
  const res = { statusCode: 200, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; } };
  let passed = false;
  mw(req, res, () => { passed = true; });
  return { req, res, passed };
}
const token = (payload) => `Bearer ${jwt.sign(payload, process.env.JWT_SECRET)}`;
const withKey = (key, fn) => {
  const old = process.env.ADMIN_API_KEY;
  if (key === undefined) delete process.env.ADMIN_API_KEY; else process.env.ADMIN_API_KEY = key;
  try { return fn(); } finally { if (old === undefined) delete process.env.ADMIN_API_KEY; else process.env.ADMIN_API_KEY = old; }
};

test('user management is closed when no admin key is configured', () => withKey(undefined, () => {
  assert.equal(run(requireAdminKey).passed, false);
  assert.equal(run(requireAdminKey).res.statusCode, 403);
  assert.equal(run(requireAdminKey, { 'x-admin-key': '' }).passed, false);
  // personel oturumu yönetici anahtarının yerini tutmaz
  assert.equal(run(requireAdminKey, { authorization: token({ role: 'admin', school_code: '1' }) }).passed, false);
}));

test('admin key must match exactly', () => withKey('dogru-anahtar', () => {
  assert.equal(run(requireAdminKey, { 'x-admin-key': 'dogru-anahtar' }).passed, true);
  assert.equal(run(requireAdminKey, { 'x-admin-key': 'yanlis-anahtar' }).res.statusCode, 401);
  assert.equal(run(requireAdminKey, { 'x-admin-key': 'dogru' }).passed, false);
  assert.equal(run(requireAdminKey).passed, false);
}));

test('admin routes stay open until a key is configured, then require it', () => {
  withKey(undefined, () => assert.equal(run(requireAdminKeyIfConfigured).passed, true));
  withKey('k1', () => {
    assert.equal(run(requireAdminKeyIfConfigured).passed, false);
    assert.equal(run(requireAdminKeyIfConfigured, { 'x-admin-key': 'k1' }).passed, true);
  });
});

test('staff routes reject anonymous, student and forged tokens', () => withKey(undefined, () => {
  assert.equal(run(requireStaff).res.statusCode, 401);
  assert.equal(run(requireStaff, { authorization: token({ role: 'student', school_code: '1' }) }).passed, false);
  const forged = `Bearer ${jwt.sign({ role: 'teacher', school_code: '1' }, 'baska-anahtar')}`;
  assert.equal(run(requireStaff, { authorization: forged }).passed, false);
  assert.equal(run(requireStaff, { authorization: 'Bearer bozuk' }).passed, false);
}));

test('staff may only touch their own school', () => withKey(undefined, () => {
  const { req, passed } = run(requireStaff, { authorization: token({ role: 'teacher', school_code: '764135' }) });
  assert.equal(passed, true);
  assert.equal(staffCanAccessSchool(req, '764135'), true);
  assert.equal(staffCanAccessSchool(req, 764135), true);
  assert.equal(staffCanAccessSchool(req, '111'), false);
}));

test('platform admin key may act on any school', () => withKey('k1', () => {
  const { req, passed } = run(requireStaff, { 'x-admin-key': 'k1' });
  assert.equal(passed, true);
  assert.equal(staffCanAccessSchool(req, '111'), true);
}));
