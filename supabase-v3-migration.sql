-- ============================================================
--  RateX v3 Migration — Accounts, Transfers, Remit No.
--  + REPAIRS all Row-Level-Security policies (fixes the error:
--    "new row violates row-level security policy")
--
--  Run ONCE: Supabase → SQL Editor → New query → paste ALL →
--  make sure NOTHING is highlighted/selected → Run.
--  Project: mazhidqjpvcxnpgexxlx
--  Safe to re-run. Existing rows are kept.
-- ============================================================

create extension if not exists pgcrypto;

create or replace function public.ratex_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ============================================================
-- 1) ACCOUNTS (Saudi Bank SAR, Cash SAR, BD Bank BDT, ...)
-- ============================================================
create table if not exists public.ratex_accounts (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name            text not null,
  currency        text not null check (currency in ('SAR','BDT')),
  type            text not null default 'Bank'
                    check (type in ('Saudi Bank','BD Bank','Cash','Mobile Wallet','Bank','Other')),
  opening_balance numeric(16,2) not null default 0,
  opening_date    date not null default current_date,
  note            text not null default '',
  archived        boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists ratex_accounts_user_idx on public.ratex_accounts (user_id);
drop trigger if exists ratex_accounts_upd on public.ratex_accounts;
create trigger ratex_accounts_upd before update on public.ratex_accounts
  for each row execute function public.ratex_set_updated_at();

-- ============================================================
-- 2) TRANSFERS (e.g. Cash SAR -> Saudi Bank SAR)
--    Source is debited amount + fee; destination gets amount.
-- ============================================================
create table if not exists public.ratex_transfers (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  txn_date        date not null default current_date,
  from_account_id uuid references public.ratex_accounts(id) on delete set null,
  to_account_id   uuid references public.ratex_accounts(id) on delete set null,
  amount          numeric(16,2) not null check (amount > 0),
  fee             numeric(16,2) not null default 0 check (fee >= 0),
  note            text not null default '',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists ratex_transfers_user_date_idx
  on public.ratex_transfers (user_id, txn_date desc);
drop trigger if exists ratex_transfers_upd on public.ratex_transfers;
create trigger ratex_transfers_upd before update on public.ratex_transfers
  for each row execute function public.ratex_set_updated_at();

-- ============================================================
-- 3) NEW COLUMNS on existing tables
-- ============================================================
alter table public.ratex_stock_lots
  add column if not exists remit_no       text not null default '',
  add column if not exists kind           text not null default 'remittance',
  add column if not exists sar_account_id uuid references public.ratex_accounts(id) on delete set null,
  add column if not exists bdt_account_id uuid references public.ratex_accounts(id) on delete set null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ratex_stock_lots_kind_check') then
    alter table public.ratex_stock_lots
      add constraint ratex_stock_lots_kind_check check (kind in ('remittance','opening'));
  end if;
end $$;

create unique index if not exists ratex_lots_remit_no_unique
  on public.ratex_stock_lots (user_id, remit_no) where remit_no <> '';
create index if not exists ratex_lots_sar_acc_idx on public.ratex_stock_lots (sar_account_id);
create index if not exists ratex_lots_bdt_acc_idx on public.ratex_stock_lots (bdt_account_id);

alter table public.ratex_trades
  add column if not exists source_account_id uuid references public.ratex_accounts(id) on delete set null;
create index if not exists ratex_trades_source_acc_idx
  on public.ratex_trades (source_account_id);

-- delivery method becomes free text (custom bank names etc.)
alter table public.ratex_trades drop constraint if exists ratex_trades_delivery_method_check;

alter table public.ratex_settlements
  add column if not exists account_id uuid references public.ratex_accounts(id) on delete set null;
create index if not exists ratex_settlements_acc_idx
  on public.ratex_settlements (account_id);

-- ============================================================
-- 4) ROW LEVEL SECURITY — rebuilt EXPLICITLY for all 7 tables
--    (each user can select/insert/update/delete only own rows)
-- ============================================================
alter table public.ratex_customers    enable row level security;
alter table public.ratex_stock_lots   enable row level security;
alter table public.ratex_trades       enable row level security;
alter table public.ratex_trade_lots   enable row level security;
alter table public.ratex_settlements  enable row level security;
alter table public.ratex_accounts     enable row level security;
alter table public.ratex_transfers    enable row level security;

-- ratex_customers
drop policy if exists ratex_customers_select on public.ratex_customers;
drop policy if exists ratex_customers_insert on public.ratex_customers;
drop policy if exists ratex_customers_update on public.ratex_customers;
drop policy if exists ratex_customers_delete on public.ratex_customers;
create policy ratex_customers_select on public.ratex_customers for select using (auth.uid() = user_id);
create policy ratex_customers_insert on public.ratex_customers for insert with check (auth.uid() = user_id);
create policy ratex_customers_update on public.ratex_customers for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy ratex_customers_delete on public.ratex_customers for delete using (auth.uid() = user_id);

