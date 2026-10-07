-- ‏ניקוי חשבונות אורח נטושים
-- ‏להרצה בעורך ה-SQL של Supabase. הרצה חוזרת אינה מזיקה.
--
-- ‏הכניסה בלי חשבון פתוחה לכל מי שמחזיק את המפתח הפומבי, ולכן
-- ‏אפשר לייצר דרכה חשבונות ריקים גם בלי לעבור באף דף שלנו. הם
-- ‏אינם מסוכנים · אבטחת השורות נותנת להם אפס שורות מהלידים,
-- ‏מהשאלון ומהמחשבון · אבל הם מנפחים את מספר המשתמשים ומשאירים
-- ‏שורות ריקות. הפונקציה הזאת מוחקת אותם.
--
-- ‏מה שהיא לא עושה, וזה העיקר: היא לא נוגעת באורח שיש לו משהו.
-- ‏תנועה אחת, מסמך אחד, נכס אחד או מטרה אחת · והחשבון נשאר, בלי
-- ‏קשר לכמה זמן עבר. אדם שניהל תקציב חודשיים ועזב לחופשה חוזר
-- ‏ומוצא את הנתונים שלו.

create or replace function public.sweep_anon(p_days integer default 14)
returns table(users_removed integer, households_removed integer)
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_cut   timestamptz := now() - make_interval(days => greatest(coalesce(p_days, 14), 1));
  v_users integer := 0;
  v_hh    integer := 0;
begin
  -- ‏האורחים הנטושים: אנונימיים, שלא נכנסו מאז הסף, ושבאף משק בית
  -- ‏שהם חברים בו אין שום דבר שאדם יצר. תקציב לבדו אינו נחשב ·
  -- ‏אותו ההקמה כותבת לבד, ולכן הוא אינו סימן שמישהו היה כאן.
  with doomed as (
    select u.id
      from auth.users u
     where u.is_anonymous
       and coalesce(u.last_sign_in_at, u.created_at) < v_cut
       and not exists (
         select 1
           from public.household_members m
          where m.user_id = u.id
            and (
              exists (select 1 from public.transactions t where t.household_id = m.household_id) or
              exists (select 1 from public.documents    d where d.household_id = m.household_id) or
              exists (select 1 from public.assets       a where a.household_id = m.household_id) or
              exists (select 1 from public.goals        g where g.household_id = m.household_id)
            )
       )
  )
  delete from auth.users u using doomed d where u.id = d.id;
  get diagnostics v_users = row_count;

  -- ‏מחיקת המשתמש גוררת את שורת החברות שלו, אבל לא את משק הבית ·
  -- ‏למשק בית אין הפניה למשתמש. מה שנשאר בלי אף חבר הוא יתום, והוא
  -- ‏גורר בשרשרת את התקציב ואת כל השאר.
  delete from public.households h
   where not exists (select 1 from public.household_members m where m.household_id = h.id);
  get diagnostics v_hh = row_count;

  return query select v_users, v_hh;
end $$;

-- ‏אין לאיש הרשאה לקרוא לה דרך ה-API. היא רצה מעורך ה-SQL או
-- ‏מהמתזמן, ושניהם רצים כבעלים.
revoke all on function public.sweep_anon(integer) from public, anon, authenticated;

-- ────────────────────────────────── התזמון ──
-- ‏אם pg_cron מותקן בפרויקט · הרצה אוטומטית כל יום בשלוש לפנות
-- ‏בוקר. אם לא · הבלוק הזה מדלג בשקט, והפונקציה עדיין עובדת
-- ‏ידנית. אין טעם להפיל מיגרציה שלמה בגלל תוסף חסר.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('sweep_anon')
      where exists (select 1 from cron.job where jobname = 'sweep_anon');
    perform cron.schedule('sweep_anon', '0 3 * * *', 'select public.sweep_anon(14)');
    raise notice 'הניקוי מתוזמן לכל יום בשלוש לפנות בוקר.';
  else
    raise notice 'pg_cron אינו מותקן. הפונקציה קיימת ואפשר להריץ אותה ידנית: select * from public.sweep_anon(14);';
  end if;
end $$;
