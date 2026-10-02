/** Whether a pharmacy is open right now, in Bangladesh time. The owner's switch can only close it early;
 *  it never opens it outside its set hours or on its weekly off day. */
const DAYS: [RegExp, number][] = [
  [/রবি|sun/i, 0], [/সোম|mon/i, 1], [/মঙ্গল|tue/i, 2], [/বুধ|wed/i, 3],
  [/বৃহস্পতি|thu/i, 4], [/শুক্র|fri/i, 5], [/শনি|sat/i, 6],
];
const PART_OF_DAY = /সকাল|দুপুর|বিকাল|বিকেল|সন্ধ্যা|রাত|morning|noon|afternoon|evening|night/i;

export type ClosedReason = 'manual' | 'hours' | 'weekly' | null;

export function openStatus(
  p: { isOpen: boolean; openFrom: string; openTo: string; weeklyOff: string | null },
  now = new Date(),
): { open: boolean; reason: ClosedReason } {
  if (!p.isOpen) return { open: false, reason: 'manual' };
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Dhaka', weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(now);
  const get = (t: string) => parts.find((x) => x.type === t)!.value;
  const dow = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(get('weekday'));
  const mins = Number(get('hour')) * 60 + Number(get('minute'));

  // A whole-day closure only: "শুক্রবার". Partial notes like "শুক্রবার দুপুর" are shown but not enforced.
  if (p.weeklyOff && !PART_OF_DAY.test(p.weeklyOff) && DAYS.some(([re, d]) => d === dow && re.test(p.weeklyOff!))) {
    return { open: false, reason: 'weekly' };
  }
  const toMin = (s: string) => Number(s.slice(0, 2)) * 60 + Number(s.slice(3, 5));
  const a = toMin(p.openFrom), b = toMin(p.openTo);
  const within = a === b ? true : a < b ? mins >= a && mins < b : mins >= a || mins < b; // overnight hours supported
  return within ? { open: true, reason: null } : { open: false, reason: 'hours' };
}
