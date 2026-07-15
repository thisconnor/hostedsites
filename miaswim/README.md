# Mia Swim

Booking, scheduling & payments platform for a solo private swim tutor —
clients book and pay online at per-account rates, tiered booking windows
open on Mia's schedule, and cancellations trigger an aggressive gap-fill
engine. Full spec: [`docs/SPEC.md`](docs/SPEC.md).

## Stack

Next.js 14 (App Router, TS) · Supabase (Postgres, RLS, magic links) ·
Stripe Checkout · Resend · Tailwind + Framer Motion · Vercel (+ Cron).

## Getting started

```bash
npm install
cp .env.example .env.local   # fill in Supabase / Stripe / Resend keys
npm run dev
```

Database: apply `supabase/migrations/` then `supabase/seed.sql` (via
`supabase db reset` locally or the SQL editor on hosted Supabase).

## Status

Phase 1 in progress, following the build order in SPEC.md §11:

- [x] Project scaffold (Next.js, Tailwind theme tokens, vitest)
- [x] Schema + RLS (`supabase/migrations/0001_initial_schema.sql`)
- [x] Seed: instructor, season, `app_config` defaults, Mon/Thu shift templates
- [x] Break-aware slot generation (`src/lib/slots/generate.ts`, unit-tested)
- [ ] Auth / approval / waitlist
- [ ] Tier/grant-gated slot query
- [ ] Checkout + webhook … (see SPEC.md §11 for the rest)
