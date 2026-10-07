create table if not exists public.households(
  id         uuid primary key default gen_random_uuid(),
  name       text not null default 'משק הבית שלי',
  created_at timestamptz not null default now()
);

create table if not exists public.household_members(
  household_id uuid not null references public.households(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  role         text not null default 'owner'
               check (role in ('owner','partner','advisor')),
  created_at   timestamptz not null default now(),
  primary key (household_id, user_id)
);

create index if not exists hm_user_idx on public.household_members (user_id);

create table if not exists public.profiles(
  user_id      uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at   timestamptz not null default now()
);

create or replace function public.is_member(p_household uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.household_members
     where household_id = p_household and user_id = auth.uid()
  )
$$;

create table if not exists public.categories(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid references public.households(id) on delete cascade,
  key          text,
  label        text not null,
  icon         text,
  kind         text not null default 'expense' check (kind in ('expense','income')),
  sort         integer not null default 100,
  archived     boolean not null default false,
  created_at   timestamptz not null default now()
);

create index if not exists categories_household_idx on public.categories (household_id);
create unique index if not exists categories_system_key_idx
  on public.categories (key) where household_id is null;

insert into public.categories (household_id, key, label, icon, kind, sort) values
  (null, 'housing',   'דיור',        '🏠', 'expense', 10),
  (null, 'food',      'מזון',        '🛒', 'expense', 20),
  (null, 'transport', 'תחבורה',      '🚗', 'expense', 30),
  (null, 'debt',      'החזרים',      '🏦', 'expense', 40),
  (null, 'fun',       'בילויים',     '🎬', 'expense', 50),
  (null, 'other',     'כל השאר',     '•',  'expense', 60),
  (null, 'salary',    'משכורת',      '💼', 'income',  10),
  (null, 'other_in',  'הכנסה אחרת',  '•',  'income',  20)
on conflict (key) where household_id is null do nothing;

create table if not exists public.budgets(
  household_id   uuid not null references public.households(id) on delete cascade,
  month          date not null,                       -- תמיד ה-1 בחודש
  category_id    uuid not null references public.categories(id) on delete cascade,
  planned_agorot bigint not null default 0 check (planned_agorot >= 0),
  updated_at     timestamptz not null default now(),
  primary key (household_id, month, category_id)
);

create table if not exists public.transactions(
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  occurred_on   date not null,
  amount_agorot bigint not null check (amount_agorot > 0),
  direction     text not null check (direction in ('in','out')),
  category_id   uuid references public.categories(id) on delete set null,
  description   text,
  source        text not null default 'manual' check (source in ('manual','import')),

  installment_no    integer check (installment_no    is null or installment_no    > 0),
  installment_total integer check (installment_total is null or installment_total > 0),

  charged_on    date,

  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now()
);

create index if not exists tx_household_date_idx on public.transactions (household_id, occurred_on desc);
create index if not exists tx_category_idx       on public.transactions (household_id, category_id);

alter table public.households        enable row level security;
alter table public.household_members enable row level security;
alter table public.profiles          enable row level security;
alter table public.categories        enable row level security;
alter table public.budgets           enable row level security;
alter table public.transactions      enable row level security;

drop policy if exists hh_rw        on public.households;
drop policy if exists hh_read      on public.households;
drop policy if exists hh_update    on public.households;
drop policy if exists hh_delete    on public.households;
drop policy if exists hm_read      on public.household_members;
drop policy if exists hm_self      on public.household_members;
drop policy if exists hm_read_self on public.household_members;
drop policy if exists hm_read_house on public.household_members;
drop policy if exists hm_leave     on public.household_members;
drop policy if exists pr_rw        on public.profiles;
drop policy if exists cat_read     on public.categories;
drop policy if exists cat_write    on public.categories;
drop policy if exists bud_rw       on public.budgets;
drop policy if exists tx_rw        on public.transactions;

create policy hh_read on public.households for select to authenticated
  using (public.is_member(id));
create policy hh_update on public.households for update to authenticated
  using (public.is_member(id)) with check (public.is_member(id));
create policy hh_delete on public.households for delete to authenticated
  using (exists (select 1 from public.household_members m
                  where m.household_id = households.id
                    and m.user_id = auth.uid()
                    and m.role = 'owner'));

create policy hm_read_self on public.household_members for select to authenticated
  using (user_id = auth.uid());
create policy hm_read_house on public.household_members for select to authenticated
  using (public.is_member(household_id));
create policy hm_leave on public.household_members for delete to authenticated
  using (user_id = auth.uid() and role <> 'owner');

create policy pr_rw on public.profiles for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy cat_read on public.categories for select to authenticated
  using (household_id is null or public.is_member(household_id));
create policy cat_write on public.categories for all to authenticated
  using (household_id is not null and public.is_member(household_id))
  with check (household_id is not null and public.is_member(household_id));

create policy bud_rw on public.budgets for all to authenticated
  using (public.is_member(household_id)) with check (public.is_member(household_id));

create policy tx_rw on public.transactions for all to authenticated
  using (public.is_member(household_id)) with check (public.is_member(household_id));

revoke all on table public.households, public.household_members, public.profiles,
                    public.categories, public.budgets, public.transactions from anon;
grant select, insert, update, delete on table
  public.profiles, public.categories, public.budgets,
  public.transactions to authenticated;
grant select, update, delete on table public.households        to authenticated;
grant select,         delete on table public.household_members to authenticated;

create or replace function public.setup_household(
  p_name    text,
  p_income  bigint,                  -- באגורות
  p_budget  jsonb                    -- {"housing":500000,"food":200000,...}
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user  uuid := auth.uid();
  v_hh    uuid;
  v_month date := date_trunc('month', current_date)::date;
  v_key   text;
  v_cat   uuid;
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;

  select household_id into v_hh from public.household_members
   where user_id = v_user limit 1;
  if v_hh is not null then
    return v_hh;
  end if;

  insert into public.households (name)
  values (left(coalesce(nullif(btrim(p_name),''),'משק הבית שלי'), 60))
  returning id into v_hh;

  insert into public.household_members (household_id, user_id, role)
  values (v_hh, v_user, 'owner');

  insert into public.profiles (user_id, display_name)
  values (v_user, left(nullif(btrim(p_name),''), 60))
  on conflict (user_id) do nothing;

  if coalesce(p_income,0) > 0 then
    select id into v_cat from public.categories
     where household_id is null and key = 'salary';
    if v_cat is not null then
      insert into public.budgets (household_id, month, category_id, planned_agorot)
      values (v_hh, v_month, v_cat, greatest(p_income,0))
      on conflict (household_id, month, category_id) do update
        set planned_agorot = excluded.planned_agorot, updated_at = now();
    end if;
  end if;

  for v_key in select jsonb_object_keys(coalesce(p_budget,'{}'::jsonb)) loop
    select id into v_cat from public.categories
     where household_id is null and key = v_key;
    if v_cat is not null then
      insert into public.budgets (household_id, month, category_id, planned_agorot)
      values (v_hh, v_month, v_cat,
              greatest((p_budget ->> v_key)::bigint, 0))
      on conflict (household_id, month, category_id) do update
        set planned_agorot = excluded.planned_agorot, updated_at = now();
    end if;
  end loop;

  return v_hh;
end $$;

revoke all on function public.setup_household(text,bigint,jsonb) from public;
grant execute on function public.setup_household(text,bigint,jsonb) to authenticated;

create table if not exists public.reflections(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  kind         text not null check (kind in ('overspend','month_end')),
  month        date not null,                      -- תמיד ה-1 בחודש
  category_id  uuid references public.categories(id) on delete set null,
  choice       text,
  note         text,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),

  constraint reflections_choice_len check (choice is null or length(choice) <= 60),
  constraint reflections_note_len   check (note   is null or length(note)   <= 500),
  constraint reflections_shape check (
    (kind = 'overspend' and category_id is not null) or
    (kind = 'month_end' and category_id is null)
  )
);

create index if not exists reflections_hh_month_idx
  on public.reflections (household_id, month desc);

create unique index if not exists reflections_once_cat_idx
  on public.reflections (household_id, kind, month, category_id)
  where category_id is not null;

create unique index if not exists reflections_once_month_idx
  on public.reflections (household_id, kind, month)
  where category_id is null;

alter table public.reflections enable row level security;

drop policy if exists refl_rw on public.reflections;
create policy refl_rw on public.reflections for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.reflections from anon;
grant select, insert, update, delete on table public.reflections to authenticated;

create table if not exists public.documents(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,

  kind         text not null default 'other'
               check (kind in ('loan','bill','statement','other')),

  title        text not null,
  provider     text,                      -- חברת חשמל, מזרחי טפחות
  period       date,                      -- לאיזה חודש המסמך שייך

  amount_agorot bigint check (amount_agorot is null or amount_agorot >= 0),
  due_on       date,
  data         jsonb not null default '{}'::jsonb,

  storage_path text,
  mime         text,
  size_bytes   integer check (size_bytes is null or size_bytes >= 0),

  transaction_id uuid references public.transactions(id) on delete set null,

  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),

  constraint documents_title_len check (length(btrim(title)) between 1 and 160),
  constraint documents_provider_len check (provider is null or length(provider) <= 80)
);

