-- ============================================================
-- Pass Exchange Portal — Supabase schema (run in SQL Editor)
-- Order: extensions -> tables -> RLS -> trigger -> functions -> cron
-- ============================================================

-- 0. Extensions
create extension if not exists "pgcrypto";

-- 1. Tables ---------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  mobile text,
  created_at timestamptz not null default now()
);

create table if not exists public.instruments (
  pass_code text primary key,
  name text not null,
  prev_close numeric not null check (prev_close > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
-- Admin adds pass codes manually, e.g.:
-- insert into public.instruments (pass_code, name, prev_close)
-- values ('VIP2026', 'VIP Season Pass', 500);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  instrument_code text not null references public.instruments(pass_code),
  side text not null check (side in ('BUY', 'SELL')),
  price numeric not null check (price > 0),
  qty numeric not null check (qty > 0),
  remaining_qty numeric not null check (remaining_qty >= 0),
  status text not null default 'OPEN'
    check (status in ('OPEN', 'PARTIAL', 'FILLED', 'CANCELLED', 'EXPIRED')),
  created_at timestamptz not null default now()
);
create index if not exists orders_book_idx on public.orders
  (instrument_code, side, status, price, created_at)
  where status in ('OPEN', 'PARTIAL');
create index if not exists orders_user_idx on public.orders (user_id, created_at desc);

create table if not exists public.trades (
  id uuid primary key default gen_random_uuid(),
  instrument_code text not null references public.instruments(pass_code),
  price numeric not null check (price > 0),
  qty numeric not null check (qty > 0),
  buy_order_id uuid references public.orders(id),
  sell_order_id uuid references public.orders(id),
  buyer_id uuid,
  seller_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists trades_inst_idx on public.trades (instrument_code, created_at desc);
create index if not exists trades_party_idx on public.trades (buyer_id, seller_id, created_at desc);

-- 2. RLS ------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.instruments enable row level security;
alter table public.orders enable row level security;
alter table public.trades enable row level security;

-- 2a. Grants (required: RLS policies alone don't grant access) --
grant usage on schema public to anon, authenticated;
grant select on public.instruments to anon, authenticated;
grant select on public.trades to anon, authenticated;
grant select, insert, update on public.orders to authenticated;
grant select, insert, update, delete on public.orders to service_role;
grant select, insert, update on public.profiles to authenticated;

-- profiles: own row only (counterpart contact goes via get_my_matches)
drop policy if exists "profiles own" on public.profiles;
create policy "profiles own" on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

-- instruments: readable by any authenticated user; writes = admin via dashboard (service_role / owner)
drop policy if exists "instruments read auth" on public.instruments;
create policy "instruments read auth" on public.instruments
  for select to authenticated using (true);

-- orders: read today's book (all authenticated); insert/cancel own only.
-- Writes to trades/status matching happen inside SECURITY DEFINER function.
drop policy if exists "orders read auth" on public.orders;
create policy "orders read auth" on public.orders
  for select to authenticated using (true);
drop policy if exists "orders insert own" on public.orders;
create policy "orders insert own" on public.orders
  for insert to authenticated with check (auth.uid() = user_id);

-- trades: readable by authenticated (prices/volumes are public);
-- buyer/seller ids visible but phone numbers are NOT in this table.
drop policy if exists "trades read auth" on public.trades;
create policy "trades read auth" on public.trades
  for select to authenticated using (true);

-- 3. Auto-create profile on signup ------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Intraday boundary: midnight Asia/Kolkata as timestamptz.
-- (date_trunc('day', now()) would be UTC midnight = 05:30 IST — wrong.)
create or replace function public.ist_day_start()
returns timestamptz
language sql stable set search_path = public as $$
  select (date_trunc('day', now() at time zone 'Asia/Kolkata')) at time zone 'Asia/Kolkata';
$$;

-- 4. place_limit_order — price/time priority, maker price --------
-- Only matches today's orders (intraday book).
create or replace function public.place_limit_order(
  p_instrument text, p_side text, p_price numeric, p_qty numeric
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_taker_id uuid;
  v_taker_remaining numeric := p_qty;
  v_filled numeric := 0;
  v_maker record;
  v_take numeric;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if p_side not in ('BUY', 'SELL') then raise exception 'Side must be BUY or SELL'; end if;
  if p_price is null or p_price <= 0 then raise exception 'Price must be > 0'; end if;
  if p_qty is null or p_qty <= 0 or p_qty != trunc(p_qty) then raise exception 'Qty must be a positive whole number'; end if;
  if not exists (select 1 from public.instruments where pass_code = p_instrument and is_active) then
    raise exception 'Unknown or inactive pass code';
  end if;

  insert into public.orders (user_id, instrument_code, side, price, qty, remaining_qty, status)
  values (v_uid, p_instrument, p_side, p_price, p_qty, p_qty, 'OPEN')
  returning id into v_taker_id;

  -- Match against opposite side, price-compatible, oldest first.
  for v_maker in
    select * from public.orders
    where instrument_code = p_instrument
      and status in ('OPEN', 'PARTIAL')
      and id != v_taker_id
      and user_id != v_uid
      and created_at >= public.ist_day_start()
      and ((p_side = 'BUY' and side = 'SELL' and price <= p_price)
        or (p_side = 'SELL' and side = 'BUY' and price >= p_price))
    order by
      case when p_side = 'BUY' then price end asc,
      case when p_side = 'SELL' then price end desc,
      created_at asc
    for update skip locked
  loop
    exit when v_taker_remaining <= 0;
    v_take := least(v_taker_remaining, v_maker.remaining_qty);

    insert into public.trades (instrument_code, price, qty, buy_order_id, sell_order_id, buyer_id, seller_id)
    values (
      p_instrument,
      v_maker.price, -- trade at maker price (standard)
      v_take,
      case when p_side = 'BUY' then v_taker_id else v_maker.id end,
      case when p_side = 'BUY' then v_maker.id else v_taker_id end,
      case when p_side = 'BUY' then v_uid else v_maker.user_id end,
      case when p_side = 'BUY' then v_maker.user_id else v_uid end
    );

    update public.orders
    set remaining_qty = remaining_qty - v_take,
        status = case when remaining_qty - v_take = 0 then 'FILLED' else 'PARTIAL' end
    where id = v_maker.id;

    v_taker_remaining := v_taker_remaining - v_take;
    v_filled := v_filled + v_take;
  end loop;

  update public.orders
  set remaining_qty = v_taker_remaining,
      status = case
        when v_taker_remaining = 0 then 'FILLED'
        when v_filled > 0 then 'PARTIAL'
        else 'OPEN' end
  where id = v_taker_id;

  return jsonb_build_object('order_id', v_taker_id, 'filled', v_filled, 'remaining', v_taker_remaining);
end $$;

-- 5. cancel_my_order — today's own open orders only --------------
create or replace function public.cancel_my_order(p_order_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.orders
  set status = 'CANCELLED'
  where id = p_order_id
    and user_id = auth.uid()
    and status in ('OPEN', 'PARTIAL')
    and created_at >= public.ist_day_start();
  if not found then raise exception 'Order not found or not cancellable'; end if;
end $$;

-- 6. get_my_matches — counterpart contact for my fills only ------
-- Privacy: caller sees ONLY trades where they are buyer or seller.
create or replace function public.get_my_matches(p_date date default current_date)
returns table (
  trade_id uuid, instrument_code text, my_side text,
  price numeric, qty numeric,
  counterpart_name text, counterpart_mobile text, created_at timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  return query
  select t.id, t.instrument_code,
    case when t.buyer_id = auth.uid() then 'BOUGHT' else 'SOLD' end,
    t.price, t.qty,
    p.name, p.mobile, t.created_at
  from public.trades t
  join public.profiles p
    on p.id = case when t.buyer_id = auth.uid() then t.seller_id else t.buyer_id end
  where (t.buyer_id = auth.uid() or t.seller_id = auth.uid())
    and t.created_at >= p_date::timestamptz
    and t.created_at < (p_date + 1)::timestamptz
  order by t.created_at desc;
end $$;

-- 7. Daily expiry — expire yesterday's book, roll prev_close ----
create or replace function public.expire_orders_daily()
returns void
language plpgsql security definer set search_path = public as $$
declare r record;
declare v_start timestamptz := public.ist_day_start();
begin
  -- Roll prev_close to each instrument's last trade price (keeps % change correct)
  for r in
    select distinct instrument_code from public.trades
    where created_at >= v_start - interval '1 day'
      and created_at < v_start
  loop
    update public.instruments i
    set prev_close = (
      select t.price from public.trades t
      where t.instrument_code = r.instrument_code
      order by t.created_at desc limit 1
    )
    where i.pass_code = r.instrument_code;
  end loop;

  update public.orders
  set status = 'EXPIRED'
  where status in ('OPEN', 'PARTIAL')
    and created_at < v_start;
end $$;

-- 8. Cron — schedule expire_orders_daily at 00:00 Asia/Kolkata ----
-- pg_cron runs in UTC; 00:00 IST = 18:30 UTC (previous day).
-- Run once in SQL Editor (requires pg_cron enabled: Database > Extensions):
--
--   create extension if not exists pg_cron;
--   select cron.schedule(
--     'passx-midnight-expiry',
--     '30 18 * * *',
--     $$select public.expire_orders_daily()$$
--   );
--
-- Verify: select * from cron.job;

-- 9. Function grants (SECURITY DEFINER still needs EXECUTE) --
grant execute on function public.place_limit_order(text, text, numeric, numeric) to authenticated;
grant execute on function public.cancel_my_order(uuid) to authenticated;
grant execute on function public.get_my_matches(date) to authenticated;
