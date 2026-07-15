import { describe, expect, it } from 'vitest';
import { generateShiftSlots, lessonCount } from './generate';

describe('generateShiftSlots', () => {
  const eightHour = generateShiftSlots({ shiftMinutes: 480 });

  it('packs ~13 lessons into an 8-hour shift (§5.2)', () => {
    expect(lessonCount(eightHour)).toBeGreaterThanOrEqual(13);
    expect(lessonCount(eightHour)).toBeLessThanOrEqual(14);
  });

  it('never exceeds 3 consecutive lessons', () => {
    let run = 0;
    for (const s of eightHour) {
      run = s.kind === 'lesson' ? run + 1 : 0;
      expect(run).toBeLessThanOrEqual(3);
    }
  });

  it('places exactly one lunch, near the middle', () => {
    const lunches = eightHour.filter((s) => s.kind === 'lunch');
    expect(lunches).toHaveLength(1);
    expect(Math.abs(lunches[0].startMin - 240)).toBeLessThanOrEqual(60);
  });

  it('is contiguous, fits the shift, and never ends on a break', () => {
    for (let i = 1; i < eightHour.length; i++) {
      expect(eightHour[i].startMin).toBe(eightHour[i - 1].endMin);
    }
    const last = eightHour[eightHour.length - 1];
    expect(last.kind).toBe('lesson');
    expect(last.endMin).toBeLessThanOrEqual(480);
  });

  it('produces off-grid start times (breaks shift the grid)', () => {
    const offGrid = eightHour.filter(
      (s) => s.kind === 'lesson' && s.startMin % 30 !== 0,
    );
    expect(offGrid.length).toBeGreaterThan(0);
  });
});