create index if not exists documents_hh_idx on public.documents (household_id, created_at desc);
create index if not exists documents_kind_idx on public.documents (household_id, kind, period desc);

alter table public.documents enable row level security;
drop policy if exists doc_rw on public.documents;
create policy doc_rw on public.documents for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.documents from anon;
grant select, insert, update, delete on table public.documents to authenticated;

create table if not exists public.imports(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  source       text not null default 'file'
               check (source in ('file','manual')),
  kind         text not null default 'bank'
               check (kind in ('bank','credit','other')),
  file_name    text,
  file_hash    text,
  rows_total   integer not null default 0 check (rows_total >= 0),
  rows_taken   integer not null default 0 check (rows_taken >= 0),
  charged_on   date,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now()
);

create index if not exists imports_hh_idx on public.imports (household_id, created_at desc);
create unique index if not exists imports_hash_idx
  on public.imports (household_id, file_hash) where file_hash is not null;

alter table public.imports enable row level security;
drop policy if exists imp_rw on public.imports;
create policy imp_rw on public.imports for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.imports from anon;
grant select, insert, update, delete on table public.imports to authenticated;

alter table public.transactions
  add column if not exists import_id uuid references public.imports(id) on delete set null;

create index if not exists tx_import_idx on public.transactions (import_id)
  where import_id is not null;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('docs', 'docs', false, 15728640,
        array['application/pdf','image/jpeg','image/png','image/webp',
              'text/csv','application/vnd.ms-excel',
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists docs_read   on storage.objects;
drop policy if exists docs_write  on storage.objects;
drop policy if exists docs_update on storage.objects;
drop policy if exists docs_delete on storage.objects;

create policy docs_read on storage.objects for select to authenticated
  using (bucket_id = 'docs'
         and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));

create policy docs_write on storage.objects for insert to authenticated
  with check (bucket_id = 'docs'
              and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));