-- ratex_stock_lots
drop policy if exists ratex_stock_lots_select on public.ratex_stock_lots;
drop policy if exists ratex_stock_lots_insert on public.ratex_stock_lots;
drop policy if exists ratex_stock_lots_update on public.ratex_stock_lots;
drop policy if exists ratex_stock_lots_delete on public.ratex_stock_lots;
create policy ratex_stock_lots_select on public.ratex_stock_lots for select using (auth.uid() = user_id);
create policy ratex_stock_lots_insert on public.ratex_stock_lots for insert with check (auth.uid() = user_id);
create policy ratex_stock_lots_update on public.ratex_stock_lots for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy ratex_stock_lots_delete on public.ratex_stock_lots for delete using (auth.uid() = user_id);

-- ratex_trades
drop policy if exists ratex_trades_select on public.ratex_trades;
drop policy if exists ratex_trades_insert on public.ratex_trades;
drop policy if exists ratex_trades_update on public.ratex_trades;
drop policy if exists ratex_trades_delete on public.ratex_trades;
create policy ratex_trades_select on public.ratex_trades for select using (auth.uid() = user_id);
create policy ratex_trades_insert on public.ratex_trades for insert with check (auth.uid() = user_id);
create policy ratex_trades_update on public.ratex_trades for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy ratex_trades_delete on public.ratex_trades for delete using (auth.uid() = user_id);

-- ratex_trade_lots
drop policy if exists ratex_trade_lots_select on public.ratex_trade_lots;
drop policy if exists ratex_trade_lots_insert on public.ratex_trade_lots;
drop policy if exists ratex_trade_lots_update on public.ratex_trade_lots;
drop policy if exists ratex_trade_lots_delete on public.ratex_trade_lots;
create policy ratex_trade_lots_select on public.ratex_trade_lots for select using (auth.uid() = user_id);
create policy ratex_trade_lots_insert on public.ratex_trade_lots for insert with check (auth.uid() = user_id);
create policy ratex_trade_lots_update on public.ratex_trade_lots for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy ratex_trade_lots_delete on public.ratex_trade_lots for delete using (auth.uid() = user_id);

-- ratex_settlements
drop policy if exists ratex_settlements_select on public.ratex_settlements;
drop policy if exists ratex_settlements_insert on public.ratex_settlements;
drop policy if exists ratex_settlements_update on public.ratex_settlements;
drop policy if exists ratex_settlements_delete on public.ratex_settlements;
create policy ratex_settlements_select on public.ratex_settlements for select using (auth.uid() = user_id);
create policy ratex_settlements_insert on public.ratex_settlements for insert with check (auth.uid() = user_id);
create policy ratex_settlements_update on public.ratex_settlements for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy ratex_settlements_delete on public.ratex_settlements for delete using (auth.uid() = user_id);

-- ratex_accounts
drop policy if exists ratex_accounts_select on public.ratex_accounts;
drop policy if exists ratex_accounts_insert on public.ratex_accounts;
drop policy if exists ratex_accounts_update on public.ratex_accounts;
drop policy if exists ratex_accounts_delete on public.ratex_accounts;
create policy ratex_accounts_select on public.ratex_accounts for select using (auth.uid() = user_id);
create policy ratex_accounts_insert on public.ratex_accounts for insert with check (auth.uid() = user_id);
create policy ratex_accounts_update on public.ratex_accounts for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy ratex_accounts_delete on public.ratex_accounts for delete using (auth.uid() = user_id);

-- ratex_transfers
drop policy if exists ratex_transfers_select on public.ratex_transfers;
drop policy if exists ratex_transfers_insert on public.ratex_transfers;
drop policy if exists ratex_transfers_update on public.ratex_transfers;
drop policy if exists ratex_transfers_delete on public.ratex_transfers;
create policy ratex_transfers_select on public.ratex_transfers for select using (auth.uid() = user_id);
create policy ratex_transfers_insert on public.ratex_transfers for insert with check (auth.uid() = user_id);
create policy ratex_transfers_update on public.ratex_transfers for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy ratex_transfers_delete on public.ratex_transfers for delete using (auth.uid() = user_id);

grant select, insert, update, delete on
  public.ratex_customers, public.ratex_stock_lots, public.ratex_trades,
  public.ratex_trade_lots, public.ratex_settlements,
  public.ratex_accounts, public.ratex_transfers
to anon, authenticated;

notify pgrst, 'reload schema';

-- Verification A: must list 7 tables
select table_name from information_schema.tables
where table_schema = 'public' and table_name like 'ratex_%'
order by table_name;

-- Verification B: must show 4 policies (select/insert/update/delete) per table
select tablename, count(*) as policies
from pg_policies
where schemaname = 'public' and tablename like 'ratex_%'
group by tablename
order by tablename;
