# Aqua Athletic App — Build Specification

> **Audience:** This document is the complete, authoritative build spec for an AI coding agent (Claude Code). Build exactly what is described here. Where a detail is not specified, choose the simplest robust option consistent with the rest of this document and leave a clearly-marked `// TODO(spec):` note rather than inventing business rules.

---

## 1. What this app is

Aqua Athletic is a swimming academy with **7 branches**. Each branch maintains a **monthly Excel workbook** (a roster of athletes plus their billing info) that staff edit by hand. This app sits on top of those workbooks and provides:

- A **customer side** (parents/athletes) to see their athlete's info and pay their monthly fees.
- An **admin side** (admins + assistants) to provision customer accounts, view analytics, and manage payments/receipts.
- An **automatic professional receipt system** for every payment, printable and auto-sent via SMS / email / WhatsApp.

### Hard architectural rule (do not violate)
**Excel is READ-ONLY to this app.** The app never writes to the Excel files. All writable state (accounts, payments, receipts) lives in the app's own PostgreSQL database. Excel is one *input source*, not the database.

---

## 2. Tech stack (fixed)

| Layer | Technology |
|---|---|
| Mobile app | **Flutter** (iOS + Android, single codebase) |
| Backend | **Python + FastAPI** |
| Database | **PostgreSQL** |
| Excel source | **Google Drive** (7 workbooks live here; already connected) |
| Payments (online) | **Paymob** (Egypt) |
| Notifications | SMS + Email + WhatsApp (provider abstraction — see §12) |
| Auth | JWT access/refresh tokens; passwords hashed with **argon2** (or bcrypt) |
| Scale target | **~6,000 users**, 7 branches |

Backend is the only component that holds secrets (Paymob keys, DB creds, Google Drive creds, notification provider keys). **No secret ever ships inside the Flutter app.** The Flutter app talks only to the FastAPI backend.

---

## 3. The data model — three stores

Everything keys on the athlete identity spine: **`(branch, athlete_number)`**.

- `athlete_number` is the stable per-branch number (the number in an "M-code" like `M31` → `31`; ignore the `M`).
- Each branch has its **own** number space starting at 1, so `31` is a different athlete in each branch. **Identity is always the pair `(branch, athlete_number)`, never the number alone.**
- The number is stable over time for a given athlete (does not get renumbered month to month).

### Store 1 — Excel (READ-ONLY source, on Google Drive)
The roster + the bill. The app reads it; it is never the system of record for payments or accounts.

### Store 2 — PostgreSQL: Accounts (writable)
Login identities for customers, provisioned by admins.

### Store 3 — PostgreSQL: Payments + Receipts (writable)
The single true ledger of all payments and generated receipts, fed by **two** inputs:
1. Paymob webhooks (online payments), and
2. Excel-detected cash payments (staff mark paid in Excel).

All three join on `(branch, athlete_number)`.

---

## 4. The Excel files — structure & how to read them

There are **7 workbooks**, one per branch, all the same structure. **Match columns by header name, not by fixed position** — branches may drift slightly. If a workbook's shape doesn't match expectations, **skip it and log a structured error** (do not silently mis-read).

Each workbook has these sheets (names may have leading/trailing spaces — trim):

### Sheet ` June Reg.` (the master roster — the important one)
One row per athlete. Real data columns (read these by header):

| Header | Meaning | Notes for app |
|---|---|---|
| `f` | Source segment: `Gems Sch.` / `Outsider` / blank | affects pricing tier (GEMS cheaper) |
| `M Code` | derived `ID & Season` (helper) | **ignore** — it's a helper field |
| `ID` | e.g. `M31` | parse number out → `athlete_number` |
| `Name` | full name | display + receipts |
| `Age` | **computed decimal age — DO NOT TRUST** | missing-DOB rows show garbage `126.4`. **Compute age from `Date of Birth` instead.** |
| `Date of Birth` | **Excel serial number** (e.g. `44202.0`) | convert via epoch 1899-12-30. May be blank. |
| `gender` | `M` / `F` / blank | |
| `Step` | level: `St.1`..`St.9`, `P.p1/p2/p4`, `Pre Team`, `Junior Team`, `Adult Men/Women` | this is the customer-facing "level" |
| `Season` | month label (`May`/`June`) | mid-transition mismatches are normal |
| `Type` | `Class` / `Private.1` / `Semi-Private.2` / `Pre Team` / `Junior Teams` | product type |
| `Days ` | e.g. `Sun.Tues`, `Sat.Wed` | not normalized; literal label |
| `Times` | mostly blank in roster | real time comes from attendance sheets (see below) |
| `Sessions` | e.g. `8 Sessions` | input to price ladder |
| `pay ` | **the authoritative bill amount** for this athlete this month | clean number when filled; **may be blank** (esp. early in month) and **may deviate from the price ladder** (hand-set). **Read verbatim. NEVER recompute it.** |
| `Phone 1` | phone | **store/read as STRING** — values are dirty (scientific notation floats, stray backslashes, country codes, spaces). Normalize on read. |
| `Phone 2` | phone | same |
| `Receipt No.` | staff-entered receipt number for cash payments | **this is the cash-payment trigger** (see §8) |
| `visa` | (sparse) | |
| `Comment` | free text; often discounts (`50% D`, `20%Dec`) or Arabic notes (`ترحيل` = transferred/carried over) | surface to admin only; **do not parse for pricing** |

