/**
 * Break-aware slot generation (SPEC.md §5.2, P0-2).
 *
 * Packs 30-minute lessons into a shift around Mia's stamina rules:
 * ≤ maxConsecutive lessons in a row, then a micro-break; one lunch per
 * shift at the break boundary nearest the shift midpoint. Off-grid start
 * times (11:40, 13:40, …) are expected — the UI shows exact times.
 *
 * Pure function over minutes-from-shift-start so it's trivially testable;
 * the caller maps minutes onto real timestamptz values per shift date.
 * Regeneration must never delete booked slots — that diffing lives in the
 * persistence layer, not here.
 */

export interface ShiftRules {
  /** Shift length in minutes, e.g. 480 for 10:00–18:00. */
  shiftMinutes: number;
  lessonMinutes?: number; // default 30
  maxConsecutive?: number; // default 3
  microBreakMinutes?: number; // default 10
  lunchMinutes?: number; // default 30
}

export interface GeneratedSlot {
  kind: 'lesson' | 'break' | 'lunch';
  /** Minutes from shift start. */
  startMin: number;
  endMin: number;
}

export function generateShiftSlots(rules: ShiftRules): GeneratedSlot[] {
  const lesson = rules.lessonMinutes ?? 30;
  const maxRun = rules.maxConsecutive ?? 3;
  const microBreak = rules.microBreakMinutes ?? 10;
  const lunch = rules.lunchMinutes ?? 30;
  const midpoint = rules.shiftMinutes / 2;

  const slots: GeneratedSlot[] = [];
  let cursor = 0;
  let run = 0;
  let lunchPlaced = false;

  while (cursor + lesson <= rules.shiftMinutes) {
    if (run === maxRun) {
      // Break due. It becomes the lunch when this boundary is at least as
      // close to the shift midpoint as the next one would be — i.e. the
      // closest boundary without splitting a run. Mia can drag it, and an
      // organically unfilled slot can become the lunch later (§5.2).
      const nextBoundary = cursor + microBreak + maxRun * lesson;
      const isLunch =
        !lunchPlaced &&
        Math.abs(cursor - midpoint) <= Math.abs(nextBoundary - midpoint);
      const len = isLunch ? lunch : microBreak;
      if (isLunch) lunchPlaced = true;
      slots.push({ kind: isLunch ? 'lunch' : 'break', startMin: cursor, endMin: cursor + len });
      cursor += len;
      run = 0;
      continue;
    }
    slots.push({ kind: 'lesson', startMin: cursor, endMin: cursor + lesson });
    cursor += lesson;
    run += 1;
  }

  return slots;
}

/** Count of bookable lessons in a generated shift. */
export function lessonCount(slots: GeneratedSlot[]): number {
  return slots.filter((s) => s.kind === 'lesson').length;
}
