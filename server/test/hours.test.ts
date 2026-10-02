import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openStatus } from '../src/hours';

const p = (o: Partial<{ isOpen: boolean; openFrom: string; openTo: string; weeklyOff: string | null }> = {}) =>
  ({ isOpen: true, openFrom: '09:00', openTo: '22:00', weeklyOff: null, ...o });
// Asia/Dhaka is UTC+6. 2026-10-02 is a Friday.
const at = (iso: string) => new Date(iso);

test('open only inside hours (Dhaka time), switch can only close', () => {
  assert.deepEqual(openStatus(p(), at('2026-10-02T05:25:00Z')), { open: true, reason: null });   // 11:25
  assert.deepEqual(openStatus(p(), at('2026-10-02T17:25:00Z')), { open: false, reason: 'hours' }); // 23:25
  assert.deepEqual(openStatus(p({ isOpen: false }), at('2026-10-02T05:25:00Z')), { open: false, reason: 'manual' });
});
test('weekly off day (whole day only) and overnight hours', () => {
  assert.equal(openStatus(p({ weeklyOff: 'শুক্রবার' }), at('2026-10-02T05:25:00Z')).reason, 'weekly');
  assert.equal(openStatus(p({ weeklyOff: 'Friday' }), at('2026-10-03T05:25:00Z')).open, true);       // Saturday
  assert.equal(openStatus(p({ weeklyOff: 'শুক্রবার দুপুর' }), at('2026-10-02T05:25:00Z')).open, true); // partial: not enforced
  assert.equal(openStatus(p({ openFrom: '18:00', openTo: '02:00' }), at('2026-10-02T19:00:00Z')).open, true); // 01:00 next day
});
