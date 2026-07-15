# Mia Swim -- Booking, Scheduling & Payments Platform

> Build spec / project seed for Claude Code. Drop this into the repo root (or reference from CLAUDE.md) and build in phases. Decisions marked **OPEN** need Connor/Mia input before or during that phase.

---

## 1. Problem Statement

Mia is a solo private swim tutor who teaches summers at her community pool, working 2--3 days a week (preferred: Monday and Thursday, flexing to Tuesday/Wednesday on demand) in roughly 8-hour shifts of 30-minute lessons at $45 per session. Her schedule lives entirely on paper, payments are collected manually, and cancellations force her to manually rearrange the week and text clients one by one. She needs a single web-based system where clients book their own slots, pay online at the correct rate, and get reminded automatically -- while she keeps a master schedule she can view, manipulate, and print (she likes paper and should get to keep it as a workflow, just not as the source of truth).

Two differentiators rule out off-the-shelf tools (Square Appointments, Acuity):

1. **Tiered client priority.** Legacy and preferred clients get first access to prime times, and Mia controls exactly when each tier's (or individual's) booking window opens for the season.
2. **Aggressive gap-fill.** With short teaching days, a single blank slot is a large fraction of her time at the pool wasted. When a cancellation opens a hole, the system fights to refill it (client blasts, waitlist alerts, compaction offers, or handing Mia a ranked call list), and non-emergency late cancellations always get charged.

## 2. Goals

- Clients self-serve: book, reschedule, and cancel their own lessons within rules Mia sets.
- Zero manual payment chasing: every booking is paid at the correct per-client rate before the lesson happens.
- Tiered access: Mia opens season booking per tier or per person, on her timeline, with prime-slot protection for top tiers.
- Mia has one master schedule: web dashboard + a print-friendly weekly view that replaces her paper sheet 1:1.
- No dead slots: every open slot inside a committed shift gets flagged and actively worked (auto-blast, waitlist, compaction offer, or a call list for Mia) until filled or passed.
- Late cancellations always cost the client something -- unless it's a genuine medical or family emergency.
- Automated reminders (email v1, SMS v2) reduce no-shows without Mia texting anyone.
- Near-zero cost to run, and cleanly dormant in the off-season (Sept--May).

## 3. Non-Goals (v1)

- **Multi-instructor UI.** Mia is solo today -- but she may become a swim-teaching manager later. Ship no staff features, but keep the schema instructor-aware (dormant `instructor_id` on availability/slots, single seeded row) so adding a second instructor later is a feature flag, not a migration.
- **Native mobile app.** Web-only, but fully responsive -- most clients will book from their phones.
- **Any multi-swimmer lessons.** Mia teaches solos only -- never two kids in the water at once, even siblings. Families with multiple kids book back-to-back solo slots instead -- see §5.6.
- **Marketing automation** (drip campaigns, CRM sequences). However, SEO and AI-search optimization of the public site IS in scope -- see §5.10.
- **In-person card reader in v1.** Planned for later (§7 P2): Stripe Tap to Pay / Terminal on Mia's phone, reconciling into the same Stripe account. Payments schema carries a `channel` field from day one so poolside payments slot in cleanly.

## 4. Users & Roles

| Role | Who | Can do |
|---|---|---|
| Admin | Mia | Full schedule CRUD, set shifts & break rules, set tiers/rates, open booking windows per tier or person, override any booking, mark no-shows, waive/charge late cancels, refund, print weekly view |
| Client | Parent/guardian (account holder) | Manage swimmer profiles (their kids), book/reschedule/cancel within policy, confirm Mia's near-term changes, pay, view history |
| Visitor | Prospective client | View portfolio site, request an account or join the waitlist; Mia approves -- keeps tier control and prevents strangers booking |

Notes: the **account holder is the parent**; swimmers are child records under the account. Billing, SMS, and login belong to the parent. The dormant `instructor` concept lives in the schema only -- no UI in v1.

## 5. Core Design Decisions

### 5.1 Priority tiers & season-open grants (the custom part)

