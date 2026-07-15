-- Mia Swim — initial schema (SPEC.md §9)
-- Conventions: money in integer cents; all timestamps timestamptz; RLS on every table.
-- Tier invisibility (§5.1 / P0-4): `accounts.tier` is never granted to the
-- authenticated role — clients read their own account through the
-- `client_account` view, which excludes tier. All eligibility logic (tier
-- windows, prime gating, grants) runs server-side with the service role.

create type account_role as enum ('admin', 'client');
create type account_status as enum ('pending', 'approved', 'waitlist', 'archived');
create type client_tier as enum ('A', 'B', 'C');
create type slot_kind as enum ('lesson', 'break', 'lunch');
create type slot_status as enum ('open', 'held', 'booked', 'blocked');
create type booking_status as enum (
  'pending_payment', 'confirmed', 'pending_client_confirmation',
  'cancelled', 'completed', 'no_show'
);
create type paid_via as enum ('checkout', 'package_credit');
create type payment_channel as enum ('online', 'in_person');
create type payment_status as enum ('paid', 'refunded', 'partial_refund');
create type cancel_category as enum ('medical_emergency', 'family_emergency', 'other');
create type grant_target as enum ('tier', 'account');
create type gap_cause as enum ('cancel', 'unsold');
create type gap_resolution as enum ('blast', 'compaction', 'call', 'became_lunch', 'expired');
create type message_channel as enum ('email', 'sms');

-- DORMANT (§3, P2): one seeded row for Mia; no v1 UI. Kept so a second
-- instructor is a feature flag, not a migration.
create table instructors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table seasons (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  start_date date not null,
  end_date date not null,
  check (end_date > start_date)
);

create table accounts (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  name text not null,
  phone text,
  role account_role not null default 'client',
  tier client_tier not null default 'C',            -- NEVER exposed to clients
  status account_status not null default 'pending', -- Mia approves (P0-1)
  rate_cents integer not null default 4500,         -- per-account rate (§5.4)
  sms_opt_in boolean not null default false,
  opening_alerts_opt_in boolean not null default true,
  stripe_customer_id text,
  created_at timestamptz not null default now()
);

create table swimmers (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts (id) on delete cascade,
  name text not null,
  birth_year integer,
  notes text, -- level, goals
  created_at timestamptz not null default now()
);

-- Prepaid 3-pack, use-it-or-lose-it (§5.4, P0-15)
create table packages (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts (id),
  season_id uuid not null references seasons (id),
  lessons_total integer not null default 3,
  lessons_used integer not null default 0,
  discount_pct numeric not null default 5,
  price_cents integer not null,
  stripe_checkout_id text,
  purchased_at timestamptz not null default now(),
  expires_at timestamptz not null, -- season end; expiry cron zeroes remainder
  check (lessons_used >= 0 and lessons_used <= lessons_total)
);

create table shift_templates (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references seasons (id),
  instructor_id uuid not null references instructors (id),
  weekday integer not null check (weekday between 0 and 6), -- 0 = Sunday
  start_time time not null,
  end_time time not null,
  max_consecutive integer not null default 3,
  micro_break_min integer not null default 10,
  lunch_min integer not null default 30,
  check (end_time > start_time)
);

