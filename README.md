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

This creates 5 tables (`ratex_customers`, `ratex_stock_lots`, `ratex_trades`, `ratex_trade_lots`, `ratex_settlements`) with Row-Level Security, so every signed-in user can only ever see **their own** data. Existing tables in the project are untouched.

### Step B — Email auth settings (optional but recommended)
Supabase → **Authentication**:
- **Providers → Email:** enabled by default. Keep *Confirm email* **ON** (users verify their email before logging in), or turn it OFF for instant signup.
- **URL Configuration → Site URL:** set to `https://ifathosen.github.io/RateX/` and add the same URL under **Redirect URLs** (needed for email confirmation & password-reset links).
- **Private use:** after creating your own account, go to **Authentication → Settings** and turn OFF *Allow new users to sign up* so nobody else can register.

### Step C — Push to GitHub
Replace the repo contents with the files in this folder and push (GitHub Pages serves from the repo):

```
index.html            ← the whole app (Supabase URL + anon key already inside)
manifest.json         ← PWA manifest (app name: RateX)
sw.js                 ← service worker (offline app shell)
icons/                ← app icons (192 / 512 / maskable)
supabase-setup.sql    ← database setup (run once in Supabase, see Step A)
.nojekyll
README.md
```

```bash
git add .
git commit -m "RateX v1"
git push
```

Then open the live URL, **Sign Up**, and add your first *Stock In*.

> The anon key in `index.html` is safe to publish — Row-Level Security protects the data. Never publish the `service_role` key.

### Step D — Install on your phone
Open the live site in Chrome (Android) → menu **⋮ → Install app** (or use the **⬇ Install** button in the app header). It installs as **RateX**. On iPhone: Safari → Share → **Add to Home Screen**.

---

## 2. How the accounting works

### Stock In (remittance you send)
| You enter | RateX computes |
|---|---|
| SAR sent, Sending fee (SAR), Exchange rate (BDT/SAR), Incentive % (default 2.5) | **Total BDT deposited** = SAR × Rate × (1 + Incentive %) *(editable if the bank deposited a slightly different amount)* |
| | **Effective cost rate** = Total BDT ÷ (SAR sent + Fee) |

*Example: 3,000 SAR @ 32.97878 + 2.5% → 101,409.75 BDT, effective rate **33.80325**.*

### Sell Trade (BDT delivered to a customer)
- Two input modes: **Customer needs BDT** (SAR = BDT ÷ your sell rate) or **Customer pays SAR** (BDT = SAR × your sell rate).
- You **manually choose the stock lot(s)** the BDT comes from; a trade can be split across several lots. Allocated BDT = delivered BDT + optional delivery charge you bear.
- **Cost (SAR)** = allocated BDT ÷ lot effective rate (snapshotted at sale time).
- **Profit (SAR)** = SAR receivable − Cost. A *lower* sell rate than your effective cost rate ⇒ profit.

*Example: deliver 20,000 BDT @ 32.50 → customer pays 615.38 SAR; cost @ 33.80325 = 591.72 SAR → **profit 23.66 SAR**.*

### Settlements & profit recognition
- Each SAR payment from the customer is a settlement (partial payments fully supported).
- **Actual Profit** = trade profit × (SAR collected ÷ SAR due). The unpaid share stays **Pending Profit**.
- A trade is **Pending → Partial → Settled** automatically.

### Dashboard definitions
| Card | Meaning |
|---|---|
| BDT Balance | Unsold BDT stock across all lots |
| SAR Balance | SAR collected from customers − SAR invested in remittances |
| Pending Settlement | Total SAR still due from all open trades |
| Actual / Pending Profit | Realised vs. locked-in-unpaid profit (SAR) |

### Editing & deleting
- Any lot, trade or payment can be edited; everything (balances, stock, dues, profit) recalculates automatically.
- Deleting a **trade** also deletes its payments and returns its BDT to stock.
- A **lot** that already supplied BDT to trades cannot be deleted (edit those trades first), and its total cannot be reduced below the amount already sold.

---

## 3. Notes

- **Currencies:** SAR and BDT only; every rate is entered by you — RateX never fetches market rates.
- **Overpayment** on a single trade is blocked; record advances on the future trade they belong to.
- **Social buttons (G / f / in)** on the login card are part of the embossed design; email & password is the working login. To enable Google/Facebook/LinkedIn: Supabase → Authentication → Providers.
- **Tech:** single-file HTML/CSS/JS + Supabase JS CDN, custom SVG/CSS charts (no chart library). Charts, icons and styles are all self-contained; only the Supabase client loads from CDN.
