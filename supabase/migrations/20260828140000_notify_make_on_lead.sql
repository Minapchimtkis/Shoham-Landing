-- Send the email for every lead, not one route in five.
--
-- Until now the browser posted to the Make webhook, and only from one place:
-- the first form in the short questionnaire. Someone arriving through the
-- landing form, the WhatsApp button, the deep questionnaire, or the short one
-- when we already knew them, was saved here and never produced an email.
--
-- The database sends it instead. Every way in ends with a row in leads or in
-- quiz_results, so a trigger on those two covers all of them, and the webhook
-- address stops being readable in the page.
--
-- The JSON is deliberately shaped like the one the browser used to send, so
-- the existing Make scenario keeps working untouched. Two honest differences:
--   * quiz_score is now the 0-100 reading. The browser used to send the raw
--     weighted total here and the 0-100 beside it; only the 0-100 is stored.
--   * a lead with no questionnaire sends quiz_type, quiz_score and
--     quiz_answers as null, so the scenario has to tolerate empty ones.
-- A "route" field is added saying how the person arrived.
--
-- Run in the Supabase SQL editor. Re-running is harmless.
-- Nothing happens until the webhook address is stored — the last step below.

create extension if not exists pg_net with schema extensions;

-- The address lives here rather than in the page. Nothing is granted to anon
-- or to authenticated, so no one holding the publishable key can read it.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.app_config(
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);
revoke all on table private.app_config from public, anon, authenticated;

-- ---------------------------------------------------------------- payload --
-- One shape, built in one place, whichever trigger is asking.
create or replace function private.make_payload(
  p_lead   public.leads,
  p_result public.quiz_results,
  p_route  text
) returns jsonb
language sql stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'name',        p_lead.name,
    'phone',       p_lead.phone,
    'message',     p_lead.message,
    'consent',     coalesce(p_lead.consent, false),
    'consentText', p_lead.consent_text,
    'consentAt',   p_lead.consent_at,
    'pageLang',    coalesce(p_lead.page_lang, 'he'),
    'source',      coalesce(p_lead.source, 'direct'),
    'route',       p_route,
    'lead_id',     p_lead.id,
    'created_at',  p_lead.created_at,
    'quiz_type',     p_result.quiz_type,
    'quiz_score',    p_result.quiz_score,
    'quiz_score_100',p_result.quiz_score,
    'quiz_answers',  p_result.quiz_answers
  )
$$;

create or replace function private.make_send(p_body jsonb)
returns void
language plpgsql
security definer
set search_path = private, extensions, public, pg_temp
as $$
declare v_url text;
begin
  select value into v_url from private.app_config where key = 'make_webhook_url';
  if coalesce(btrim(v_url), '') = '' then return; end if;
  perform net.http_post(
    url     := v_url,
    body    := p_body,
    headers := jsonb_build_object('Content-Type', 'application/json')
  );
end $$;

-- ------------------------------------------------------------- new person --
-- Deferred to the end of the transaction on purpose: quiz_submit writes the
-- lead first and the answers second, and this way the email carries both.
create or replace function private.notify_make_lead()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_lead   public.leads%rowtype;
  v_result public.quiz_results%rowtype;
  v_route  text := 'new';
begin
  select * into v_lead from public.leads where id = new.id;

  -- The row can be gone by now: a second entry for a phone we already hold is
  -- merged into the original and deleted. That person is still worth an email,
  -- so send it against the record that survived.
  if v_lead.id is null then
    v_route := 'existing';
    select * into v_lead from public.leads
     where norm_phone(phone) = norm_phone(new.phone)
     order by created_at asc limit 1;
    if v_lead.id is null then return null; end if;
  end if;

  select * into v_result from public.quiz_results
   where lead_id = v_lead.id order by created_at desc limit 1;

  perform private.make_send(private.make_payload(v_lead, v_result, v_route));
  return null;
exception when others then
  -- Telling him about a lead must never be able to cost him the lead.
  raise warning 'notify_make_lead: %', sqlerrm;
  return null;
end $$;

-- ------------------------------------------- questionnaire, person we know --
create or replace function private.notify_make_quiz()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_lead public.leads%rowtype;
  v_same boolean;
begin
  if new.lead_id is null then return null; end if;
  select * into v_lead from public.leads where id = new.lead_id;
  if v_lead.id is null then return null; end if;
  select (l.xmin = pg_current_xact_id()::xid) into v_same
    from public.leads l where l.id = new.lead_id;
  -- Written moments ago in this same transaction, so the lead trigger is
  -- already going to send this and one email is enough.
  if v_same then return null; end if;

  perform private.make_send(private.make_payload(v_lead, new, 'questionnaire'));
  return null;
exception when others then
  raise warning 'notify_make_quiz: %', sqlerrm;
  return null;
end $$;

drop trigger if exists leads_notify_make on public.leads;
create constraint trigger leads_notify_make
  after insert on public.leads
  deferrable initially deferred
  for each row execute function private.notify_make_lead();

drop trigger if exists quiz_results_notify_make on public.quiz_results;
create trigger quiz_results_notify_make
  after insert on public.quiz_results
  for each row execute function private.notify_make_quiz();

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- the URL --
-- Last step, and the only one to edit. Create a NEW webhook in Make and put
-- its address here: the old one has been readable in the page and cannot be
-- made private again. Until this runs, no email is sent by the database.
--
--   insert into private.app_config(key, value)
--   values ('make_webhook_url', 'https://hook.eu1.make.com/PUT-THE-NEW-ONE-HERE')
--   on conflict (key) do update set value = excluded.value, updated_at = now();