create table slots (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references seasons (id),
  instructor_id uuid not null references instructors (id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  is_prime boolean not null default false, -- prime gating (§5.1)
  kind slot_kind not null default 'lesson',
  status slot_status not null default 'open',
  hold_expires_at timestamptz, -- 10-min checkout hold (P0-5)
  unique (instructor_id, starts_at), -- double-booking guard
  check (ends_at > starts_at)
);

-- Season-open grants: tier- or account-targeted booking windows (§5.1)
create table booking_grants (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references seasons (id),
  target grant_target not null,
  tier client_tier,
  account_id uuid references accounts (id),
  opens_at timestamptz not null,
  expires_at timestamptz not null,
  notified_at timestamptz,
  check (
    (target = 'tier' and tier is not null and account_id is null) or
    (target = 'account' and account_id is not null and tier is null)
  )
);

create table bookings (
  id uuid primary key default gen_random_uuid(),
  slot_id uuid not null unique references slots (id), -- one booking per slot
  account_id uuid not null references accounts (id),
  swimmer_id uuid not null references swimmers (id),
  checkout_group_id uuid not null, -- links sibling/hour multi-slot checkouts (§5.6)
  paid_via paid_via not null default 'checkout',
  package_id uuid references packages (id),
  status booking_status not null default 'pending_payment',
  price_cents integer not null,
  cancelled_at timestamptz,
  cancel_category cancel_category,
  cancel_note text,
  fee_waived boolean not null default false,
  waived_by uuid references accounts (id),
  created_at timestamptz not null default now()
);
create index bookings_account_idx on bookings (account_id);
create index bookings_group_idx on bookings (checkout_group_id);

create table payments (
  id uuid primary key default gen_random_uuid(),
  checkout_group_id uuid not null,
  stripe_checkout_id text,
  stripe_payment_intent text,
  amount_cents integer not null,
  channel payment_channel not null default 'online', -- in_person arrives in P2
  status payment_status not null default 'paid',
  refunded_at timestamptz,
  created_at timestamptz not null default now()
);
create index payments_group_idx on payments (checkout_group_id);

create table waitlist (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references seasons (id),
  account_id uuid not null references accounts (id),
  preferred_days integer[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (season_id, account_id)
);

-- Every gap and its resolution, so Mia learns which tactics fill slots (§5.3)
create table gap_events (
  id uuid primary key default gen_random_uuid(),
  slot_id uuid not null references slots (id),
  detected_at timestamptz not null default now(),
  cause gap_cause not null,
  resolved_by gap_resolution,
  resolved_at timestamptz
);

create table messages_log (
  id uuid primary key default gen_random_uuid(),
  account_id uuid references accounts (id),
  channel message_channel not null,
  template text not null,
  sent_at timestamptz not null default now(),
  provider_id text
);

-- Tunables Mia controls without a deploy (§9): tier window days, prime
-- cutoff hours, confirm window, grant default days, package window end,
-- cancel cutoff, season dates.
create table app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table instructors enable row level security;
alter table seasons enable row level security;
alter table accounts enable row level security;
alter table swimmers enable row level security;
alter table packages enable row level security;
alter table shift_templates enable row level security;
alter table slots enable row level security;
alter table booking_grants enable row level security;
alter table bookings enable row level security;
alter table payments enable row level security;
alter table waitlist enable row level security;
alter table gap_events enable row level security;
alter table messages_log enable row level security;
alter table app_config enable row level security;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from accounts where id = auth.uid() and role = 'admin'
  );
$$;

-- Admin: full access everywhere.
create policy admin_all_instructors on instructors for all using (is_admin());
create policy admin_all_seasons on seasons for all using (is_admin());
create policy admin_all_accounts on accounts for all using (is_admin());
create policy admin_all_swimmers on swimmers for all using (is_admin());
create policy admin_all_packages on packages for all using (is_admin());
create policy admin_all_shift_templates on shift_templates for all using (is_admin());
create policy admin_all_slots on slots for all using (is_admin());
create policy admin_all_booking_grants on booking_grants for all using (is_admin());
create policy admin_all_bookings on bookings for all using (is_admin());
create policy admin_all_payments on payments for all using (is_admin());
create policy admin_all_waitlist on waitlist for all using (is_admin());
create policy admin_all_gap_events on gap_events for all using (is_admin());
create policy admin_all_messages_log on messages_log for all using (is_admin());
create policy admin_all_app_config on app_config for all using (is_admin());

-- Clients: own rows only. No client policy on slots/grants/app_config —
-- slot eligibility is computed server-side so tier logic never leaks (P0-4).
create policy own_account on accounts for select using (id = auth.uid());
create policy own_swimmers on swimmers for all
  using (account_id = auth.uid()) with check (account_id = auth.uid());
create policy own_packages on packages for select using (account_id = auth.uid());
create policy own_bookings on bookings for select using (account_id = auth.uid());
create policy own_waitlist on waitlist for select using (account_id = auth.uid());
create policy own_payments on payments for select using (
  checkout_group_id in (select checkout_group_id from bookings where account_id = auth.uid())
);

-- Tier invisibility, enforced at the column level: authenticated clients can
-- only select these accounts columns. `tier` (and `status`/`rate_cents`
-- internals) require the service role.
revoke select on accounts from authenticated;
grant select (id, email, name, phone, sms_opt_in, opening_alerts_opt_in)
  on accounts to authenticated;