**Columns to ignore entirely:** the helper-column band to the right (roughly columns AK–BE) contains derived formulas including a broken `=#REF!` repeated thousands of times (~8,363 `#REF!` cells). **Read only the named real columns A–S + `Comment`. Never ingest the helper band.**

**Empty/whitespace handling:** many cells contain a single space `' '` rather than being truly empty. **Trim before testing for empty.** Expect `Step` empty on ~57% of rows, `Type` empty on ~16%, `gender` empty on ~20%. Empty is normal, not an error.

### Sheets `Sat.Wed`, `Sun.Tues`, `Mon.Thu` (attendance / scheduling)
**These are where `coach` and `time` come from** (the roster has no coach field). Layout is NOT a clean table — it has:
- a title row, a time-block header row (e.g. `4:15 to 5:10 pm`),
- athletes grouped under a **coach name** (coach appears in column 1 as a grouping label, repeated/blank down the group),
- blank spacer rows, and a `Total` column.

Parse by walking rows: track the **current time-block** (from block-header rows) and **current coach** (from the coach label), and attach `(coach, time_block, day_pair)` to each athlete row found (matched by `ID` / number).

- `Mon.Thu` and `Teams` are often **empty templates** — handle gracefully (no members).
- An athlete may appear in **more than one** block/coach → a customer's `coach`+`time` can be a **list**, not a single value.

### Sheet `Teams`
Same attendance layout, for team squads. Often an empty `May` template at month start.

### Sheet `Sk.` (reference data — "Prize List")
Two unrelated things in one sheet, parse separately:
1. **Price matrix** (rows ~2–10): membership type × session-count (`8x` … `1x`) → price. Tiers include `Class (Regular)`, `Class (GEMS)`, `Private 1:1`, `Semi Priv 1:2`, `Semi Priv 1:3`, `Junior Teams`, `Elite Team`. **This is reference/documentation only** — the app does NOT use it to compute bills (the bill is the `pay` cell). You MAY display it to admins as info.
2. **Coach name list** (down a right-hand column ~T): ~20 coach names. Useful as a per-branch coach lookup.

---

## 5. How the app reads Excel — caching & refresh

**Pattern: cached + refresh-on-change, per file.** Do NOT re-parse on every request (too slow at 6,000 users) and do NOT parse once and go stale.

For each of the 7 Google Drive files:
1. On startup, download + parse → build the joined in-memory model for that branch → cache it. Record the Drive file's `modifiedTime`.
2. On a schedule (e.g. every 60s) **and** on demand, check each file's Drive `modifiedTime`. If unchanged → keep cache. If changed → re-download, re-parse, replace that branch's cache, update stored `modifiedTime`. Only the changed branch re-parses.
3. **Robustness:** if a download/parse fails (file mid-save, locked, malformed), **keep serving the previous good cache** and retry next cycle. Never crash, never blank out good data. Log the failure with branch + reason.
4. **Mid-save safety:** download a copy and parse the copy, not a live handle.

The parsed cache holds **finished, joined objects** (not raw sheets): a list of `Athlete` objects per branch with `{branch, athlete_number, name, dob, age_computed, gender, step/level, type, days, sessions, pay, phone1, phone2, segment(f), comment, receipt_no, schedule:[{coach, time_block, day_pair}...]}`.

> This cache layer is the seam for the future migration off Excel: later, "parse the workbook" is replaced by "query a DB" and nothing downstream changes.

