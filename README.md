# RateX — SAR ⇄ BDT Trading Ledger

A mobile-first, installable web app (PWA) for tracking a personal remittance-trading business:

- **Buy stock:** send SAR from Saudi Arabia → receive BDT in Bangladesh (exchange rate + 2.5% government incentive = your true *effective cost rate*).
- **Sell:** deliver that BDT to customers' bKash/bank accounts in Bangladesh at **your own sell rate** → they pay you SAR (in full, partially, or on credit).
- **Settle:** record every instalment until each trade is settled.
- **Profit:** calculated per trade; *Actual Profit* grows as payments arrive, the rest stays *Pending Profit*.

**Live:** https://ifathosen.github.io/RateX/ · **Repo:** `ifathosen/RateX` · **Backend:** Supabase (Auth + Postgres with Row-Level Security)

---

## 1. One-time setup

### Step A — Create the database tables (2 minutes)
1. Open your [Supabase project](https://supabase.com/dashboard) → **SQL Editor** → **New query**
2. Paste the entire content of [`supabase-setup.sql`](./supabase-setup.sql)
3. Click **Run**. You should see *Success. No rows returned.*

This creates 7 tables (customers, stock lots, trades, trade-lots, settlements, **accounts** and **transfers**) with Row-Level Security, so every signed-in user can only ever see **their own** data. Existing tables in the project are untouched.

> **Already running v1/v2?** Don't re-run the full setup — run only [`supabase-v3-migration.sql`](./supabase-v3-migration.sql) once. It adds the accounts/transfers tables, the new columns (Remit No., account links) and rebuilds every RLS policy (this also fixes "new row violates row-level security policy"). Your existing data — including entries saved offline on your phone — is kept and will back up afterwards.

### Step B — Email auth settings (optional but recommended)
Supabase → **Authentication**:
- **Providers → Email:** enabled by default. Keep *Confirm email* **ON** (users verify their email before logging in), or turn it OFF for instant signup.
- **URL Configuration → Site URL:** set to `https://ifathosen.github.io/RateX/` and add the same URL under **Redirect URLs** (needed for email confirmation & password-reset links).
- **Private use:** after creating your own account, go to **Authentication → Settings** and turn OFF *Allow new users to sign up* so nobody else can register.

### Step C — Push to GitHub
Replace the repo contents with the files in this folder and push (GitHub Pages serves from the repo):

```
index.html            ← the whole app (Supabase URL + anon key already inside)
supabase.js           ← Supabase client library, self-hosted so the app opens offline
manifest.json         ← PWA manifest (app name: RateX)
sw.js                 ← service worker (offline app shell, cache v2)
icon-192.png          ← app icons — ALL files sit flat in the repo root (no subfolders!)
icon-512.png
maskable-512.png
supabase-setup.sql    ← full database setup for a fresh project (includes v3)
supabase-v3-migration.sql ← run ONCE when upgrading an existing v1/v2 database
.nojekyll
README.md
```

```bash
git add .
git commit -m "RateX"
git push
```

Then open the live URL, **Sign Up**, and add your first *Stock In*.

> The anon key in `index.html` is safe to publish — Row-Level Security protects the data. Never publish the `service_role` key.

### Step D — Install on your phone
Open the live site in Chrome (Android) → menu **⋮ → Install app** (or use the **⬇ Install** button in the app header). It installs as **RateX**. On iPhone: Safari → Share → **Add to Home Screen**.

---

## 2. How the accounting works

### Accounts first (opening balances)
Create your real accounts — e.g. **Saudi Bank (SAR)**, **Cash in Hand (SAR)**, **BD Bank (BDT)** — each with the balance it had on its **opening date** (before the transactions you record). Account balances are then derived:

- **SAR account:** opening − remittances (amount + fee) + settlements posted to it ± transfers
- **BD account:** opening + remittance credits − sell deliveries (incl. delivery charge) ± transfers

**No transaction can exceed the source account's balance.** All charges (remittance fee, delivery charge, transfer fee) are extra debits from the source account — they never reduce the amount the receiver gets.

Old stock bought before you started: add it as **Historical Lots** (Entry Type on the Stock In form) — each old remittance as its own lot with its own rate. Historical lots give you saleable stock and a cost rate, but do **not** post to accounts again (that money is already inside your opening balances). Every lot gets an auto-generated **Remit No.** (e.g. `REM-20261029-001`), shown on sell trades and searchable.

### Stock In (remittance you send)
| You enter | RateX computes |
|---|---|
| SAR sent, Sending fee (SAR), Exchange rate (BDT/SAR), Incentive % (default 2.5) | **Total BDT deposited** = SAR × Rate × (1 + Incentive %) *(editable if the bank deposited a slightly different amount)* |
| | **Effective cost rate** = Total BDT ÷ (SAR sent + Fee) |

*Example: 3,000 SAR @ 32.97878 + 2.5% → 101,409.75 BDT, effective rate **33.80325**.*

### Sell Trade (BDT delivered to a customer)
- Two input modes: **Customer needs BDT** (SAR = BDT ÷ your sell rate) or **Customer pays SAR** (BDT = SAR × your sell rate).
- You pick the **BD account the money is delivered from** (its balance is debited and can never go negative), the delivery method is free text (bKash, any bank name, ...), customer **name is mandatory**, phone and receiver account are optional.
- You **manually choose the stock lot(s)** the BDT comes from; a trade can be split across several lots. Allocated BDT = delivered BDT + optional delivery charge you bear.
- **Cost (SAR)** = allocated BDT ÷ lot effective rate (snapshotted at sale time).
- **Trade Profit (SAR)** = SAR receivable − Cost. A *lower* sell rate than your effective cost rate ⇒ profit.
  All trading fees are inside this number: the remittance fee is part of the lot's effective rate, and the delivery charge is part of the allocated BDT.
- **Net Profit (SAR)** = Trade Profit − standalone transfer fees (e.g. Cash → Bank charge). Those fees are debited from the source account *and* deducted from Actual/Net profit in Dashboard & Analytics. Remittance fees are never double-counted.

*Example: deliver 20,000 BDT @ 32.50 → customer pays 615.38 SAR; cost @ 33.80325 = 591.72 SAR → **profit 23.66 SAR**.*

### Settlements & profit recognition
- Each SAR payment from the customer is a settlement (partial payments fully supported). Every payment is **posted to the SAR account you choose** (Cash in Hand or Saudi Bank), and cash can later be moved with **Transfer → Cash to Saudi Bank** when you deposit it for the next remittance.
- **Actual Profit** = trade profit × (SAR collected ÷ SAR due). The unpaid share stays **Pending Profit**.
- A trade is **Pending → Partial → Settled** automatically.

### Dashboard definitions
| Card | Meaning |
|---|---|
| BDT Balance | Unsold BDT stock across all lots |
| SAR Balance | Total of your SAR accounts (Saudi Bank + Cash); falls back to collected − invested before accounts are set up |
| Pending Settlement | Total SAR still due from all open trades |
| Actual / Pending Profit | Realised vs. locked-in-unpaid profit (SAR) |

### Editing & deleting
- Any account, lot, trade, payment or transfer can be edited; everything (balances, stock, dues, profit) recalculates automatically.
- **Deleting anything opens an advanced warning popup** showing the exact balance/stock/profit impact, and you must tick "I understand…" before the delete button activates.
- Deleting a **trade** also deletes its payments and returns its BDT to stock and to the BD account.
- A **lot** that already supplied BDT to trades cannot be deleted (edit those trades first), and its total cannot be reduced below the amount already sold. Accounts used by history cannot be deleted — archive them instead.

---

## 3. Notes

- **Currencies:** SAR and BDT only; every rate is entered by you — RateX never fetches market rates.
- **Overpayment** on a single trade is blocked; record advances on the future trade they belong to.
- **Social buttons (G / f / in)** on the login card are part of the embossed design; email & password is the working login. To enable Google/Facebook/LinkedIn: Supabase → Authentication → Providers.
- **Offline-first:** once you have logged in (first login needs internet), RateX works completely offline. Every entry is saved instantly on the phone and queued; the header chip shows `☁ Synced`, `⏳ N to sync` or `📴 Offline · N saved`. When internet returns, changes are backed up to Supabase automatically (you can also tap the chip to sync/pull now). Don't clear the browser/site data while the chip shows unsynced changes, and if you edit the same record on two devices while both are offline, the later backup wins.
- **Tech:** single-file HTML/CSS/JS app with a **self-hosted** Supabase client (`supabase.js`) and a service-worker app shell — even the library loads offline. Custom CSS-bar/conic charts, no chart library. All files live flat in the repo root; manifest and service worker reference `icon-192.png` etc. at root, which is what makes Chrome offer **Install app**.
