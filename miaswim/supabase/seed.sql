-- Seed: Mia (dormant instructor row), season, spec-default config (SPEC.md §5, §9).
-- OPEN items keep the spec's working defaults until Mia confirms (§12).

insert into instructors (id, name, active)
values ('00000000-0000-0000-0000-000000000001', 'Mia', true);

insert into seasons (id, label, start_date, end_date)
values ('00000000-0000-0000-0000-000000000010', 'Summer 2026', '2026-06-01', '2026-08-31');

insert into app_config (key, value) values
  ('tier_window_days',        '{"A": 21, "B": 14, "C": 7}'), -- OPEN: Mia confirms
  ('prime_cutoff_hours',      '72'),
  ('confirm_window_hours',    '48'),                          -- OPEN
  ('grant_default_days',      '7'),                           -- OPEN
  ('cancel_cutoff_hours',     '24'),
  ('checkout_hold_minutes',   '10'),
  ('package_lessons',         '3'),
  ('package_discount_pct',    '5'),
  ('package_window_end',      'null'),                        -- set when Mia opens the season
  ('call_list_trigger_hours', '48'),
  ('active_season_id',        '"00000000-0000-0000-0000-000000000010"');

-- Mia's preferred shift days (§5.2): Monday + Thursday, 10:00–18:00.
insert into shift_templates (season_id, instructor_id, weekday, start_time, end_time)
values
  ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001', 1, '10:00', '18:00'),
  ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001', 4, '10:00', '18:00');
