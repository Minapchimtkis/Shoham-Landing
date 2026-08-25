-- Marks the leads the quiz creates, so the dashboard can show which door
-- someone came through instead of calling every quiz lead "ישיר".
--
-- Optional: everything works without it, those leads simply carry no source.
-- Run in the Supabase SQL editor, after the quiz_results migration.

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

  if v_lead.id is null then
    if coalesce(trim(p_name),'') = '' or length(norm_phone(p_phone)) <> 9 then
      return jsonb_build_object('ok', false, 'reason', 'not_identified');
    end if;
    insert into public.leads (name, phone, message, consent, consent_text, consent_at, page_lang)
    values (trim(p_name), trim(p_phone), p_message, p_consent, p_consent_text,
            case when p_consent then now() end, coalesce(p_page_lang,'he'))
    returning * into v_lead;

    -- Only for a lead this function created, and only if the column is there.
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
  values (v_lead.id, p_quiz_type, p_quiz_score, coalesce(p_quiz_answers,'[]'::jsonb));

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.quiz_submit(text,integer,jsonb,uuid,text,text,text,boolean,text,text) from public;
grant execute on function public.quiz_submit(text,integer,jsonb,uuid,text,text,text,boolean,text,text) to anon, authenticated;

notify pgrst, 'reload schema';