Three tiers, admin-configurable -- **Tier A (legacy), Tier B (preferred), Tier C (standard)**. Two mechanisms:

1. **Booking-window distances.** Each tier can book up to N days out; N is set by Mia per tier (not hardcoded). Working defaults: A=21, B=14, C=7 -- **OPEN:** Mia confirms.
2. **Prime-slot gating.** Mia flags slots as *prime*; prime slots stay locked for lower tiers until a configurable cutoff (default T-72h), then open to everyone so they don't go unsold.

**Season-open grants (the onboarding flow).** Clients create accounts on the website ahead of the season (Mia announces the transition to the new system). When Mia decides to open booking, she issues a *grant* -- targeted at a whole tier **or** individual accounts -- and each grantee is notified (email v1, SMS v2) that their booking window is open. A grant has an expiry (default: 7 days -- **OPEN**) during which they select their appointment times for the summer. After grants expire, the normal rolling tier windows govern.

**Tier invisibility is a hard rule.** Clients never see a tier label, and no client-facing API response may include tier data -- clients only ever see which slots are bookable *for them* and when. Acceptance test: inspect every portal API payload for tier leakage.

### 5.2 Shift structure & break rules

Mia's day is not a naive :00/:30 grid -- the slot generator packs lessons around her real stamina rules:

- **Lesson unit:** 30 minutes, priced per 30 minutes.
- **Consecutive cap:** comfortable up to an hour straight; after **3 lessons in a row (90 min), auto-insert a 10-minute break**.
- **Lunch:** one 30-minute lunch break per shift, placed near the middle by default; Mia can drag it, and an organically unfilled slot can *become* the lunch (freeing a break elsewhere).
- **Shifts:** Mia defines shift templates (day + start/end, e.g., Mon 10:00--18:00); the generator lays down runs of ≤3 lessons separated by 10-min breaks plus the lunch. An 8-hour shift yields ~13 bookable lessons.
- **Off-grid times are fine.** Breaks shift start times off :00/:30 (e.g., 11:40, 13:40); the booking UI simply shows exact times. Alternative considered and rejected: forcing a clean grid by burning full 30-min break slots costs ~2 lessons/shift.
- **Days:** preferred Monday + Thursday; Tuesday/Wednesday added per demand. The dashboard's per-day demand view (waitlist size, fill %) should inform whether adding a day is worth it.

### 5.3 Gap-fill & utilization (the other custom part)

- **Gap detection.** Any open or newly cancelled slot inside a committed shift (especially one flanked by bookings) is flagged as a *gap* -- highlighted on the week view and in Mia's morning digest, with per-shift fill % shown.
- **Escalating fill tactics:**
  1. *Auto-blast* (email v1, SMS v2): tier-eligible, opted-in clients **and waitlisted families** get "A spot just opened Thu 4:30" with a claim link -- first to pay wins, resolved by the same double-booking constraint as normal booking. Waitlist includes new/prospective clients Mia didn't have room for; a gap is their way in.
  2. *Compaction offer:* clients booked adjacent that day are offered a shift ("come 30 min earlier?") to close the hole. (P0 surfaces the suggestion to Mia; P1 automates the outreach.)
  3. *Call list -- the "be nice about it" path:* if a gap is open at T-48h, Mia gets a text/email with a ranked shortlist (waitlisted first, then families who usually book that weekday/time) with phone numbers. The gap card in the dashboard shows the same suggestions on demand, because some gaps get filled by Mia personally charming the right parent -- the system does the targeting, she does the charm.
- Every gap and its resolution is logged (`gap_events`) so Mia learns which tactics actually fill slots.

### 5.4 Payment model