create policy docs_update on storage.objects for update to authenticated
  using (bucket_id = 'docs'
         and public.is_member(nullif((storage.foldername(name))[1], '')::uuid))
  with check (bucket_id = 'docs'
              and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));

create policy docs_delete on storage.objects for delete to authenticated
  using (bucket_id = 'docs'
         and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));

alter table public.transactions
  add column if not exists is_transfer boolean not null default false;

create index if not exists tx_not_transfer_idx
  on public.transactions (household_id, occurred_on desc)
  where is_transfer = false;

create table if not exists public.goals(
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  title         text not null,
  target_agorot bigint not null check (target_agorot > 0),
  saved_agorot  bigint not null default 0 check (saved_agorot >= 0),
  target_date   date,
  icon          text,
  archived      boolean not null default false,
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint goals_title_len check (length(btrim(title)) between 1 and 60),
  constraint goals_date_sane check (target_date is null or target_date >= date '2020-01-01')
);

create index if not exists goals_hh_idx on public.goals (household_id, archived, created_at);

alter table public.goals enable row level security;
drop policy if exists goal_rw on public.goals;
create policy goal_rw on public.goals for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.goals from anon;
grant select, insert, update, delete on table public.goals to authenticated;

alter table public.households
  add column if not exists cycle_start smallint not null default 1;

alter table public.households
  drop constraint if exists households_cycle_start_range;
alter table public.households
  add constraint households_cycle_start_range
  check (cycle_start between 1 and 28);

