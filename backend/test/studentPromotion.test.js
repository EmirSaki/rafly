const { test } = require('node:test');
const assert = require('node:assert/strict');
const { buildPromotionPlan, snapshot } = require('../src/services/studentPromotion');
const row = (id, number, full_name, class_name = '6A', school_level = 'ortaokul') => ({ student_id: id, student_number: number, full_name, class_name, class_code: class_name, school_level });

test('kural matches full name and number, preserving the original ID', () => {
  const old = row(42, '001', 'Ali Veli Yılmaz');
  const plan = buildPromotionPlan([old], [row(undefined, '001', ' ALİ   VELİ YILMAZ ', '7B')], 'all');
  assert.equal(plan.updated[0].before.student_id, 42);
  assert.equal(plan.updated[0].after.class_name, '7B');
  assert.equal(plan.removed.length, 0);
  assert.equal(plan.added.length, 0);
  assert.equal(old.class_name, '6A');
});
test('same number with different name is never matched', () => {
  const p = buildPromotionPlan([row(1, '12', 'Ayşe Ak')], [row(null, '12', 'Fatma Ak')], 'all');
  assert.equal(p.updated.length, 0); assert.equal(p.removed.length, 1); assert.equal(p.added.length, 1);
});
test('matched grade 8 keeps identity across levels, missing 8 and 12 are exported', () => {
  const p = buildPromotionPlan([row(1, '1', 'Ali Ak', '8A'), row(2, '2', 'Veli Ak', '8B'), row(3, '3', 'Ece Ak', '12A', 'lise')], [row(null, '1', 'Ali Ak', '9A', 'lise')], 'all');
  assert.equal(p.updated.length, 1); assert.deepEqual(p.removed.map(r => r.student_id), [2, 3]);
});
test('level scope never removes another level', () => {
  const p = buildPromotionPlan([row(1, '1', 'Ali Ak'), row(2, '2', 'Ece Ak', '12A', 'lise')], [row(null, '1', 'Ali Ak', '7A')], 'ortaokul');
  assert.equal(p.removed.length, 0);
});
test('empty or duplicated incoming input aborts instead of silently deleting', () => {
  const s = row(1, '1', 'Ali Ak');
  assert.throws(() => buildPromotionPlan([s], [], 'all'));
  assert.throws(() => buildPromotionPlan([s], [s, s], 'all'));
});
test('duplicates in the existing roster are merged into one survivor', () => {
  const a = row(1, '1', 'Ali Ak');
  const b = row(2, '1', 'Ali Ak');
  const p = buildPromotionPlan([a, b], [a], 'all');
  assert.equal(p.merges.length, 1);
  assert.equal(p.merges[0].duplicates.length, 1);
});
test('scope mismatch and final same-class number collisions abort', () => {
  const s = row(1, '1', 'Ali Ak');
  assert.throws(() => buildPromotionPlan([], [s], 'lise'));
  assert.throws(() => buildPromotionPlan([], [s, row(2, '1', 'Veli Ak')], 'all'));
  assert.throws(() => buildPromotionPlan([s], [row(null, '1', 'Ali Ak', '9A', 'lise')], 'lise'));
});
test('snapshot invalidates preview on a roster or account change', () => {
  assert.notEqual(snapshot([row(1, '1', 'Ali Ak')], []), snapshot([row(1, '1', 'Ali Ak', '7B')], []));
  assert.notEqual(snapshot([], []), snapshot([], [{ user_id: 5 }]));
});