- **Rate: $45 per 30-minute solo session** (the only lesson type), may rise with demand. Rates live **per account** so grandfathering a legacy family is a one-field edit. **OPEN:** do demand-driven increases exempt Tier A?
- **Prepaid package (use-it-or-lose-it):** a **3-lesson pack at 5% off** (3 × $45 = $135 → **$128.25**), purchasable **only during the season-open window** Mia sets. Once the window closes, packages disappear and everything is à la carte at $45. Mechanics: purchase → account holds 3 lesson credits → booking a slot consumes a credit instead of Stripe Checkout → **credits expire at season end, no refund**. One credit = one 30-minute lesson (an hour booking consumes two). Package-paid late cancels: non-emergency <24h burns the credit (that *is* the charge); emergency restores it.
- **v1: Pay at booking** via Stripe Checkout. Booking isn't confirmed until payment succeeds.
- **Cancellation policy:**
  - Cancel ≥24h out → automatic refund (or account credit -- **OPEN**).
  - Cancel <24h → the client **must select a reason**. *Medical emergency* or *family emergency* → no charge (auto-refund), logged; **any other reason → charged full price** (payment kept). The dashboard shows emergency-waiver frequency per family so a pattern of "emergencies" is visible, and Mia can override any waiver either direction.
  - No-shows marked by Mia keep the payment.
  - Every cancellation immediately triggers gap-fill (§5.3) -- a late-cancelled slot that refills earns twice (**OPEN:** keep both, or partial credit back? Keeping both is the incentive-correct default).
- **Client-facing policy copy (draft -- Mia to finalize wording):**
  > **Cancellation policy.** Life happens -- here's how we handle it. Cancel **more than 24 hours** before your lesson and you'll get a full refund (or your package credit back). Cancel **within 24 hours** and the lesson is charged in full -- unless it's a medical or family emergency; just select the reason when you cancel and the fee is waived. Missed lessons without notice are charged in full. If Mia ever needs to move or cancel a lesson, you'll always be notified right away -- and never charged.
- **v2 (P1): Card on file** via Stripe SetupIntent for trusted tiers -- enables pay-after-lesson and automatic no-show/late-cancel charges on recurring bookings.
- **Later (P2): in-person payments** via Stripe Tap to Pay on Mia's phone, same Stripe account, `payments.channel = in_person`.

### 5.5 Schedule changes & confirmation windows

Everybody affected is notified of **every** schedule change, no exceptions. The difference is whether they must approve it:

- **Far out (beyond the confirmation window):** Mia's change auto-applies; client gets a notification with the new time. Done.
- **Near term (inside the window, default 48h -- OPEN):** Mia's change puts the booking into `pending_client_confirmation`; the client receives a confirm link and must accept the new time. If they decline or don't respond by a deadline, the booking reverts/cancels per Mia's choice, with a full refund (Mia moved it, not them).

### 5.6 Booking configurations (solo-only)

Every lesson is one swimmer, 30 minutes, $45. Multi-slot needs are handled as *linked solo bookings in one checkout*:

1. **Siblings:** each kid gets their own slot at $45 -- usually back-to-back. When a parent with multiple swimmers books a slot, the flow offers a one-tap "add the adjacent slot for {other kid}."
2. **Hour lessons (rare but real):** one swimmer books two consecutive slots -- 2 × $45 = $90, no discount. The UI offers "extend to an hour" when the next slot is open.

Both cases create multiple booking rows sharing one Stripe Checkout session (`checkout_group_id`), so paying once covers all slots and a payment failure releases every hold together. Note the interaction with §5.2: an hour lesson consumes two of the ≤3-lesson run before a break.

### 5.7 SMS

- Twilio, one local number. Confirmation on booking, reminders T-24h and T-2h, grant-opened notices, gap blasts, cancellation/refund notices. STOP/opt-out honored.
- ⚠️ **Gotcha:** US A2P 10DLC registration is mandatory, takes days, and throttles until approved. Start registration in Phase 1; SMS ships Phase 2. Email (Resend) covers every notification type from day one.

### 5.8 The paper bridge

A `/admin/print` route renders the week as a clean, ink-friendly schedule grid (client, swimmer(s), exact time, paid status, breaks/lunch shown). Mia prints it before her shift and keeps her paper habit -- the site is the source of truth, the paper is a snapshot.

### 5.9 Seasonal mode

A `season` config (start/end dates). Off-season: booking UI shows "Booking opens May 2027 -- join the notify list," crons no-op, nothing to tear down. Free tiers mean the off-season costs ~$0.