create table if not exists public.assets(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,

  kind text not null check (kind in (
    'bank_savings',  -- חיסכון בבנק
    'deposit',       -- פיקדון
    'cash',          -- מזומן
    'portfolio',     -- תיק השקעות
    'crypto',        -- קריפטו
    'mutual_fund',   -- קרן נאמנות
    'study_fund',    -- קרן השתלמות
    'provident',     -- קופת גמל
    'pension',       -- פנסיה
    'realestate',    -- נדל"ן
    'other'
  )),

  name text not null,

  amount_agorot bigint not null default 0 check (amount_agorot >= 0),

  liability_agorot bigint not null default 0 check (liability_agorot >= 0),

  note text,
  archived boolean not null default false,

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint assets_name_len check (length(btrim(name)) between 1 and 60),
  constraint assets_note_len check (note is null or length(note) <= 300),
  constraint assets_liability_where_asked check (
    liability_agorot = 0 or kind in ('realestate','other')
  )
);

create index if not exists assets_hh_idx on public.assets (household_id, archived, kind);

alter table public.assets enable row level security;
drop policy if exists asset_rw on public.assets;
create policy asset_rw on public.assets for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.assets from anon;
grant select, insert, update, delete on table public.assets to authenticated;

create or replace function public.wa_click(
  p_page         text    default 'landing',
  p_token        uuid    default null,
  p_name         text    default null,
  p_phone        text    default null,
  p_consent      boolean default false,
  p_consent_text text    default null,
  p_page_lang    text    default 'he'
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_lead  public.leads%rowtype;
  v_fresh integer;
  v_hour  integer;
  v_name  text := left(btrim(coalesce(p_name,'')), 80);
  v_page  text := case when p_page in ('landing','quiz','app') then p_page else 'landing' end;
begin
  select count(*) into v_hour from public.wa_clicks
   where created_at > now() - interval '1 hour';
  if v_hour >= 200 then
    return jsonb_build_object('ok', false, 'reason', 'busy');
  end if;

  if p_token is not null then
    select * into v_lead from public.leads where quiz_token = p_token;
  end if;

  if v_lead.id is null and length(norm_phone(p_phone)) = 9 then
    select * into v_lead from public.leads
     where norm_phone(phone) = norm_phone(p_phone)
     order by created_at desc limit 1;
  end if;

  if v_lead.id is null and v_name <> '' and length(norm_phone(p_phone)) = 9 then
    select count(*) into v_fresh from public.leads
     where created_at > now() - interval '1 hour';
    if v_fresh < 40 then
      insert into public.leads (name, phone, consent, consent_text, consent_at, page_lang)
      values (v_name, btrim(p_phone), p_consent, p_consent_text,
              case when p_consent then now() end, coalesce(p_page_lang,'he'))
      returning * into v_lead;

      if exists (
        select 1 from pg_attribute
         where attrelid = 'public.leads'::regclass
           and attname = 'source' and attnum > 0 and not attisdropped
      ) then
        execute 'update public.leads set source = coalesce(source, ''whatsapp'') where id = $1'
          using v_lead.id;
      end if;
    end if;
  end if;

  insert into public.wa_clicks (lead_id, page) values (v_lead.id, v_page);
  return jsonb_build_object('ok', true, 'identified', v_lead.id is not null);
end $$;

revoke all on function public.wa_click(text,uuid,text,text,boolean,text,text) from public;
grant execute on function public.wa_click(text,uuid,text,text,boolean,text,text) to anon, authenticated;

drop policy if exists hm_self       on public.household_members;
drop policy if exists hm_read       on public.household_members;
drop policy if exists hm_read_self  on public.household_members;
drop policy if exists hm_read_house on public.household_members;
drop policy if exists hm_leave      on public.household_members;

create policy hm_read_self on public.household_members for select to authenticated
  using (user_id = auth.uid());

create policy hm_read_house on public.household_members for select to authenticated
  using (public.is_member(household_id));

create policy hm_leave on public.household_members for delete to authenticated
  using (user_id = auth.uid() and role <> 'owner');

revoke insert, update on table public.household_members from authenticated;

drop policy if exists hh_rw     on public.households;
drop policy if exists hh_read   on public.households;
drop policy if exists hh_update on public.households;
drop policy if exists hh_delete on public.households;

create policy hh_read on public.households for select to authenticated
  using (public.is_member(id));

create policy hh_update on public.households for update to authenticated
  using (public.is_member(id)) with check (public.is_member(id));

create policy hh_delete on public.households for delete to authenticated
  using (exists (select 1 from public.household_members m
                  where m.household_id = households.id
                    and m.user_id = auth.uid()
                    and m.role = 'owner'));

revoke insert on table public.households from authenticated;
