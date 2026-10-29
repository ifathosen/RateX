-- ============================================================
-- RateX FIX: creates the 3 missing tables + security + reloads
-- the API schema cache. Safe to run even if tables already exist.
-- Run in the CORRECT project: mazhidqjpvcxnpgexxlx
-- ============================================================

create extension if not exists pgcrypto;

create or replace function public.ratex_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- 3) SELL TRADES
create table if not exists public.ratex_trades (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id           uuid references public.ratex_customers(id) on delete set null,
  txn_date              date not null default current_date,
  delivery_method       text not null default 'bKash'
                          check (delivery_method in ('bKash','Nagad','Bank','Cash','Other')),
  receiver_info         text not null default '',
  bdt_amount            numeric(16,2) not null check (bdt_amount > 0),
  delivery_charge_bdt   numeric(16,2) not null default 0 check (delivery_charge_bdt >= 0),
  sell_rate             numeric(14,6) not null check (sell_rate > 0),
  sar_due               numeric(14,2) not null check (sar_due > 0),
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

-- 4) TRADE -> LOT ALLOCATIONS
create table if not exists public.ratex_trade_lots (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  trade_id          uuid not null references public.ratex_trades(id) on delete cascade,
  lot_id            uuid not null references public.ratex_stock_lots(id) on delete restrict,
  bdt_allocated     numeric(16,2) not null check (bdt_allocated > 0),
  cost_rate         numeric(14,6) not null check (cost_rate > 0),
  cost_sar          numeric(14,4) not null check (cost_sar >= 0),
  created_at        timestamptz not null default now()
);
create index if not exists ratex_tl_trade_idx on public.ratex_trade_lots (trade_id);
create index if not exists ratex_tl_lot_idx   on public.ratex_trade_lots (lot_id);
create index if not exists ratex_tl_user_idx  on public.ratex_trade_lots (user_id);

-- 5) SETTLEMENTS
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

-- Security for ALL 5 tables (re-applied, safe)
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
    execute format('create policy %I on public.%I for select using (auth.uid() = user_id)', t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (auth.uid() = user_id)', t || '_insert', t);
    execute format('create policy %I on public.%I for update using (auth.uid() = user_id) with check (auth.uid() = user_id)', t || '_update', t);
    execute format('create policy %I on public.%I for delete using (auth.uid() = user_id)', t || '_delete', t);
    execute format('grant select, insert, update, delete on public.%I to anon, authenticated', t);
  end loop;
end $$;

-- Force the REST API to pick up the new tables NOW
notify pgrst, 'reload schema';

-- Verification: this must list all 5 ratex_ tables
select table_name
from information_schema.tables
where table_schema = 'public' and table_name like 'ratex_%'
order by table_name;