### 5.10 Frontend, SEO & AI-search standards

- **Built to Connor's standard:** clean modern design, tasteful animations (Framer Motion), fast, fully responsive. Public pages: portfolio/bio, photos, testimonials, pricing, booking entry.
- **Color direction (from Mia): blue for swimming, summery and fun.** Working palette: pool blues as the anchor (deep water blue for headers/CTAs, bright aqua for accents) with a warm summer accent (coral or sunshine yellow) and light, airy neutrals (sand/off-white) -- playful, not corporate. Built on CSS variables/Tailwind theme tokens; exact hex values are Mia's call and swap in without rework.
- **SEO:** SSR/SSG public pages, semantic HTML, per-page meta + OpenGraph, sitemap.xml + robots.txt, image alt text, Core Web Vitals green.
- **AI-search optimization:** schema.org structured data (`LocalBusiness`/`Service` with area served, price range, hours), a genuinely descriptive plain-language services page (AI answer engines quote clear prose), FAQ page with FAQ schema ("How much are private swim lessons in [city]?"), and an `llms.txt`. Target queries: "private swim lessons [city]", "swim instructor near [community]".

## 6. User Stories (priority order)

**Mia (admin)**
- As Mia, I want to define shift templates (day, hours) and have the system generate the lesson slots *with my break rules baked in* so my day is packed but humane.
- As Mia, I want to open season booking for a tier or a specific family, with a deadline, so my favorite clients pick first -- on my schedule.
- As Mia, I want a master week view with gaps, fill %, and paid status so I have one reference instead of paper reconstruction.
- As Mia, I want any cancellation to immediately kick off gap-fill (blast, waitlist, compaction, or my call list) so I never sit through an empty 30 minutes at the pool.
- As Mia, I want non-emergency late cancels charged automatically -- and genuine emergencies waived -- so the policy enforces itself without me being the bad guy.
- As Mia, I want near-term schedule changes to require client confirmation so nobody shows up at the old time.
- As Mia, I want demand signals (waitlist size, fill % by day) so I know when adding Tuesday or Wednesday is worth it.
- As Mia, I want a printable weekly sheet so I can keep paper poolside.

**Client (parent)**
- As a parent, I want an SMS/email the moment my booking window opens, and a simple flow to lock in my summer times before the window closes.
- As a parent, I want to see open slots I'm eligible for and book+pay in under a minute.
- As a parent with two kids, I want to book back-to-back slots for them in one checkout so drop-off is one trip and payment is one charge.
- As a parent, I want to extend a lesson to a full hour when the next slot is open, priced clearly at 2 × $45.
- As a returning family, I want to prepay the discounted 3-lesson pack during the season-open window and watch my remaining credits as I book.
- As a parent, I want to cancel or reschedule online, and if it's last-minute for a real emergency, not be charged.
- As a parent, I want to confirm or decline when Mia moves my lesson on short notice.
- As a new family that didn't get a spot, I want to join a waitlist and get pinged when an opening appears.
- As a parent, I want reminders before lessons and receipts after.

## 7. Requirements

