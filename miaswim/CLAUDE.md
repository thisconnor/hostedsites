# Mia Swim

Booking, scheduling & payments platform for a solo private swim tutor.
**The full build spec is `docs/SPEC.md` — read it before any feature work.**
Build in the Phase 1 order in SPEC.md §11; decisions marked **OPEN** need
Connor/Mia input.

## Stack (SPEC.md §8)

Next.js 14+ App Router (TypeScript) · Supabase (Postgres + RLS + magic-link
auth) · Stripe Checkout + webhooks · Resend email (Twilio SMS in Phase 2) ·
Tailwind theme tokens + Framer Motion · Vercel hosting + Cron.

## Hard rules

- **Tier invisibility (P0-4):** no client-facing response — UI or API — may
  contain tier data. Eligibility is computed server-side (service role);
  clients only ever see which slots are bookable for them.
- **Double-booking:** enforced by DB constraints (`slots` unique on
  instructor+start, `bookings.slot_id` unique), never by application checks
  alone.
- **Money:** integer cents everywhere. Rates are per-account
  (`accounts.rate_cents`).
- **Regenerating a shift never deletes booked slots** (P0-2).
- Keep `instructor_id` plumbed through schedule tables (dormant multi-
  instructor support) but build no instructor UI.

## Layout

- `supabase/migrations/` — schema + RLS (source of truth for the data model)
- `supabase/seed.sql` — Mia's instructor row, season, `app_config` defaults
- `src/lib/slots/generate.ts` — break-aware slot generation (§5.2), pure +
  unit-tested (`npm test`)
- `src/lib/config.ts` — typed `app_config` keys and defaults
- `src/app/` — public site, `/book`, `/portal`, `/admin` (one repo)

## Commands

`npm run dev` · `npm test` (vitest) · `npm run typecheck`
