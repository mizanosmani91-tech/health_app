-- স্বাস্থ্য ডায়েরি — Supabase schema
-- Patient health data (visits, medicines, tests, prescriptions) stays ON THE PHONE
-- and in the user's own Google Drive. This database only holds what has to be
-- shared between the two roles: accounts/roles, pharmacies, stock status,
-- patient->pharmacy requests, and the pharmacy owner's own books.
--
-- Run in the Supabase SQL editor (or `supabase db push`). Safe to re-run.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- profiles
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       text not null check (role in ('patient', 'owner')),
  full_name  text,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select using (id = auth.uid());
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles for insert with check (id = auth.uid());
-- The role is chosen once. The app upserts, so allow update but only of the name:
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from authenticated;
grant update (full_name) on public.profiles to authenticated;

-- --------------------------------------------------------------- pharmacies
create table if not exists public.pharmacies (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null unique references auth.users(id) on delete cascade,
  name          text not null,
  address       text not null,
  phone         text not null,
  license_no    text not null,
  license_path  text,                                  -- storage path in bucket "licenses"
  status        text not null default 'pending' check (status in ('pending', 'verified', 'rejected')),
  is_open       boolean not null default true,
  open_from     time not null default '09:00',
  open_to       time not null default '22:00',
  weekly_off    text,
  notify_new    boolean not null default true,
  created_at    timestamptz not null default now()
);
alter table public.pharmacies enable row level security;

create or replace function public.owns_pharmacy(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.pharmacies where id = pid and owner_id = auth.uid());
$$;

drop policy if exists pharmacies_select on public.pharmacies;
create policy pharmacies_select on public.pharmacies for select
  using (owner_id = auth.uid() or status = 'verified');
drop policy if exists pharmacies_insert on public.pharmacies;
create policy pharmacies_insert on public.pharmacies for insert
  with check (owner_id = auth.uid() and status = 'pending'
              and exists (select 1 from public.profiles where id = auth.uid() and role = 'owner'));
drop policy if exists pharmacies_update on public.pharmacies;
create policy pharmacies_update on public.pharmacies for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- Owners can never touch verification status or ownership:
revoke update on public.pharmacies from authenticated;
grant update (name, address, phone, license_no, license_path, is_open, open_from, open_to, weekly_off, notify_new)
  on public.pharmacies to authenticated;

-- ------------------------------------------------------------ medicine catalog
create table if not exists public.medicine_catalog (
  id           bigint generated always as identity primary key,
  name         text not null,
  generic_name text,
  manufacturer text,
  form         text
);
create index if not exists medicine_catalog_name_idx on public.medicine_catalog (lower(name));
alter table public.medicine_catalog enable row level security;
drop policy if exists catalog_read on public.medicine_catalog;
create policy catalog_read on public.medicine_catalog for select using (auth.uid() is not null);

insert into public.medicine_catalog (name, generic_name, manufacturer, form)
select * from (values
  ('নাপা ৫০০ মি.গ্রা.', 'প্যারাসিটামল', 'বেক্সিমকো', 'ট্যাবলেট'),
  ('নাপা এক্সট্রা', 'প্যারাসিটামল + ক্যাফেইন', 'বেক্সিমকো', 'ট্যাবলেট'),
  ('নাপা সিরাপ', 'প্যারাসিটামল', 'বেক্সিমকো', 'সিরাপ'),
  ('ওমিপ্রাজল ২০', 'ওমিপ্রাজল', 'স্কয়ার', 'ক্যাপসুল'),
  ('সারজেল ২০', 'এসোমিপ্রাজল', 'স্কয়ার', 'ট্যাবলেট'),
  ('ফেক্সো ১২০', 'ফেক্সোফেনাডিন', 'স্কয়ার', 'ট্যাবলেট'),
  ('মন্টিনেক্স ১০', 'মন্টেলুকাস্ট', 'এসকেএফ', 'ট্যাবলেট'),
  ('সিপ্রোসিন ৫০০', 'সিপ্রোফ্লক্সাসিন', 'ইনসেপ্টা', 'ট্যাবলেট'),
  ('ভিটামিন ডি ৪০০০', 'কোলক্যালসিফেরল', null, 'ক্যাপসুল')
) as v(name, generic_name, manufacturer, form)
where not exists (select 1 from public.medicine_catalog);

