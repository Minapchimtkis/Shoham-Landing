-- Intake questionnaires: the discovery form people fill in before the first
-- mapping meeting. Two kinds, individual and couple.
--
-- intake.html is a public page, exactly like quiz.html, so it holds no
-- privileged key. Every write goes through intake_submit() below, which is
-- SECURITY DEFINER and is the only thing that touches the table. Anonymous
-- visitors get no direct read, insert, update or delete at all: a submitted
-- questionnaire is somebody's financial life, and the page that collects it
-- must not be able to read back anyone else's.
--
-- Run once in the Supabase SQL editor. Re-running is harmless.

-- ── the answers table ─────────────────────────────────────────────────
-- lead_id uses whatever type leads.id actually has, uuid or bigint alike,
-- and is nullable: a questionnaire is worth keeping even if the lead it was
-- attached to is later deleted, so the link drops rather than the answers.
--
-- answers is self-describing on purpose. It carries the question text next
-- to each answer instead of only an id, so a submission read six months from
-- now still says what was actually asked. Keying by id alone would mean that
-- rewording a question silently rewrites every past answer sheet, and this
-- is a record he reads before sitting down with a person.
do $$
declare id_type text;
begin
  select format_type(a.atttypid, a.atttypmod) into id_type
    from pg_attribute a
   where a.attrelid = 'public.leads'::regclass
     and a.attname = 'id' and a.attnum > 0 and not a.attisdropped;

  if to_regclass('public.intake_submissions') is null then
    execute format($f$
      create table public.intake_submissions(
        id            uuid        primary key default gen_random_uuid(),
        lead_id       %s          references public.leads(id) on delete set null,
        kind          text        not null,
        answers       jsonb       not null default '[]'::jsonb,
        name          text,
        phone         text,
        email         text,
        partner_a     text,
        partner_b     text,
        status        text        not null default 'new',
        notes         text,
        consent       boolean     not null default false,
        consent_text  text,
        consent_at    timestamptz,
        submit_token  uuid,
        started_at    timestamptz,
        created_at    timestamptz not null default now(),
        updated_at    timestamptz not null default now()
      )$f$, id_type);
  else
    execute format('alter table public.intake_submissions add column if not exists lead_id %s', id_type);
    alter table public.intake_submissions add column if not exists kind         text;
    alter table public.intake_submissions add column if not exists answers      jsonb default '[]'::jsonb;
    alter table public.intake_submissions add column if not exists name         text;
    alter table public.intake_submissions add column if not exists phone        text;
    alter table public.intake_submissions add column if not exists email        text;
    alter table public.intake_submissions add column if not exists partner_a    text;
    alter table public.intake_submissions add column if not exists partner_b    text;
    alter table public.intake_submissions add column if not exists status       text default 'new';
    alter table public.intake_submissions add column if not exists notes        text;
    alter table public.intake_submissions add column if not exists consent      boolean default false;
    alter table public.intake_submissions add column if not exists consent_text text;
    alter table public.intake_submissions add column if not exists consent_at   timestamptz;
    alter table public.intake_submissions add column if not exists submit_token uuid;
    alter table public.intake_submissions add column if not exists started_at   timestamptz;
    alter table public.intake_submissions add column if not exists created_at   timestamptz default now();
    alter table public.intake_submissions add column if not exists updated_at   timestamptz default now();
  end if;
end $$;

-- Only the two kinds the page can produce, and only the four states the
-- dashboard offers. A check here is what makes the dashboard's dropdown the
-- real set rather than a suggestion.
alter table public.intake_submissions drop constraint if exists intake_kind_ck;
alter table public.intake_submissions
  add constraint intake_kind_ck check (kind in ('individual','couple'));

alter table public.intake_submissions drop constraint if exists intake_status_ck;
alter table public.intake_submissions
  add constraint intake_status_ck check (status in ('new','meeting_set','met','in_progress'));

-- The same submission replayed by a flaky connection, a double tap or a
-- refresh must land once. The page mints one token per filled questionnaire
-- and sends it with every attempt, so the second attempt collides here
-- instead of creating a twin.
create unique index if not exists intake_submit_token_idx
  on public.intake_submissions (submit_token) where submit_token is not null;

create index if not exists intake_created_idx on public.intake_submissions (created_at desc);
create index if not exists intake_lead_idx    on public.intake_submissions (lead_id);
create index if not exists intake_status_idx  on public.intake_submissions (status);
create index if not exists intake_phone_idx   on public.intake_submissions (public.norm_phone(phone));

-- ── who may touch it ──────────────────────────────────────────────────
-- "Signed in" is not a permission in this project. The budget app is open
-- to the world by design, so anyone who signs up there is authenticated in
-- this same Supabase project and holds the publishable key printed in the
-- page source. 20261015120000_lock_business_tables.sql settled the rule for
-- every business table: an explicit staff list, checked by is_staff(). This
-- table is somebody's financial life and answers, so it follows that rule
-- and stops rather than guessing if the list is not there.
do $$
begin
  if to_regclass('public.staff') is null
     or to_regprocedure('public.is_staff()') is null then
    raise exception using message =
      'is_staff() or the staff table is missing. Run ' ||
      '20261015120000_lock_business_tables.sql first, then this file.';
  end if;
  if not exists (select 1 from public.staff) then
    raise exception using message =
      'The staff list is empty, so this would lock you out of your own ' ||
      'dashboard. Add yourself first: insert into public.staff(user_id) ' ||
      'select id from auth.users where lower(email)=lower(''your email'');';
  end if;
end $$;

alter table public.intake_submissions enable row level security;

-- Every policy, including any written outside this repo, then only
-- staff-gated ones.
do $$
declare p text;
begin
  for p in select policyname from pg_policies
            where schemaname = 'public' and tablename = 'intake_submissions' loop
    execute format('drop policy %I on public.intake_submissions', p);
  end loop;
