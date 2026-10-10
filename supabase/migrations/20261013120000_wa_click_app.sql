-- ═══════════════════════════════════════════════════════════════
--  קליק וואטסאפ מתוך האפליקציה
-- ═══════════════════════════════════════════════════════════════
--
-- הפונקציה קיבלה עד היום 'landing' או 'quiz', וכל ערך אחר נדחס
-- ל-'landing'. כלומר קליק מתוך האפליקציה היה נרשם כאילו הגיע מדף
-- נחיתה, ומזהם מקור שכבר נמדד.
--
-- שינוי של שורה אחת: 'app' מצטרף לרשימה. שאר הגוף זהה לקובץ
-- 20260825180000, כולל תקרת 200 הקליקים לשעה ויצירת הליד.
--
-- לתשומת לבך: לוח הבקרה סופר היום את wa_clicks בלי להפריד לפי
-- page, ולכן הקליקים מהאפליקציה ייספרו יחד עם אלה מהדף. הנתון
-- עצמו מופרד ושמור, וכשנרצה אפשר לפצל את התצוגה.
--
-- להרצה בעורך ה-SQL של Supabase. הרצה חוזרת אינה מזיקה.

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
  -- כאן, ורק כאן, השינוי.
  v_page  text := case when p_page in ('landing','quiz','app') then p_page else 'landing' end;
begin
  -- A ceiling on the table itself, so a script cannot fill it with clicks.
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

  -- Details were given and this is someone new: a real lead, like the form.
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