### Excel detection job (drives cash receipts — see §8)
Every refresh cycle, after re-parsing a changed branch, run a **reconciliation pass**: for each athlete, if Excel now shows a **paid state** (a `Receipt No.` present for the current period, and/or `pay` recorded as collected per the branch's convention) that does **not** yet have a corresponding payment row in Postgres for that `(branch, athlete_number, period)`, then **create the cash payment + generate & send its receipt** (§8). This pass must be **idempotent** — detecting the same Excel state twice must never create two payments/receipts (dedupe on `(branch, athlete_number, period, source=cash)`).

---

## 6. Roles, scope & accounts

### Viewer types
| Type | Scope | View |
|---|---|---|
| **Customer** | self only, within their branch | narrow: name, age, level, time, coach, bill/receipts |
| **Assistant** | ONE assigned branch | full admin view, that branch only |
| **Admin** | ALL 7 branches | full admin view, all branches |

- **Admin ⊇ Assistant** (admin can do everything an assistant can, plus cross-branch).
- Scope is a **read-time filter** over the same cached data — an assistant's session carries `branch = assigned`; they cannot address other branches. Admin has no branch filter.
- Admin/assistant branch assignment is **app config / DB**, never in Excel.
- Decide and implement an **admin cross-branch view** as: a branch **switcher** (pick a branch, view it like an assistant) **plus** an academy-wide **aggregate** dashboard for analytics (§11). Build both.

### Account provisioning (admin-driven; NO open self-registration)
This is the only way customer accounts are created. Open registration must NOT exist.

Flow:
1. Admin/assistant opens the **Athletes page** for a branch → sees the roster (from Excel cache).
2. Admin taps an athlete's name → backend creates an **Accounts** row for that `(branch, athlete_number)`:
   - generates a **login code** (unique handle) and a **temporary password**,
   - stores `password_hash` (argon2) — **never** plaintext, even the temp one,
   - sets `must_change_password = true` (temp pass is one-time; forced reset on first login),
   - snapshots `name_at_creation` and `dob_at_creation` (identity guard, see below),
   - records `created_by_admin`, `created_at`.
3. **Delivery — both channels available** (admin chooses per provisioning):
   - **In person:** show the code + temp password on the admin screen for the admin to hand over, AND/OR
   - **Auto-send** the code + temp password to the athlete's phone (`Phone 1`) via SMS/WhatsApp and/or email if available.
4. Customer logs in with code + temp pass → **forced to set a new password** → `must_change_password = false`. Admin never learns the customer's real password.

### Identity guard (safety — keep this even though departed accounts are left as-is)
Because numbers *could* theoretically be reused for a new athlete after one leaves, and departed accounts are NOT archived:
- On each login and on each cache refresh, compare the athlete currently at `(branch, athlete_number)` in Excel against the account's `name_at_creation` (and `dob_at_creation` if present).
- If they **clearly mismatch**, do **not** serve the new athlete's data to the old account — flag a `identity_mismatch` state and require admin re-verification. This is the only thing preventing "log in next month, see someone else's child." It costs little; keep it.
- An account whose athlete is simply **absent** from the current month's roster → show **"no active enrollment"** (not an error, not a bill).

---

## 7. Payments — Paymob (online channel)

### Rules
- The **amount is always supplied by the backend**, read from Excel `pay`. **Never** trust an amount sent by the client. The app *displays* the bill; the backend *authorizes* the charge.
- Backend holds the Paymob secret key and creates the payment intent. Flutter only opens Paymob checkout with a returned token.
- **The webhook is the source of truth**, not the app's success screen. The app callback can be faked/dropped.
- **Verify the Paymob HMAC signature** on every webhook before trusting it. Reject unsigned/invalid.
- On verified `paid` webhook: create a Payments row (`source=paymob`), generate the receipt (§8), auto-send it.

### Flow
1. App shows "You owe `pay` EGP for `<period>`" (from Excel cache via backend).
2. Customer taps Pay → backend creates Paymob intent for that exact amount → returns token.
3. App opens Paymob checkout (card + mobile wallet).
4. Paymob → webhook → backend verifies HMAC → records payment → generates + sends receipt.
5. App polls/refreshes payment status from backend (Postgres), shows "Paid ✓".

### Onboarding note (for the human, not code)
Paymob merchant account requires the academy to be a registered business (Commercial Register, Tax Card, owner ID, bank account); settlement is **EGP only**. Use Paymob **sandbox** for all development/testing. Real fee ≈ **2.75% + 3 EGP** per transaction (not relevant to code, but don't add app-side surcharges unless told).

### Store-acceptance framing (affects UI copy)
Lessons are an **in-person real-world service**, so Apple/Google IAP does **not** apply and external payment (Paymob) is allowed. To keep this classification clean: payment screens must clearly present the product as **in-person swimming lessons at a physical branch** (show branch, coach, class time). Do **not** use digital-subscription/"unlock" language.

---

## 8. Receipts (the headline feature)

Every payment — **both** channels — produces a professional, printable, auto-sent receipt. This replaces staff hand-writing receipts.

### Two payment channels feed the receipt system
| Channel | How payment is known | Receipt number owner |
|---|---|---|
| **Paymob (online)** | verified webhook | **App generates** the number, sequence prefix `P-` (e.g. `P-000123`) |
| **Cash / in-person** | **detected from Excel** (`Receipt No.` present for the period) during the reconciliation pass (§5) | **Staff's number from Excel**, stored as-is with prefix `C-` (e.g. `C-<excel number>`) |

Prefixes (`P-` / `C-`) guarantee the two numbering schemes **never collide**.

### Receipt generation rules
- Triggered **automatically** the moment a payment becomes known (Paymob webhook, or Excel cash detection). **Auto-send immediately** on generation (both channels).
- Generate a **PDF** receipt (printable, professional). Store the PDF (object storage or DB blob) linked to the Payments row. Also keep structured fields so it can be re-rendered.
- **Idempotent:** one payment = exactly one receipt. Re-detecting the same Excel state must not produce a second receipt.

### Receipt contents (pull from data already on hand)
- Academy name + branch + logo placeholder
- **Receipt number** (`P-`/`C-` prefixed)
- Date/time issued
- **Athlete name**, athlete number, level (`Step`), type
- **Parent/athlete phone** (normalized from `Phone 1`)
- **Period** (e.g. "June 2026")
- **Amount paid** (EGP), payment channel (Online / Cash)
- Paymob transaction id (online only)
- A clear "PAID" mark
- Footer: thank-you + contact line

### Sending
- **Auto-send on generation** via the customer's available channels: **SMS, Email, WhatsApp** (use whatever contact info exists; phone from `Phone 1`, email if captured on the account).
- Provide a **manual resend** action on the admin side and a **download/share** action on the customer side (in addition to auto-send).
- Sending must be **non-blocking and retried** — if a send fails, the receipt is still generated and recorded; queue the send and retry. A failed SMS must never lose the receipt.

---

## 9. Database schema (PostgreSQL)

> Use migrations (Alembic). All money in EGP, stored as integer **piastres** (or `NUMERIC(12,2)`) — pick one and be consistent; never float. All timestamps UTC.

### `branches`
- `id` (PK), `name`, `drive_file_id` (the Google Drive workbook), `display_name`

### `admin_users`
- `id` (PK), `email`/`username`, `password_hash`, `role` (`admin` | `assistant`), `assigned_branch_id` (nullable; required for assistant, null for admin), `is_active`, `created_at`, `last_login_at`

### `accounts` (customer logins)
- `id` (PK)
- `branch_id` (FK)
- `athlete_number` (int)  → **unique together: `(branch_id, athlete_number)`**
- `login_code` (unique)
- `password_hash`
- `must_change_password` (bool, default true)
- `name_at_creation`, `dob_at_creation` (identity guard)
- `email` (nullable, for receipts), `phone_at_creation` (nullable)
- `status` (`active` | `disabled` | `identity_mismatch`)
- `created_by_admin_id` (FK), `created_at`, `last_login_at`

### `payments`
- `id` (PK)
- `branch_id` (FK), `athlete_number` (int)
- `period` (e.g. `2026-06`)
- `source` (`paymob` | `cash`)
- `amount_owed_snapshot` (the Excel `pay` at time of payment — so later Excel edits don't corrupt history)
- `amount_paid`
- `currency` (`EGP`)
- `paymob_transaction_id` (nullable)
- `excel_receipt_no` (nullable; the staff number for cash)
- `status` (`pending` | `paid` | `failed` | `refunded`)
- `paid_at`, `created_at`
- **Idempotency:** unique constraint on `(branch_id, athlete_number, period, source)` to prevent double-recording.

### `receipts`
- `id` (PK)
- `payment_id` (FK, unique — one receipt per payment)
- `receipt_number` (unique; `P-` or `C-` prefixed)
- `pdf_url` / `pdf_blob`
- `issued_at`
- snapshot of all printed fields (athlete name, level, phone, period, amount, channel)
- `send_status` JSON: per-channel `{sms, email, whatsapp}` → `pending|sent|failed`, with retry counts

### `notification_log`
- `id`, `receipt_id` (nullable), `account_id` (nullable), `channel`, `to`, `status`, `error`, `attempts`, `created_at`

---

## 10. Backend API (FastAPI) — endpoints

> All endpoints JSON. Auth via JWT. Enforce **scope** on every endpoint (assistant → own branch only; customer → self only). Rate-limit auth endpoints.

### Auth
- `POST /auth/customer/login` — `{login_code, password}` → tokens; flags `must_change_password`
- `POST /auth/customer/change-password`
- `POST /auth/admin/login`
- `POST /auth/refresh`

### Customer
- `GET /me` — athlete profile: name, computed age, level, list of `{coach, time, day_pair}`, branch. (No billing internals beyond their own.)
- `GET /me/bill` — current period: amount owed (Excel `pay`), paid status, receipt(s).
- `POST /me/pay/paymob/intent` — backend creates Paymob intent for the owed amount → returns checkout token. (Amount is server-side, never from client.)
- `GET /me/receipts` — list + download links.
- `POST /me/receipts/{id}/resend` — resend to self.

### Admin / assistant
- `GET /branches` (admin: all; assistant: own)
- `GET /branches/{id}/athletes` — roster from Excel cache (the provisioning + management list)
- `POST /branches/{id}/athletes/{athlete_number}/provision` — create account, return code + temp pass, trigger delivery (in-person display and/or auto-send)
- `GET /branches/{id}/athletes/{athlete_number}` — full athlete detail (all Excel fields incl. comment, phones, segment, schedule)
- `GET /branches/{id}/payments?period=&status=` — owed-vs-paid list (the dashboard data)
- `POST /admin/receipts/{id}/resend`
- `GET /admin/analytics?scope=branch|academy&...` (§11)
- `GET /admin/health/excel` — per-branch parse status (last refresh, last error, file modifiedTime) so staff can see if a file failed to load

### Webhooks
- `POST /webhooks/paymob` — **verify HMAC**, then record payment + generate/send receipt. Idempotent.

### Background jobs
- Excel refresh + reconciliation pass (§5) on a scheduler.
- Notification send/retry queue.

---

## 11. Admin analytics (build on data honesty tiers)

Present analytics in **3 tiers**, labeled by reliability. Do not show confident numbers off sparse data.

**Tier 1 — Roster analytics (solid; build fully):**
- Enrollment by **level** (`Step`) — per branch + academy-wide. Show as a funnel (P.p1 → St.1 → St.2 …) to expose retention cliffs.
- Enrollment by **type** (`Class`/`Private`/`Semi`/`Team`).
- **Segment mix** (`f`: GEMS vs Outsider vs blank).
- **Age** distribution (computed from DOB; exclude the `126.4` garbage / ages > 100).
- **Gender** split.
- **Branch comparison** dashboard (all of the above side by side, 7 branches).
- **Owed vs collected** (from Postgres payments vs Excel `pay`): collection rate, outstanding list, totals per branch + academy.

**Tier 2 — Operational (coverage-dependent; show with an honesty label):**
- **Coach load** (members per coach, from attendance sheets) — label "based on X% of slots filled".
- **Time-block / slot utilization** (which class times are full/empty) — same caveat.

**Tier 3 — Trends (future; design for it now):**
- Stamp every parse with its **period/month**. When multiple months of files accumulate, enable **month-over-month** growth, retention by level, and churn. Build the data plumbing (period-stamped snapshots) now even though charts come later.

Discounts in `Comment` are free text → surface as a **flagged-for-review list**, never as a precise figure.

---

## 12. Notifications (provider abstraction)

- Define a `NotificationProvider` interface with `send_sms`, `send_email`, `send_whatsapp`.
- Implement concrete providers behind it (pick widely-available ones; **leave provider keys as config/env**, do not hardcode). WhatsApp via a Business API provider; SMS via an Egypt-capable SMS gateway; email via SMTP/transactional provider.
- All sends go through a **queue with retries** and are logged in `notification_log`. A send failure never blocks payment/receipt creation.
- Phone numbers come from Excel (`Phone 1`) and are **dirty** — normalize to E.164 (Egypt `+20`) before sending; if un-normalizable, mark that channel `failed` and continue with other channels.

---

## 13. Flutter app — screens

### Customer
1. **Login** (code + password) → forced **change-password** screen if `must_change_password`.
2. **Home / Profile:** athlete name, age, level, and their class **time(s) + coach(es)** (list if multiple), branch.
3. **Bill:** current period amount owed; **Pay** button (Paymob) when unpaid; "Paid ✓" + receipt when paid; "no active enrollment" if athlete absent from current roster.
4. **Receipts:** list, view/download PDF, share, resend to self.

### Admin / Assistant
1. **Login.**
2. **Branch selector** (admin only; assistant locked to their branch).
3. **Athletes list** (roster from Excel) → tap to **provision account** (shows generated code + temp pass; choose in-person / auto-send) and to view **athlete detail**.
4. **Payments dashboard:** owed vs paid for the period, filter by status, outstanding list, **resend receipt** action.
5. **Analytics** (§11) with the 3 tiers + branch/academy toggle.
6. **Excel health** panel: per-branch last refresh time + any parse errors.

UI must be clean and professional. Receipt PDF must look polished (this is a selling point).

---

## 14. Non-functional requirements

- **Scale:** ~6,000 customer accounts + staff. Reads served from cache; DB handles accounts/payments. This load is light for Postgres — but **index** `(branch_id, athlete_number)`, `period`, `status`, `login_code`.
- **Security:**
  - argon2/bcrypt password hashing; never store plaintext (incl. temp passwords).
  - JWT with refresh; enforce scope on every endpoint.
  - Paymob secret + all provider keys server-side only; HMAC-verify Paymob webhooks.
  - No secrets in the Flutter app.
  - Customer can only ever access their own athlete; assistant only their branch.
- **Reliability:**
  - Excel parse failures degrade gracefully (serve last good cache; surface in Excel-health panel).
  - Receipt generation and notification sending are idempotent and retried; never double-charge, never double-receipt (unique constraints in §9).
  - Payment truth = Postgres, fed by Paymob webhooks + Excel reconciliation. The app answers "paid?"/"receipt?" only from Postgres.
- **Money:** integer minor units or `NUMERIC`; never float. Snapshot owed amount at payment time.
- **Migration seam:** keep the Excel-read behind a single `RosterSource` interface so it can later be swapped for a DB-backed source without touching the rest of the app.
- **Config:** all environment-specific values (Drive file IDs, Paymob keys, provider keys, DB URL) via env/secret manager. Provide `.env.example`.
- **Testing:** Paymob sandbox; a small hand-made sample workbook with ~15–20 fully-populated athletes (every field filled, a couple of discounts, a multi-slot athlete, a missing-DOB row, a dirty phone) to exercise every UI state, since real files are nearly empty until the month starts.

---

## 15. Build order (suggested)

1. **Backend skeleton** + Postgres + migrations + `RosterSource` interface.
2. **Excel ingestion**: Google Drive read, parser (roster + attendance join + Sk.), cache + refresh-on-change, Excel-health endpoint. Use the sample workbook.
3. **Admin auth + roles/scope.**
4. **Account provisioning** (generate code/temp pass, identity snapshot, both delivery channels).
5. **Customer auth** + profile + bill (read-only owed amount).
6. **Payments**: Paymob intent + webhook (HMAC) + Postgres ledger.
7. **Excel cash reconciliation pass** (idempotent cash-payment detection).
8. **Receipts**: PDF generation + numbering (`P-`/`C-`) + auto-send + resend + retry queue.
9. **Notifications** provider abstraction (SMS/email/WhatsApp).
10. **Analytics** (Tier 1 → 2 → 3 plumbing).
11. **Flutter app** screens consuming the API.
12. Harden: indexes, rate limits, idempotency tests, store-acceptance UI copy.

---

## 16. Critical "don't get this wrong" list

- **Never write to Excel.** It is read-only.
- **Never recompute the bill.** Read `pay` verbatim; it can deviate from the price matrix.
- **Never trust a client-supplied payment amount.** Backend supplies it from Excel.
- **Never trust the Paymob app callback;** trust the **HMAC-verified webhook**.
- **Identity is `(branch, athlete_number)`** — number alone is not unique across branches.
- **Keep the identity guard** (name snapshot) so a reused number can't expose the wrong child.
- **Idempotency everywhere** payments/receipts are created (unique constraints) — no double payments, no double receipts.
- **Phones and many fields are dirty** — read as strings, trim, normalize.
- **Empty fields are normal**, especially early in the month — design "pending"/"no enrollment" states as first-class.
- **Receipt numbers:** Paymob → app-generated `P-`; cash → staff's Excel number as `C-`. Prefixes prevent collision.
