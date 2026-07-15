/**
 * Typed access to `app_config` (SPEC.md §9) — Mia's tunables.
 * Defaults mirror supabase/seed.sql; the DB row always wins.
 * OPEN spec items (§12) keep working defaults until Mia confirms.
 */

export interface AppConfig {
  tier_window_days: { A: number; B: number; C: number };
  prime_cutoff_hours: number;
  confirm_window_hours: number;
  grant_default_days: number;
  cancel_cutoff_hours: number;
  checkout_hold_minutes: number;
  package_lessons: number;
  package_discount_pct: number;
  /** ISO timestamp; null = package window closed (à la carte only). */
  package_window_end: string | null;
  call_list_trigger_hours: number;
  active_season_id: string;
}

export const CONFIG_DEFAULTS: AppConfig = {
  tier_window_days: { A: 21, B: 14, C: 7 },
  prime_cutoff_hours: 72,
  confirm_window_hours: 48,
  grant_default_days: 7,
  cancel_cutoff_hours: 24,
  checkout_hold_minutes: 10,
  package_lessons: 3,
  package_discount_pct: 5,
  package_window_end: null,
  call_list_trigger_hours: 48,
  active_season_id: '',
};

/** 3-pack price: rate × lessons × (1 − discount), rounded to a cent (§5.4). */
export function packagePriceCents(
  rateCents: number,
  lessons = CONFIG_DEFAULTS.package_lessons,
  discountPct = CONFIG_DEFAULTS.package_discount_pct,
): number {
  return Math.round(rateCents * lessons * (1 - discountPct / 100));
}