-- -------------------------------------------------------------------- stock
-- Patients never read this table (it has prices). They use search_stock() below,
-- which exposes only in / low / out.
create table if not exists public.stock_items (
  id           uuid primary key default gen_random_uuid(),
  pharmacy_id  uuid not null references public.pharmacies(id) on delete cascade,
  name         text not null,
  generic_name text,
  form         text,
  qty          numeric,
  unit         text,
  buy_price    numeric,
  sell_price   numeric,
  expiry       date,
  batch_no     text,
  status       text not null default 'in' check (status in ('in', 'low', 'out')),
  last_sold_at timestamptz,
  updated_at   timestamptz not null default now()
);
create index if not exists stock_items_pharmacy_idx on public.stock_items (pharmacy_id);
alter table public.stock_items enable row level security;
drop policy if exists stock_owner_all on public.stock_items;
create policy stock_owner_all on public.stock_items for all
  using (public.owns_pharmacy(pharmacy_id)) with check (public.owns_pharmacy(pharmacy_id));

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists stock_touch on public.stock_items;
create trigger stock_touch before update on public.stock_items for each row execute function public.touch_updated_at();

-- ------------------------------------------------------- patient-facing search
create or replace function public.search_stock(p_names text[])
returns table (
  pharmacy_id uuid, pharmacy_name text, address text, phone text, is_open boolean,
  medicine_name text, status text, updated_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select ph.id, ph.name, ph.address, ph.phone, ph.is_open, n.name,
         coalesce(
           case
             when bool_or(s.status = 'in')  then 'in'
             when bool_or(s.status = 'low') then 'low'
             when bool_or(s.status = 'out') then 'out'
           end, 'unknown'),
         (select max(x.updated_at) from public.stock_items x where x.pharmacy_id = ph.id)
  from public.pharmacies ph
  cross join unnest(p_names) as n(name)
  left join public.stock_items s
         on s.pharmacy_id = ph.id
        and (s.name ilike '%' || n.name || '%' or s.generic_name ilike '%' || n.name || '%')
  where auth.uid() is not null and ph.status = 'verified'
  group by ph.id, ph.name, ph.address, ph.phone, ph.is_open, n.name
  order by ph.name, n.name;
$$;
revoke all on function public.search_stock(text[]) from public, anon;
grant execute on function public.search_stock(text[]) to authenticated;

-- ----------------------------------------------------------------- requests
create table if not exists public.med_requests (
  id            uuid primary key default gen_random_uuid(),
  pharmacy_id   uuid not null references public.pharmacies(id) on delete cascade,
  patient_id    uuid not null references auth.users(id) on delete cascade,
  patient_name  text not null,
  status        text not null default 'new' check (status in ('new', 'replied')),
  reply_message text,
  created_at    timestamptz not null default now(),
  replied_at    timestamptz
);
create table if not exists public.med_request_items (
  id            uuid primary key default gen_random_uuid(),
  request_id    uuid not null references public.med_requests(id) on delete cascade,
  medicine_name text not null,
  days          int,
  availability  text not null default 'pending' check (availability in ('pending', 'yes', 'no'))
);
create index if not exists med_requests_pharmacy_idx on public.med_requests (pharmacy_id, created_at desc);
create index if not exists med_requests_patient_idx  on public.med_requests (patient_id, created_at desc);
create index if not exists med_request_items_req_idx on public.med_request_items (request_id);
alter table public.med_requests enable row level security;
alter table public.med_request_items enable row level security;

drop policy if exists req_patient_select on public.med_requests;
create policy req_patient_select on public.med_requests for select using (patient_id = auth.uid());
drop policy if exists req_owner_select on public.med_requests;
create policy req_owner_select on public.med_requests for select using (public.owns_pharmacy(pharmacy_id));
drop policy if exists req_owner_update on public.med_requests;
create policy req_owner_update on public.med_requests for update
  using (public.owns_pharmacy(pharmacy_id)) with check (public.owns_pharmacy(pharmacy_id));
revoke update on public.med_requests from authenticated;
grant update (status, reply_message, replied_at) on public.med_requests to authenticated;

drop policy if exists item_select on public.med_request_items;
create policy item_select on public.med_request_items for select using (
  exists (select 1 from public.med_requests r where r.id = request_id
          and (r.patient_id = auth.uid() or public.owns_pharmacy(r.pharmacy_id))));
drop policy if exists item_owner_update on public.med_request_items;
create policy item_owner_update on public.med_request_items for update using (
  exists (select 1 from public.med_requests r where r.id = request_id and public.owns_pharmacy(r.pharmacy_id)));
revoke update on public.med_request_items from authenticated;
grant update (availability) on public.med_request_items to authenticated;

-- Patients create requests only through this function (validates pharmacy + role).
create or replace function public.create_med_request(p_pharmacy_id uuid, p_patient_name text, p_items jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare rid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'patient') then
    raise exception 'only patients can send requests';
  end if;
  if not exists (select 1 from public.pharmacies where id = p_pharmacy_id and status = 'verified') then
    raise exception 'pharmacy not available';
  end if;
  if jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 30 then
    raise exception 'invalid item list';
  end if;
  insert into public.med_requests (pharmacy_id, patient_id, patient_name)
  values (p_pharmacy_id, auth.uid(), left(p_patient_name, 80)) returning id into rid;
  insert into public.med_request_items (request_id, medicine_name, days)
  select rid, left(i->>'name', 120), nullif(i->>'days', '')::int from jsonb_array_elements(p_items) i;
  return rid;
end $$;
revoke all on function public.create_med_request(uuid, text, jsonb) from public, anon;
grant execute on function public.create_med_request(uuid, text, jsonb) to authenticated;

-- ------------------------------------------------------- owner books (hisab)
create table if not exists public.ledger_entries (
  id          uuid primary key default gen_random_uuid(),
  pharmacy_id uuid not null references public.pharmacies(id) on delete cascade,
  kind        text not null check (kind in ('income', 'expense')),
  title       text not null,
  note        text,
  amount      numeric not null check (amount >= 0),
  entry_date  date not null default current_date,
  created_at  timestamptz not null default now()
);
create index if not exists ledger_pharmacy_idx on public.ledger_entries (pharmacy_id, entry_date desc);
alter table public.ledger_entries enable row level security;
drop policy if exists ledger_owner_all on public.ledger_entries;
create policy ledger_owner_all on public.ledger_entries for all
  using (public.owns_pharmacy(pharmacy_id)) with check (public.owns_pharmacy(pharmacy_id));

-- Credit book: direction 'receivable' = customers owe me (আমি পাবো), 'payable' = I owe suppliers (আমি দেবো)
create table if not exists public.khata_entries (
  id          uuid primary key default gen_random_uuid(),
  pharmacy_id uuid not null references public.pharmacies(id) on delete cascade,
  direction   text not null check (direction in ('receivable', 'payable')),
  party_name  text not null,
  phone       text,
  amount      numeric not null check (amount > 0),
  paid        numeric not null default 0 check (paid >= 0),
  note        text,
  created_at  timestamptz not null default now(),
  check (paid <= amount)
);
create index if not exists khata_pharmacy_idx on public.khata_entries (pharmacy_id, direction);
alter table public.khata_entries enable row level security;
drop policy if exists khata_owner_all on public.khata_entries;
create policy khata_owner_all on public.khata_entries for all
  using (public.owns_pharmacy(pharmacy_id)) with check (public.owns_pharmacy(pharmacy_id));

-- ------------------------------------------------------------------ storage
-- Private bucket for drug-licence photos; each owner can only touch "<uid>/...".
insert into storage.buckets (id, name, public) values ('licenses', 'licenses', false)
on conflict (id) do nothing;
drop policy if exists licenses_owner_rw on storage.objects;
create policy licenses_owner_rw on storage.objects for all
  using (bucket_id = 'licenses' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'licenses' and (storage.foldername(name))[1] = auth.uid()::text);

-- Verifying a pharmacy is done by an admin in the dashboard:
--   update public.pharmacies set status = 'verified' where id = '<pharmacy id>';
