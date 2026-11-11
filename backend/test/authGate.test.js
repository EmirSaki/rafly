const { test } = require('node:test');
process.env.JWT_SECRET = 'auth-gate-test-only-key';
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { authGate, decide, classify } = require('../src/middlewares/auth.gate');

const bearer = (payload) => `Bearer ${jwt.sign(payload, process.env.JWT_SECRET)}`;
const staff = bearer({ role: 'teacher', school_code: '764135' });
const student = bearer({ role: 'student', school_code: '764135' });
const req = (method, path, { auth, query = {}, body } = {}) => ({
  method, path, query, body, headers: auth ? { authorization: auth } : {},
});

test('routes are classified by sensitivity', () => {
  assert.equal(classify('POST', '/api/users/login'), 'public');
  assert.equal(classify('POST', '/api/students/login'), 'public');
  assert.equal(classify('GET', '/api/schools/764135/logo'), 'public');
  assert.equal(classify('POST', '/api/schools/764135/logo'), 'staff');
  assert.equal(classify('GET', '/api/schools/764135/books'), 'member');
  assert.equal(classify('GET', '/api/schools/764135/books/isbn/9786050000000'), 'member');
  assert.equal(classify('GET', '/api/schools/764135/books/export'), 'staff');
  assert.equal(classify('POST', '/api/schools/764135/books'), 'staff');
  assert.equal(classify('GET', '/api/announcements'), 'member');
  assert.equal(classify('POST', '/api/announcements'), 'staff');
  assert.equal(classify('GET', '/api/students'), 'staff');
  assert.equal(classify('DELETE', '/api/students'), 'staff');
  assert.equal(classify('POST', '/api/students/import'), 'staff');
  assert.equal(classify('POST', '/api/students/bulk-passwords'), 'staff');
  assert.equal(classify('GET', '/api/students/profile'), 'self');
  assert.equal(classify('GET', '/api/reservations'), 'staff');
  assert.equal(classify('POST', '/api/reservations/loan-by-student'), 'staff');
  assert.equal(classify('PATCH', '/api/reservations/12/return'), 'staff');
  assert.equal(classify('GET', '/api/schools/764135/report-cards'), 'staff');
  assert.equal(classify('GET', '/api/admin/schools'), 'self');
  assert.equal(classify('GET', '/api/users'), 'self');
  assert.equal(classify('GET', '/api/bilinmeyen'), 'staff');
});

test('anonymous requests to staff and member routes are refused', () => {
  assert.equal(decide(req('GET', '/api/students', { query: { schoolCode: '764135' } })).status, 401);
  assert.equal(decide(req('GET', '/api/schools/764135/books')).status, 401);
  assert.equal(decide(req('GET', '/api/students', { auth: 'Bearer bozuk' })).status, 401);
  assert.equal(decide(req('POST', '/api/users/login')).ok, true);
});

test('students may read books and announcements but not staff data', () => {
  assert.equal(decide(req('GET', '/api/schools/764135/books', { auth: student })).ok, true);
  assert.equal(decide(req('GET', '/api/announcements', { auth: student, query: { schoolCode: '764135' } })).ok, true);
  assert.equal(decide(req('GET', '/api/students', { auth: student, query: { schoolCode: '764135' } })).reason, 'personel-degil');
  assert.equal(decide(req('POST', '/api/reservations/loan-by-student', { auth: student, body: { schoolCode: '764135' } })).status, 403);
});

test('staff are limited to their own school', () => {
  assert.equal(decide(req('GET', '/api/students', { auth: staff, query: { schoolCode: '764135' } })).ok, true);
  assert.equal(decide(req('GET', '/api/students', { auth: staff, query: { schoolCode: '111' } })).reason, 'baska-okul');
  assert.equal(decide(req('GET', '/api/schools/111/books', { auth: staff })).reason, 'baska-okul');
  assert.equal(decide(req('POST', '/api/reservations/loan-by-student', { auth: staff, body: { schoolCode: '111' } })).reason, 'baska-okul');
  assert.equal(decide(req('PATCH', '/api/reservations/5/return', { auth: staff })).ok, true);
});

function run(r, mode) {
  const old = process.env.AUTH_MODE;
  if (mode) process.env.AUTH_MODE = mode; else delete process.env.AUTH_MODE;
  const res = { statusCode: 200, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; } };
  let passed = false;
  const warn = console.warn; console.warn = () => {};
  try { authGate(r, res, () => { passed = true; }); }
  finally { console.warn = warn; if (old === undefined) delete process.env.AUTH_MODE; else process.env.AUTH_MODE = old; }
  return { passed, res };
}

test('transition mode lets old clients through, enforce mode blocks them', () => {
  const anon = req('GET', '/api/students', { query: { schoolCode: '764135' } });
  assert.equal(run(anon).passed, true);
  const enforced = run(anon, 'enforce');
  assert.equal(enforced.passed, false);
  assert.equal(enforced.res.statusCode, 401);
  assert.equal(run(req('GET', '/api/students', { auth: staff, query: { schoolCode: '764135' } }), 'enforce').passed, true);
  assert.equal(run(req('POST', '/api/students/login'), 'enforce').passed, true);
});
