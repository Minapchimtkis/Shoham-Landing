-- ─────────────────────────────────────────────────────────────────────────
-- מחשבון הביטחון הכלכלי  ·  /financial-security/
--
-- המחשבון עובד גם בלי המיגרציה הזו: הליד נוצר דרך אותה edge function
-- שדף הנחיתה משתמש בה, וכל התמונה הפיננסית נכנסת לשדה ההודעה כטקסט.
-- מה שהמיגרציה מוסיפה זה שני דברים שאי אפשר לעשות בטקסט חופשי:
--
--   1. עמודת email על leads. עד היום לא הייתה כזו, והמחשבון מבקש אימייל.
--   2. טבלת calc_results עם המספרים כמו שהם, כך שאפשר יהיה לסנן
--      ולחפש לפיהם בלוח הבקרה במקום לקרוא פסקה.
--
-- להריץ ב-SQL editor של Supabase. הרצה חוזרת אינה מזיקה.
-- (הסביבה שבה נכתב הקובץ חוסמת גישה ל-supabase.co, אז אי אפשר
--  להריץ אותו מכאן.)
-- ─────────────────────────────────────────────────────────────────────────

-- ── 1. אימייל על הליד ────────────────────────────────────────────────────
-- בלי ברירת מחדל ובלי not null: ללידים הקיימים אין אימייל, וזו
-- התשובה הנכונה עבורם.
alter table public.leads add column if not exists email text;

create index if not exists leads_email_idx on public.leads (lower(email))
  where email is not null;


-- ── 2. תוצאות המחשבון ────────────────────────────────────────────────────
-- נבנה לפי אותו דפוס של quiz_results: מזהה הליד בטיפוס שלו, מחיקת
-- ליד גוררת את התוצאות איתה, והכל מוגן ב-RLS.
do $$
declare id_type text;
begin
  select format_type(a.atttypid, a.atttypmod) into id_type
    from pg_attribute a
   where a.attrelid = 'public.leads'::regclass
     and a.attname = 'id' and a.attnum > 0 and not a.attisdropped;

  if id_type is null then
    raise exception 'public.leads has no id column';
  end if;

  if to_regclass('public.calc_results') is null then
    execute format($f$
      create table public.calc_results(
        id         uuid primary key default gen_random_uuid(),
        lead_id    %s references public.leads(id) on delete cascade,
        calc_type  text        not null default 'financial_freedom',
        calc_data  jsonb       not null default '{}'::jsonb,
        created_at timestamptz not null default now()
      )
    $f$, id_type);
  end if;
end $$;

create index if not exists calc_results_lead_idx    on public.calc_results (lead_id);
create index if not exists calc_results_created_idx on public.calc_results (created_at desc);

alter table public.calc_results enable row level security;

-- רק משתמש מחובר (שוהם, בלוח הבקרה) קורא. anon לא נוגע בטבלה
-- ישירות — הכתיבה כולה עוברת דרך calc_save שלמטה.
drop policy if exists calc_results_read on public.calc_results;
create policy calc_results_read on public.calc_results
  for select to authenticated using (true);

revoke all on table public.calc_results from anon;
grant select on table public.calc_results to authenticated;