end $$;

create policy intake_staff_read on public.intake_submissions
  for select to authenticated using (public.is_staff());
create policy intake_staff_update on public.intake_submissions
  for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy intake_staff_delete on public.intake_submissions
  for delete to authenticated using (public.is_staff());

-- Anonymous visitors reach the table through intake_submit() and nowhere
-- else. There is no policy for them, so RLS denies everything by default,
-- and the grants are revoked as well so the denial does not rest on one
-- mechanism alone.
revoke all on public.intake_submissions from anon;

-- The dashboard is signed in, but it still has no business rewriting answers.
-- RLS decides which rows; these grants decide which columns, so even a
-- compromised dashboard script cannot edit what somebody answered. Postgres
-- needs the table-level update grant revoked first for the column list to
-- be the whole of it.
revoke all on public.intake_submissions from authenticated;
grant select, delete on public.intake_submissions to authenticated;
grant update (status, notes, updated_at, lead_id) on public.intake_submissions to authenticated;

-- updated_at should mean the last time anything changed, not the last time
-- the dashboard remembered to say so.
create or replace function public.intake_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists intake_touch_trg on public.intake_submissions;
create trigger intake_touch_trg before update on public.intake_submissions
  for each row execute function public.intake_touch();

-- ── the one door in ───────────────────────────────────────────────────
-- Returns a plain jsonb verdict rather than raising, so the page can tell
-- somebody what to do about it in Hebrew instead of showing a 500.
create or replace function public.intake_submit(
  p_kind         text,
  p_answers      jsonb,
  p_token        uuid    default null,
  p_submit_token uuid    default null,
  p_name         text    default null,
  p_phone        text    default null,
  p_email        text    default null,
  p_partner_a    text    default null,
  p_partner_b    text    default null,
  p_consent      boolean default false,
  p_consent_text text    default null,
  p_started_at   timestamptz default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_lead   public.leads%rowtype;
  v_kind   text := left(btrim(coalesce(p_kind,'')), 20);
  v_name   text := left(btrim(coalesce(p_name,'')), 80);
  v_phone  text := left(btrim(coalesce(p_phone,'')), 40);
  v_email  text := left(btrim(coalesce(p_email,'')), 120);
  v_recent integer;
  v_id     uuid;
begin
  if v_kind not in ('individual','couple') then
    return jsonb_build_object('ok', false, 'reason', 'bad_kind');
  end if;

  -- Consent is the lawful basis for holding any of this. Without it there is
  -- nothing to store, so it is refused here and not only in the page.
  if not coalesce(p_consent, false) then
    return jsonb_build_object('ok', false, 'reason', 'no_consent');
  end if;

  -- A real sheet is a short list of stages, each a short list of answers.
  -- The ceiling is generous enough for the longest questionnaire with every
  -- free-text box filled, and small enough that nobody can park a payload
  -- in the table.
  if p_answers is null
     or jsonb_typeof(p_answers) <> 'array'
     or jsonb_array_length(p_answers) > 12
     or octet_length(p_answers::text) > 60000 then
    return jsonb_build_object('ok', false, 'reason', 'bad_answers');
  end if;

  if v_name = '' or length(norm_phone(v_phone)) <> 9 then
    return jsonb_build_object('ok', false, 'reason', 'not_identified');
  end if;

  -- The same questionnaire arriving twice is the expected case, not an
  -- attack: a tap that looked like it failed, or a refresh on the thank-you
  -- screen. It succeeds quietly so the person is not told off for it.
  if p_submit_token is not null then
    select id into v_id from public.intake_submissions where submit_token = p_submit_token;
    if v_id is not null then
      return jsonb_build_object('ok', true, 'duplicate', true);
    end if;
  end if;

  -- Somebody answering honestly does this once, maybe twice if they changed
  -- their mind. Six in an hour from one number is a script.
  select count(*) into v_recent from public.intake_submissions
   where norm_phone(phone) = norm_phone(v_phone)
     and created_at > now() - interval '1 hour';
  if v_recent >= 6 then
    return jsonb_build_object('ok', false, 'reason', 'too_many_attempts');
  end if;

  -- Attach to the person it belongs to. A personal link is exact; a phone
  -- number is how somebody who opened the page on their own is recognised.
  -- Failing to match is fine, and the questionnaire is kept either way.
  if p_token is not null then
    select * into v_lead from public.leads where quiz_token = p_token;
  end if;

  if v_lead.id is null then
    select * into v_lead from public.leads
     where norm_phone(phone) = norm_phone(v_phone)
     order by created_at desc limit 1;
  end if;

  insert into public.intake_submissions
    (lead_id, kind, answers, name, phone, email, partner_a, partner_b,
     consent, consent_text, consent_at, submit_token, started_at)
  values
    (v_lead.id, v_kind, p_answers, v_name, v_phone, nullif(v_email,''),
     nullif(left(btrim(coalesce(p_partner_a,'')), 80), ''),
     nullif(left(btrim(coalesce(p_partner_b,'')), 80), ''),
     true, left(coalesce(p_consent_text,''), 2000), now(),
     p_submit_token,
     case when p_started_at is not null and p_started_at < now()
            and p_started_at > now() - interval '30 days'
          then p_started_at end)
  on conflict (submit_token) where submit_token is not null do nothing
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.intake_submit(text,jsonb,uuid,uuid,text,text,text,text,text,boolean,text,timestamptz) from public;
grant execute on function public.intake_submit(text,jsonb,uuid,uuid,text,text,text,text,text,boolean,text,timestamptz) to anon, authenticated;

notify pgrst, 'reload schema';
