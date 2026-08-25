-- Quiz results, and the join back to the lead who answered.
--
-- quiz.html is a public page: anyone can take the short quiz and leave their
-- details, and whoever leaves details is then offered the deeper assessment.
-- So the page cannot hold any privileged key — it calls quiz_submit() below,
-- which is SECURITY DEFINER and is the only thing that touches the tables.
-- The leads table itself stays unreadable to anonymous visitors.
--
-- Run once in the Supabase SQL editor. Re-running is harmless.

-- ── phone matching ────────────────────────────────────────────────────
-- 0501234567 and +972501234567 are the same person. Comparing the last 9
-- digits makes both forms match without rewriting what anyone typed.
create or replace function public.norm_phone(p text)
returns text language sql immutable as $$
  select right(regexp_replace(coalesce(p,''), '\D', '', 'g'), 9)
$$;

create index if not exists leads_norm_phone_idx on public.leads (public.norm_phone(phone));

-- ── a stable per-lead link ────────────────────────────────────────────
-- Lets the dashboard hand someone a personal assessment link before a call,
-- so they arrive identified without typing their phone again.
alter table public.leads add column if not exists quiz_token uuid default gen_random_uuid();
update public.leads set quiz_token = gen_random_uuid() where quiz_token is null;
create unique index if not exists leads_quiz_token_idx on public.leads (quiz_token);

-- ── results ───────────────────────────────────────────────────────────
-- lead_id is declared with whatever type leads.id actually has, so this runs
-- correctly whether the table uses uuid or bigint keys.
do $$
declare id_type text;
begin
  select format_type(a.atttypid, a.atttypmod) into id_type
    from pg_attribute a
   where a.attrelid = 'public.leads'::regclass and a.attname = 'id' and a.attnum > 0;

  execute format($f$
    create table if not exists public.quiz_results(
      id           uuid primary key default gen_random_uuid(),
      lead_id      %s references public.leads(id) on delete cascade,
      quiz_type    text        not null,
      quiz_score   integer,
      quiz_answers jsonb       not null default '[]'::jsonb,
      created_at   timestamptz not null default now()
    )$f$, id_type);
end $$;

create index if not exists quiz_results_lead_idx    on public.quiz_results (lead_id);
create index if not exists quiz_results_created_idx on public.quiz_results (created_at desc);

alter table public.quiz_results enable row level security;

-- Only the signed-in dashboard reads or deletes results. Anonymous visitors
-- get no direct access at all; their only route in is quiz_submit().
drop policy if exists quiz_results_read   on public.quiz_results;
drop policy if exists quiz_results_delete on public.quiz_results;
create policy quiz_results_read   on public.quiz_results for select to authenticated using (true);
create policy quiz_results_delete on public.quiz_results for delete to authenticated using (true);

-- Supabase grants anon table privileges on new public tables by default, and
-- RLS alone would then be the only thing standing between a visitor and every
-- result. Say it outright instead of relying on that.
revoke all on table public.quiz_results from anon;
grant select, delete on table public.quiz_results to authenticated;

-- ── the one entry point for the public page ───────────────────────────
-- Resolves the answering lead — by personal token, else by phone, else by
-- creating one — and files the result against it. Returns only a flag, so a
-- caller cannot use it to read anything back out of the leads table.
create or replace function public.quiz_submit(
  p_quiz_type    text,
  p_quiz_score   integer,
  p_quiz_answers jsonb,
  p_token        uuid    default null,
  p_name         text    default null,
  p_phone        text    default null,
  p_message      text    default null,
  p_consent      boolean default false,
  p_consent_text text    default null,
  p_page_lang    text    default 'he'
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_lead public.leads%rowtype;
begin
  if coalesce(trim(p_quiz_type),'') = '' then
    return jsonb_build_object('ok', false, 'reason', 'missing_quiz_type');
  end if;

  if p_token is not null then
    select * into v_lead from public.leads where quiz_token = p_token;
  end if;

  if v_lead.id is null and length(norm_phone(p_phone)) = 9 then
    select * into v_lead from public.leads
     where norm_phone(phone) = norm_phone(p_phone)
     order by created_at desc limit 1;
  end if;

  -- Someone taking the short quiz cold is a new lead; the answers become the
  -- message so the dashboard shows why they got in touch.
  if v_lead.id is null then
    if coalesce(trim(p_name),'') = '' or length(norm_phone(p_phone)) <> 9 then
      return jsonb_build_object('ok', false, 'reason', 'not_identified');
    end if;
    insert into public.leads (name, phone, message, consent, consent_text, consent_at, page_lang)
    values (trim(p_name), trim(p_phone), p_message, p_consent, p_consent_text,
            case when p_consent then now() end, coalesce(p_page_lang,'he'))
    returning * into v_lead;
  end if;

  insert into public.quiz_results (lead_id, quiz_type, quiz_score, quiz_answers)
  values (v_lead.id, p_quiz_type, p_quiz_score, coalesce(p_quiz_answers,'[]'::jsonb));

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.quiz_submit(text,integer,jsonb,uuid,text,text,text,boolean,text,text) from public;
grant execute on function public.quiz_submit(text,integer,jsonb,uuid,text,text,text,boolean,text,text) to anon, authenticated;

-- Confirms a personal link is valid before the assessment is shown, and
-- returns the first name so the page can greet them. Nothing else leaks.
create or replace function public.quiz_identify(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_name text;
begin
  select name into v_name from public.leads where quiz_token = p_token;
  if v_name is null then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'name', v_name);
end $$;

revoke all on function public.quiz_identify(uuid) from public;
grant execute on function public.quiz_identify(uuid) to anon, authenticated;