### P0 -- Must have (Phase 1 can't ship without)
| # | Requirement | Acceptance criteria (abridged) |
|---|---|---|
| P0-1 | Auth: email magic-link; roles admin/client; new accounts require Mia's approval; visitors can join waitlist | Unapproved accounts can log in but not book; Mia notified of requests |
| P0-2 | Shift templates + slot generation with break rules (≤3 consecutive, 10-min breaks, 30-min lunch, off-grid times) | Regenerating a shift never deletes booked slots; an 8h template yields ~13 lessons with breaks placed per rules |
| P0-3 | Tier logic: configurable per-tier windows + prime gating + **season-open grants** targetable at tier or individual, with expiry, notified by email | Tier C sees a prime slot 5 days out as locked, bookable at T-72h; a granted client can book immediately regardless of rolling window until grant expires |
| P0-4 | Tier invisibility | No client-facing response (UI or API) contains tier data |
| P0-5 | Booking + Stripe Checkout: 10-min hold during checkout; confirmed on webhook; multi-slot checkout (sibling back-to-back, hour extension) as linked bookings under one session | Double-booking impossible under concurrency (DB constraint); failed payment releases *all* held slots in the group |
| P0-6 | Per-account rates ($45/30min default; grandfather-able); hour = 2 × rate | Checkout amount always equals rate × slot count for the account |
| P0-7 | Cancellation policy with reason capture: ≥24h refund; <24h reason required -- emergency (medical/family) auto-waived + logged, all else charged full | Waiver frequency visible per family; Mia can override either direction; every late cancel fires gap-fill |
| P0-8 | Admin dashboard: week view with gap highlights, per-shift fill %, breaks/lunch rendered; booking override; no-show marking; refunds | Cancelled mid-shift slot renders as flagged gap within seconds |
| P0-9 | Schedule-change confirmation: changes inside window (default 48h) require client confirm; outside → notify only | Unconfirmed near-term change never silently stands; decline path refunds |
| P0-10 | Gap-fill auto-blast (email): tier-eligible opted-in clients + waitlisted families get claim links; first paid wins | Claim link dies when slot books; blasts logged |
| P0-11 | Call-list fallback + gap suggestions: open gap at T-48h → Mia gets ranked shortlist with phones; same suggestions on the gap card on demand | Waitlisted rank first; digests logged; system contacts no one in this path -- Mia does |
| P0-12 | Email notifications (booking, grant-opened, reminder T-24h, change-confirm, cancellation, refund) via Resend | Reminder cron idempotent |
| P0-13 | Printable weekly schedule incl. breaks | One page per week, legible in B&W |
| P0-14 | Public site: portfolio, testimonials, pricing, booking entry -- Connor's design standard, theme-tokenized for Mia's palette; SEO + AI-search per §5.10 | Lighthouse SEO ≥ 95; valid LocalBusiness structured data; sitemap live |
| P0-15 | Prepaid 3-pack: purchasable only while the season-open package window is active (`app_config`); Checkout at 3 × rate × 0.95 → credits ledger; credit-paid bookings skip Checkout; season-end expiry cron; credits burn/restore per cancellation policy | Purchase attempt outside the window is impossible in UI and API; expiry disclosed at purchase; credit math survives cancel/restore round-trips |

### P1 -- Fast follow (Phase 2)
- Twilio SMS: reminders, grant-opened notices, gap blasts with claim links, change-confirm requests (blocked on A2P approval).
- Automated compaction offers (P0 detects and suggests; P1 messages adjacent clients).
- Recurring weekly bookings with per-occurrence payment or season prepay (**OPEN**).
- Card on file for Tier A: pay-after-lesson, automatic no-show/late-cancel charges.
- Waitlist self-serve polish (position hints, preferences by day/time).

### P2 -- Future (design for, don't build)
- **In-person payments:** Stripe Tap to Pay on Mia's phone, `channel=in_person`, unified reconciliation.
- **Second instructor:** activate the dormant `instructor_id` -- per-instructor shifts, client-instructor affinity. No v1 UI.
- Demand-based dynamic pricing suggestions; larger package sizes if 3-packs sell.
- Google Calendar one-way sync; multi-season "rebook last summer's slot" one-tap.

## 8. Architecture & Stack

```
Next.js 14+ (App Router, TypeScript)  -- one repo: public site + /book + /portal + /admin
├── Hosting: Vercel (hobby tier)      -- Connor already deploys here
├── DB + Auth: Supabase (Postgres, RLS, magic links)
├── Payments: Stripe Checkout + webhooks (v2: SetupIntents; later: Tap to Pay)
├── Email: Resend        SMS: Twilio (Phase 2)
├── UI: Tailwind (theme tokens) + Framer Motion
└── Cron: Vercel Cron → /api/cron/{reminders,gap-digest,hold-expiry,grant-expiry}
```

