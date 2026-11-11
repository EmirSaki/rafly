const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const {
  validateNewPassword, signSetupToken, verifySetupToken, createLoginThrottle,
} = require('../src/utils/studentPassword');

test('şifre kuralları', () => {
  assert.ok(validateNewPassword('12345'));
  assert.ok(validateNewPassword('1234'));
  assert.ok(validateNewPassword('111111'));
  assert.ok(validateNewPassword(undefined));
  assert.ok(validateNewPassword('a'.repeat(73)));
  assert.equal(validateNewPassword('kitap-2026'), null);
  assert.equal(validateNewPassword('123456'), null);
});

test('kurulum anahtarı: geçerli anahtar çözülür, oturum anahtarı kabul edilmez', () => {
  assert.equal(verifySetupToken(signSetupToken({ user_id: 7 })).user_id, 7);
  const sessionToken = jwt.sign({ user_id: 7, role: 'student' }, process.env.JWT_SECRET || 'dev_secret');
  assert.equal(verifySetupToken(sessionToken), null);
  assert.equal(verifySetupToken('bozuk'), null);
  assert.equal(verifySetupToken(undefined), null);
  const expired = jwt.sign({ purpose: 'student_password_setup', user_id: 7 }, process.env.JWT_SECRET || 'dev_secret', { expiresIn: -5 });
  assert.equal(verifySetupToken(expired), null);
});

test('deneme sınırı: limitte engeller, pencere geçince açar, reset temizler', () => {
  let t = 0;
  const th = createLoginThrottle({ max: 3, windowMs: 1000, now: () => t });
  for (let i = 0; i < 3; i++) { assert.equal(th.blocked('k'), false); th.fail('k'); }
  assert.equal(th.blocked('k'), true);
  assert.equal(th.blocked('baska'), false);
  t = 1500;
  assert.equal(th.blocked('k'), false);
  th.fail('k'); th.fail('k'); th.fail('k');
  th.reset('k');
  assert.equal(th.blocked('k'), false);
});