-- ── 3. הכתיבה ────────────────────────────────────────────────────────────
-- אותו רעיון כמו quiz_submit: פונקציה אחת, SECURITY DEFINER, שהיא
-- הדבר היחיד שדף ציבורי יכול לקרוא לו, עם תקרות שמונעות הצפה.
--
-- ברוב המקרים הליד כבר קיים כשמגיעים לכאן: המחשבון שולח קודם
-- ל-submit-lead (שם יושבת בדיקת Turnstile) ורק אחר כך קורא לזה.
-- הענף שיוצר ליד חדש הוא רשת ביטחון, ולכן הוא זה שחייב את התקרה.
create or replace function public.calc_save(
  p_name      text    default null,
  p_phone     text    default null,
  p_email     text    default null,
  p_data      jsonb   default '{}'::jsonb,
  p_calc_type text    default 'financial_freedom',
  p_page_lang text    default 'he'
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_lead   public.leads%rowtype;
  v_recent integer;
  v_fresh  integer;
  v_name   text := left(btrim(coalesce(p_name, '')), 80);
  v_mail   text := left(btrim(coalesce(p_email, '')), 160);
  v_type   text := left(btrim(coalesce(p_calc_type, 'financial_freedom')), 40);
begin
  if length(norm_phone(p_phone)) <> 9 then
    return jsonb_build_object('ok', false, 'reason', 'not_identified');
  end if;

  -- תמונה אמיתית של מחשבון היא אובייקט קטן. כל דבר מעבר לזה הוא לא זה.
  if p_data is null
     or jsonb_typeof(p_data) <> 'object'
     or octet_length(p_data::text) > 20000 then
    return jsonb_build_object('ok', false, 'reason', 'bad_data');
  end if;

  if v_mail <> '' and v_mail !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' then
    v_mail := '';
  end if;

  select * into v_lead
    from public.leads
   where norm_phone(phone) = norm_phone(p_phone)
   order by created_at desc
   limit 1;

  -- מי שממלא באמת עושה את זה פעם או פעמיים, לא שמונה פעמים בשעה.
  if v_lead.id is not null then
    select count(*) into v_recent
      from public.calc_results
     where lead_id = v_lead.id
       and created_at > now() - interval '1 hour';
    if v_recent >= 8 then
      return jsonb_build_object('ok', false, 'reason', 'too_many_attempts');
    end if;
  else
    if v_name = '' then
      return jsonb_build_object('ok', false, 'reason', 'not_identified');
    end if;

    select count(*) into v_fresh
      from public.leads
     where created_at > now() - interval '1 hour';
    if v_fresh >= 40 then
      return jsonb_build_object('ok', false, 'reason', 'rate_limited');
    end if;

    insert into public.leads (name, phone, consent, consent_at, page_lang)
    values (v_name, btrim(p_phone), true, now(), coalesce(p_page_lang, 'he'))
    returning * into v_lead;

    if exists (
      select 1 from pg_attribute
       where attrelid = 'public.leads'::regclass
         and attname = 'source' and attnum > 0 and not attisdropped
    ) then
      execute 'update public.leads set source = coalesce(source, ''calculator'') where id = $1'
        using v_lead.id;
    end if;
  end if;

  -- האימייל נרשם רק אם אין כבר אחד. פנייה חדשה לא דורסת כתובת
  -- ששוהם כבר תיקן ביד בלוח הבקרה.
  if v_mail <> '' then
    update public.leads
       set email = v_mail
     where id = v_lead.id
       and coalesce(btrim(email), '') = '';
  end if;

  -- ליד שנוצר דרך submit-lead מגיע לכאן בלי source. השורה הזו היא
  -- מה שגורם לו להופיע בלוח הבקרה כליד של המחשבון ולא כ״ישיר״.
  if exists (
    select 1 from pg_attribute
     where attrelid = 'public.leads'::regclass
       and attname = 'source' and attnum > 0 and not attisdropped
  ) then
    execute 'update public.leads set source = coalesce(source, ''calculator'') where id = $1'
      using v_lead.id;
  end if;

  insert into public.calc_results (lead_id, calc_type, calc_data)
  values (v_lead.id, v_type, p_data);

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.calc_save(text,text,text,jsonb,text,text) from public;
grant execute on function public.calc_save(text,text,text,jsonb,text,text) to anon, authenticated;

notify pgrst, 'reload schema';

-- מה לבדוק אחרי ההרצה:
--   select count(*) from public.calc_results;
--   select coalesce(source,'(ריק)') as source, count(*)
--     from public.leads group by 1 order by 2 desc;