Why Postgres/Supabase over Firebase: the domain is relational (accounts → swimmers → bookings → payments; tier- and grant-gated slot queries; uniqueness constraints against double-booking; break-aware slot generation). Postgres constraints + RLS do the heavy lifting. Free tiers cover solo-tutor volume (~26--40 lessons/week at 2--3 shifts).

**OPEN:** what's her current site built on / who owns the domain?

## 9. Data Model (Postgres)

```
instructors    id, name, active            -- DORMANT: one seeded row for Mia; no v1 UI
accounts       id, email, name, phone, role(admin|client), tier(A|B|C),
               status(pending|approved|waitlist|archived),
               rate_cents (default 4500),
               sms_opt_in, opening_alerts_opt_in, stripe_customer_id
swimmers       id, account_id, name, birth_year, notes (level, goals)
packages       id, account_id, season_id, lessons_total(3), lessons_used,
               discount_pct(5), price_cents, stripe_checkout_id,
               purchased_at, expires_at(season end)   -- use-it-or-lose-it
seasons        id, label, start_date, end_date
shift_templates id, season_id, instructor_id, weekday, start_time, end_time,
               max_consecutive(3), micro_break_min(10), lunch_min(30)
slots          id, season_id, instructor_id, starts_at, ends_at, is_prime,
               kind(lesson|break|lunch), status(open|held|booked|blocked)
               UNIQUE(instructor_id, starts_at)   -- double-booking guard
booking_grants id, season_id, target(tier|account), tier?, account_id?,
               opens_at, expires_at, notified_at
bookings       id, slot_id UNIQUE, account_id, swimmer_id, checkout_group_id,
               paid_via(checkout|package_credit), package_id?,
               status(pending_payment|confirmed|pending_client_confirmation|
               cancelled|completed|no_show),
               price_cents, cancelled_at, cancel_reason(category+free_text),
               fee_waived(bool), waived_by
payments       id, checkout_group_id, stripe_checkout_id, stripe_payment_intent,
               amount_cents, channel(online|in_person),
               status(paid|refunded|partial_refund), refunded_at
waitlist       id, season_id, account_id, preferred_days[], created_at
               -- includes new families Mia had no room for; powers blasts + call lists
gap_events     id, slot_id, detected_at, cause(cancel|unsold),
               resolved_by(blast|compaction|call|became_lunch|expired), resolved_at
messages_log   id, account_id, channel(email|sms), template, sent_at, provider_id
app_config     key, value  -- tier window days, prime cutoff, confirm window,
                              grant default days, package window end, cancel cutoff,
                              season dates
```

RLS: clients read/write only their own rows; slot eligibility (tier windows, prime gating, grants) enforced server-side; **tier never serialized to client responses**.

## 10. Key Flows

**Season open:** Mia creates grants (tier or individuals, expiry) → grantees notified (email v1/SMS v2) "your booking window is open until {date}" → they book their summer times → grant-expiry cron closes lapsed grants → rolling tier windows take over.

**Booking:** client picks eligible slot → server validates (tier window ∪ active grant, prime gating, slot open) → flow offers "add adjacent slot for {sibling}" / "extend to an hour" → all chosen slots `held` 10 min under one `checkout_group_id` → if the account has package credits, booking consumes credits and confirms instantly; otherwise Stripe Checkout at rate × slot count → webhook confirms the whole group → confirmation sent.

**Package purchase:** only while the season-open package window is active → client buys the 3-pack via Checkout (rate × 3 × 0.95) → credits ledger opens → expiry = season end; expiry cron zeroes unused credits (use-it-or-lose-it, disclosed at purchase). Window closed → package UI gone, à la carte only.

**Cancellation (client):** ≥24h → refund (or credit restored, for package bookings), slot reopens. <24h → reason required; medical/family emergency → auto-waive + refund/credit-restore + log; anything else → payment or credit kept. Either way `gap_event` created and gap-fill fires.

**Gap-fill:** blast (email v1) to eligible + waitlisted with claim links → unclaimed: compaction suggestion surfaced (P1: automated outreach) → open at T-48h: ranked call list to Mia; gap card shows suggestions on demand → resolution recorded (including `became_lunch` when Mia converts the hole to her lunch).

