-- Guards for quiz_submit, which is the one function a public page can call.
--
-- The landing form is protected by Turnstile; the quiz is not, and it can
-- create leads. Nothing here is a substitute for a challenge — a determined
-- attacker with a fresh phone number each time still gets through — but it
-- stops the cheap cases: a script replaying the same submission, a bot
-- posting rubbish, and a flood large enough to bury the real leads.
--
-- Supersedes the earlier definitions. Run in the Supabase SQL editor.

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
declare
  v_lead   public.leads%rowtype;
  v_recent integer;
  v_fresh  integer;
  v_name   text := left(btrim(coalesce(p_name,'')), 80);
  v_type   text := left(btrim(coalesce(p_quiz_type,'')), 40);
begin
  if v_type = '' then
    return jsonb_build_object('ok', false, 'reason', 'missing_quiz_type');
  end if;

  -- A real set of answers is a short list of short strings.
  if p_quiz_answers is not null and (
       jsonb_typeof(p_quiz_answers) <> 'array'
       or jsonb_array_length(p_quiz_answers) > 40
       or octet_length(p_quiz_answers::text) > 20000) then
    return jsonb_build_object('ok', false, 'reason', 'bad_answers');
  end if;

  if p_token is not null then
    select * into v_lead from public.leads where quiz_token = p_token;
  end if;

  if v_lead.id is null and length(norm_phone(p_phone)) = 9 then
    select * into v_lead from public.leads
     where norm_phone(phone) = norm_phone(p_phone)
     order by created_at desc limit 1;
  end if;

  -- Someone answering honestly fills this in once or twice, not six times an
  -- hour. This is what stops a replayed submission piling up on one person.
  if v_lead.id is not null then
    select count(*) into v_recent from public.quiz_results
     where lead_id = v_lead.id and created_at > now() - interval '1 hour';
    if v_recent >= 6 then
      return jsonb_build_object('ok', false, 'reason', 'too_many_attempts');
    end if;
  end if;

  if v_lead.id is null then
    if v_name = '' or length(norm_phone(p_phone)) <> 9 then
      return jsonb_build_object('ok', false, 'reason', 'not_identified');
    end if;

    -- A ceiling far above any real hour, so a flood cannot bury the list.
    -- Results still attach to leads that already exist while it holds.
    select count(*) into v_fresh from public.leads
     where created_at > now() - interval '1 hour';
    if v_fresh >= 40 then
      return jsonb_build_object('ok', false, 'reason', 'busy');
    end if;

    insert into public.leads (name, phone, message, consent, consent_text, consent_at, page_lang)
    values (v_name, btrim(p_phone), left(coalesce(p_message,''), 4000), p_consent, p_consent_text,
            case when p_consent then now() end, coalesce(p_page_lang,'he'))
    returning * into v_lead;

    if exists (
      select 1 from pg_attribute
       where attrelid = 'public.leads'::regclass
         and attname = 'source' and attnum > 0 and not attisdropped
    ) then
      execute 'update public.leads set source = coalesce(source, ''quiz'') where id = $1'
        using v_lead.id;
    end if;
  end if;

  insert into public.quiz_results (lead_id, quiz_type, quiz_score, quiz_answers)
  values (v_lead.id, v_type, p_quiz_score, coalesce(p_quiz_answers, '[]'::jsonb));

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.quiz_submit(text,integer,jsonb,uuid,text,text,text,boolean,text,text) from public;
grant execute on function public.quiz_submit(text,integer,jsonb,uuid,text,text,text,boolean,text,text) to anon, authenticated;

notify pgrst, 'reload schema';
