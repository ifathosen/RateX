-- ============================================================
--  RateX — Supabase Setup
--  Run this ONCE: Supabase Dashboard → SQL Editor → New query
--  → paste everything → Run.
--  Safe to re-run (uses IF NOT EXISTS / DROP POLICY IF EXISTS).
--  Tables are prefixed "ratex_" so nothing existing is touched.
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- updated_at helper ----------
create or replace function public.ratex_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ============================================================
-- 1) CUSTOMERS  (for customer-wise due ledger)
-- ============================================================
create table if not exists public.ratex_customers (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name        text not null,
  phone       text not null default '',
  note        text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists ratex_customers_unique
  on public.ratex_customers (user_id, lower(name), phone);
create index if not exists ratex_customers_user_idx
  on public.ratex_customers (user_id);

drop trigger if exists ratex_customers_upd on public.ratex_customers;
create trigger ratex_customers_upd before update on public.ratex_customers
  for each row execute function public.ratex_set_updated_at();

-- ============================================================
-- 2) STOCK LOTS  (each remittance you SEND = one lot = BDT stock in)
--    total_bdt      = sar_amount * base_rate * (1 + incentive_pct/100)
--    effective_rate = total_bdt / (sar_amount + fee_sar)   ← your true cost rate
-- ============================================================
create table if not exists public.ratex_stock_lots (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  txn_date        date not null default current_date,
  sar_amount      numeric(14,2) not null check (sar_amount > 0),
  fee_sar         numeric(14,2) not null default 0 check (fee_sar >= 0),
  base_rate       numeric(14,6) not null check (base_rate > 0),      -- BDT per 1 SAR (before incentive)
  incentive_pct   numeric(8,4)  not null default 2.5 check (incentive_pct >= 0),
  total_bdt       numeric(16,2) not null check (total_bdt > 0),      -- BDT actually deposited (with incentive)
  effective_rate  numeric(14,6) not null check (effective_rate > 0), -- BDT per 1 SAR incl. incentive & fee
  source          text not null default '',                            -- e.g. ENJAZ / SNB / UrPay / Bank name
  note            text not null default '',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists ratex_lots_user_date_idx
  on public.ratex_stock_lots (user_id, txn_date desc);

drop trigger if exists ratex_lots_upd on public.ratex_stock_lots;
create trigger ratex_lots_upd before update on public.ratex_stock_lots
  for each row execute function public.ratex_set_updated_at();

-- ============================================================
-- 3) SELL TRADES  (BDT delivered to a customer in BD, SAR payable by him)
--    sar_due = bdt_amount / sell_rate
-- ============================================================
create table if not exists public.ratex_trades (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id           uuid references public.ratex_customers(id) on delete set null,
  txn_date              date not null default current_date,
  delivery_method       text not null default 'bKash'
                          check (delivery_method in ('bKash','Nagad','Bank','Cash','Other')),
  receiver_info         text not null default '',   -- receiver number / account in BD
  bdt_amount            numeric(16,2) not null check (bdt_amount > 0),   -- BDT delivered to receiver
  delivery_charge_bdt   numeric(16,2) not null default 0 check (delivery_charge_bdt >= 0), -- optional, paid by you from stock
  sell_rate             numeric(14,6) not null check (sell_rate > 0),    -- BDT per 1 SAR you charged customer
  sar_due               numeric(14,2) not null check (sar_due > 0),      -- total SAR customer must pay you
  note                  text not null default '',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index if not exists ratex_trades_user_date_idx
  on public.ratex_trades (user_id, txn_date desc);
create index if not exists ratex_trades_customer_idx
  on public.ratex_trades (customer_id);

drop trigger if exists ratex_trades_upd on public.ratex_trades;
create trigger ratex_trades_upd before update on public.ratex_trades
  for each row execute function public.ratex_set_updated_at();

-- ============================================================
-- 4) TRADE → LOT ALLOCATIONS  (MANUAL lot selection; a trade can
--    be split across multiple lots. cost is snapshotted.)
--    Sum of bdt_allocated for a trade = bdt_amount + delivery_charge_bdt
-- ============================================================
create table if not exists public.ratex_trade_lots (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  trade_id          uuid not null references public.ratex_trades(id) on delete cascade,
  lot_id            uuid not null references public.ratex_stock_lots(id) on delete restrict,
  bdt_allocated     numeric(16,2) not null check (bdt_allocated > 0),
  cost_rate         numeric(14,6) not null check (cost_rate > 0),  -- lot effective rate at sale time
  cost_sar          numeric(14,4) not null check (cost_sar >= 0),  -- bdt_allocated / cost_rate
  created_at        timestamptz not null default now()
);
create index if not exists ratex_tl_trade_idx on public.ratex_trade_lots (trade_id);
create index if not exists ratex_tl_lot_idx   on public.ratex_trade_lots (lot_id);
create index if not exists ratex_tl_user_idx  on public.ratex_trade_lots (user_id);

-- ============================================================
-- 5) SETTLEMENTS  (each SAR payment received from customer;
--    a trade can have many → partial / instalment payments)
-- ============================================================
create table if not exists public.ratex_settlements (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  trade_id    uuid not null references public.ratex_trades(id) on delete cascade,
  txn_date    date not null default current_date,
  sar_amount  numeric(14,2) not null check (sar_amount > 0),
  method      text not null default 'Cash'
                check (method in ('Cash','Bank Transfer','STC Pay','UrPay','Other')),
  note        text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists ratex_stl_trade_idx on public.ratex_settlements (trade_id);
create index if not exists ratex_stl_user_date_idx
  on public.ratex_settlements (user_id, txn_date desc);

drop trigger if exists ratex_stl_upd on public.ratex_settlements;
create trigger ratex_stl_upd before update on public.ratex_settlements
  for each row execute function public.ratex_set_updated_at();

-- ============================================================
-- 6) ROW LEVEL SECURITY — every user sees ONLY his own data
-- ============================================================
alter table public.ratex_customers    enable row level security;
alter table public.ratex_stock_lots   enable row level security;
alter table public.ratex_trades       enable row level security;
alter table public.ratex_trade_lots   enable row level security;
alter table public.ratex_settlements  enable row level security;

do $$
declare t text;
begin
  foreach t in array array[
    'ratex_customers','ratex_stock_lots','ratex_trades',
    'ratex_trade_lots','ratex_settlements'
  ] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);

    execute format('create policy %I on public.%I for select using (auth.uid() = user_id)',  t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (auth.uid() = user_id)', t || '_insert', t);
    execute format('create policy %I on public.%I for update using (auth.uid() = user_id) with check (auth.uid() = user_id)', t || '_update', t);
    execute format('create policy %I on public.%I for delete using (auth.uid() = user_id)', t || '_delete', t);
  end loop;
end $$;

-- ============================================================
-- Done ✅  Now open the RateX site, Sign Up, and start trading.
-- Tip: Supabase → Authentication → Providers → Email:
--   • Keep "Confirm email" ON  → users must verify email before login.
--   • Or turn it OFF          → signup logs in instantly.
-- To make the app private after creating YOUR account:
--   Authentication → Settings → turn OFF "Allow new users to sign up".
-- ============================================================