**Admin reschedule:** Mia moves a booking → outside confirm window: auto-apply + notify → inside window: `pending_client_confirmation`, client confirms/declines by deadline; decline or timeout → revert or cancel with full refund, per Mia's choice.

**Reminders (cron):** daily 8 AM → T-24h reminders for tomorrow's confirmed bookings; hourly → T-2h (SMS, P1). All sends logged and idempotent.

## 11. Phased Delivery

| Phase | Scope | Definition of done |
|---|---|---|
| 1 -- MVP | P0-1 … P0-15; portfolio migrated with Mia's palette; real client list seeded with tiers/rates; Twilio A2P registration submitted | Mia opens the season via grants (3-pack purchasable during the window), runs one real week on the system, prints paper *from* it; a test late cancel charges correctly and either refills via blast or lands on her call list |
| 2 -- Automation | SMS everywhere (reminders, grants, blasts, confirms), automated compaction, recurring bookings, card-on-file auto-charges | A same-day cancellation triggers texts and refills itself; no-shows charge automatically |
| 3 -- Growth | Tap to Pay in-person payments, season packages, calendar sync, multi-season rebooking, gap analytics, (if ever) second-instructor activation | Poolside card payments reconcile in Stripe; returning families rebook in one tap |

Phase 1 build order: schema + RLS → auth/approval/waitlist → shift templates + break-aware slot generation → tier/grant-gated slot query → checkout + webhook (Stripe CLI) → 3-pack purchase + credits ledger → cancellation policy + reason/waiver flow → gap detection + blast + claim links → admin week view + gap cards → change-confirmation flow → call-list digest cron → client portal → emails → print view → public site + SEO → seed data.

## 12. Open Questions

**Blocking (answer before Phase 1):**
1. **Pricing, remaining:** any grandfathered legacy rates below $45? Do future demand-driven increases exempt Tier A? How long does the package window stay open after season-open grants go out? *(Resolved: $45/30min solo-only; siblings back-to-back at $45 each; hour = 2 × $45; 3-pack at 5% off, season-open window only, use-it-or-lose-it.)*
2. Current website platform + domain ownership? *(Resolved: color direction is blue + summery/fun -- final hex values whenever Mia picks them.)*
3. Tier assignments: which families are A/B/C; prime hours; per-tier window days.
4. Grant window default: 7 days right?
5. Confirmation window for near-term changes: 48h right? And on decline -- revert or cancel?
6. Cancellation refunds: card refund or account credit?
7. Emergency waiver: auto-waive on selection (current design) or hold for Mia's one-tap approval?
8. Business entity for Stripe + Twilio A2P: Mia's SSN/sole prop or an LLC? Affects onboarding and taxes.

**Non-blocking:**
9. Recurring bookings: per-occurrence charge or season prepay?
10. Hide prime slots from Tier C entirely, or show as locked?
11. Opening-alert blasts: opt-in at signup or default-on? Frequency cap per family?
12. Compaction: how often can one family be asked to shift before it's annoying?
13. Double-earn on refilled late-cancels: keep both (default) or partial credit back?
14. Cancellation policy copy: drafted in §5.4 -- Mia finalizes wording before launch. *(Resolved: no liability waiver needed -- the community pool doesn't require one.)*

## 13. Running Costs

| Item | Cost |
|---|---|
| Vercel hobby + Supabase free tier | $0 at this volume |
| Domain | ~$12/yr (may already own) |
| Stripe | 2.9% + $0.30 online; Tap to Pay in-person ~2.7% + $0.05 (P2) |
| Twilio | ~$1.15/mo number + ~$0.008/SMS + one-time A2P registration (~$20-ish); ≈ $5--8/mo in season |
| **Total** | **≈ $6--10/mo in season, ≈ $1/mo off-season** |

For contrast: Square Appointments free plan covers maybe 80% of this with zero build effort -- but no tier/grant system, no per-client rates at booking, no break-aware slot generation, no escalating gap-fill engine, no emergency-aware cancellation policy, and no ownership of the client data. Those are the reasons to build.
