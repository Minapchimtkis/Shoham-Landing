-- ‏להעתיק את כל הקובץ הזה לעורך ה-SQL של Supabase וללחוץ Run.
-- ‏הרצה חוזרת אינה מזיקה. שני הדברים ביחד, בסדר הנכון.
-- ═══════════════════════════════════════════════════════════════
--  1. תצלומי הון עצמי · הקו השני בגרף
--  2. ניקוי חשבונות אורח נטושים
-- ═══════════════════════════════════════════════════════════════
--
-- ‏מה קורה אחרי שתריץ:
--
-- ‏התצלומים · מסך סיכום השנה מתחיל לצבור מדידה אחת לחודש של
-- ההון העצמי שלך. הקו השני בגרף יתחיל להיראות מהחודש השני ·
-- נקודה אחת אינה קו, והאפליקציה אומרת את זה במילים.
--
-- ‏הניקוי · פונקציה שמוחקת חשבונות אורח ריקים ונטושים. היא לא
-- נוגעת באורח שיש לו משהו: תנועה, מסמך, נכס, מטרה, חוב, מחשבה,
-- ייבוא או קטגוריה שהוסיף בעצמו. היא גם לא רצה מעצמה · בסוף
-- הקובץ יש שורה שמראה כמה יימחקו, בלי למחוק, ורק אחריה ההרצה.

-- ═══════════════ 1. תצלומי הון עצמי ═══════════════

-- ‏בלי הטבלה הזאת הגרף במסך סיכום השנה מראה קו אחד בלבד, "מה
-- שנשאר", והאפליקציה ממשיכה לעבוד בדיוק כמו קודם. אחריה מופיע
-- גם הקו השני.
--
-- ‏למה בכלל צריך טבלה: assets מחזיקה את הסכום הנוכחי בלבד,
-- ו-debts את היתרה הנוכחית בלבד. כשאתה מעדכן את הפנסיה
-- מ-200,000 ל-210,000, המספר הקודם נמחק ואין לאן לחזור. לכן
-- אי אפשר לצייר הון עצמי לאחור · הנתון אינו קיים, וציור שלו
-- בכל זאת היה המצאה.
--
-- ‏מכאן והלאה הוא כן קיים. האפליקציה כותבת שורה אחת לחודש בכל
-- פתיחה, כך שהחודש הנוכחי תמיד עדכני והחודשים שעברו קפואים
-- כפי שהיו. הקו יתחיל להיראות מהחודש השני.
--
-- ‏לא נכתב כלום למי שאין לו נכסים ואין לו חובות. אפס כזה אינו
-- "אין לי כלום" אלא "עוד לא הזנתי", וקו שטוח על אפס הוא שקר
-- שקט.

create table if not exists public.net_worth_snapshots(
  household_id uuid not null references public.households(id) on delete cascade,

  -- ‏תמיד ה-1 בחודש, כמו budgets. נקודה אחת לחודש היא הרזולוציה
  -- ‏שאדם באמת מסתכל עליה, ויומית הייתה יוצרת רעש בלי מידע.
  as_of date not null,

  assets_agorot      bigint not null default 0 check (assets_agorot >= 0),
  -- ‏ההתחייבויות שרובצות על נכסים · משכנתא על דירה
  liabilities_agorot bigint not null default 0 check (liabilities_agorot >= 0),
  -- ‏החובות העומדים בפני עצמם · הלוואה, מינוס, אשראי
  debts_agorot       bigint not null default 0 check (debts_agorot >= 0),

  net_agorot bigint generated always as
    (assets_agorot - liabilities_agorot - debts_agorot) stored,

  updated_at timestamptz not null default now(),

  primary key (household_id, as_of),
  constraint nws_first_of_month check (extract(day from as_of) = 1),
  -- ‏תצלום בעתיד אינו תצלום. בלי זה שעון מוטעה בטלפון היה פותח
  -- ‏נקודה בעוד שנה ומותח את כל הגרף.
  constraint nws_not_future check (as_of <= (current_date + interval '1 month'))
);

create index if not exists nws_household_idx
  on public.net_worth_snapshots (household_id, as_of);

alter table public.net_worth_snapshots enable row level security;

drop policy if exists nws_rw on public.net_worth_snapshots;
create policy nws_rw on public.net_worth_snapshots
  for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

-- ‏אבטחת השורות קובעת מי רואה מה, אבל בלי ההרשאה הזאת איש אינו
-- ‏מגיע לטבלה בכלל דרך ה-API. שאר הטבלאות באפליקציה מעניקות
-- ‏אותה במפורש, וגם זאת.
grant select, insert, update, delete on table public.net_worth_snapshots to authenticated;


-- ═══════════════ 2. ניקוי חשבונות אורח ═══════════════

-- ‏הכניסה בלי חשבון פתוחה לכל מי שמחזיק את המפתח הפומבי. זה נכון
-- וכך זה צריך להיות · אבל זה אומר שאפשר לייצר חשבונות ריקים גם
-- בלי לעבור באף דף שלנו. הם אינם מסוכנים · אבטחת השורות נותנת
-- להם אפס שורות מהלידים, מהשאלון ומהמחשבון · אבל הם מנפחים את
-- מספר המשתמשים ומשאירים שורות ריקות בבסיס הנתונים.
--
-- ‏הפונקציה הזאת מוחקת אותם. מה שהיא לא עושה, וזה העיקר: היא לא
-- נוגעת באורח שיש לו משהו. תנועה אחת, מסמך אחד, נכס אחד, מטרה
-- אחת, חוב אחד, מחשבה אחת, ייבוא אחד או קטגוריה שהוא הוסיף
-- בעצמו · והחשבון נשאר, בלי קשר לכמה זמן עבר. אדם שניהל תקציב
-- חודשיים ועזב לחופשה ארוכה חוזר ומוצא את הנתונים שלו.
--
-- ‏תקציב לבדו אינו נחשב, ובכוונה: את התקציב ההקמה כותבת בעצמה
-- ברגע הכניסה, ולכן הוא אינו סימן שאדם היה כאן.
--
-- ‏אם pg_cron מותקן בפרויקט, הקובץ גם מתזמן את זה לכל יום בשלוש
-- לפנות בוקר. אם לא · הוא מדלג בשקט ואומר לך, והפונקציה עדיין
-- עובדת ידנית בכל רגע.


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
              exists (select 1 from public.goals        g where g.household_id = m.household_id) or
              exists (select 1 from public.debts        b where b.household_id = m.household_id) or
              exists (select 1 from public.reflections  r where r.household_id = m.household_id) or
              exists (select 1 from public.imports      i where i.household_id = m.household_id) or
              -- ‏קטגוריה שהמשתמש הוסיף בעצמו. קטגוריות המערכת יושבות
              -- ‏בלי משק בית, ולכן אינן נספרות כאן.
              exists (select 1 from public.categories   c where c.household_id = m.household_id)
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

-- ═══════════════════════════════════════════════════════════════
--  בדיקה · שש שורות של "תקין"
-- ═══════════════════════════════════════════════════════════════
select 'טבלת התצלומים' as "מה", 
       case when to_regclass('public.net_worth_snapshots') is not null
            then 'תקין' else 'חסרה' end as "מצב"
union all
select 'אבטחת שורות לתצלומים',
       case when (select relrowsecurity from pg_class
                   where oid = 'public.net_worth_snapshots'::regclass)
            then 'תקין' else 'כבויה · סכנה' end
union all
select 'הרשאה למשתמשים מחוברים',
       case when has_table_privilege('authenticated','public.net_worth_snapshots','select')
             and has_table_privilege('authenticated','public.net_worth_snapshots','insert')
            then 'תקין' else 'חסרה · הטבלה לא תעבוד' end
union all
select 'ההון העצמי מחושב ולא נשמר',
       case when exists (select 1 from pg_attribute
                          where attrelid = 'public.net_worth_snapshots'::regclass
                            and attname = 'net_agorot' and attgenerated = 's')
            then 'תקין' else 'חסר' end
union all
select 'פונקציית הניקוי',
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                          where n.nspname='public' and p.proname='sweep_anon')
            then 'תקין' else 'חסרה' end
union all
select 'והיא סגורה ל-API',
       case when not has_function_privilege('anon','public.sweep_anon(integer)','execute')
             and not has_function_privilege('authenticated','public.sweep_anon(integer)','execute')
            then 'תקין' else 'פתוחה · סכנה' end;


-- ═══════════════════════════════════════════════════════════════
--  כמה יימחקו · מספר בלבד, בלי למחוק כלום
-- ═══════════════════════════════════════════════════════════════
-- ‏התנאי כאן הוא העתק של התנאי שבתוך הפונקציה, ושניהם צריכים
-- ‏להשתנות יחד.
select count(*) as "אורחים נטושים שיימחקו"
  from auth.users u
 where u.is_anonymous
   and coalesce(u.last_sign_in_at, u.created_at) < now() - interval '14 days'
   and not exists (
     select 1 from public.household_members m
      where m.user_id = u.id
        and (
          exists (select 1 from public.transactions t where t.household_id = m.household_id) or
          exists (select 1 from public.documents    d where d.household_id = m.household_id) or
          exists (select 1 from public.assets       a where a.household_id = m.household_id) or
          exists (select 1 from public.goals        g where g.household_id = m.household_id) or
          exists (select 1 from public.debts        b where b.household_id = m.household_id) or
          exists (select 1 from public.reflections  r where r.household_id = m.household_id) or
          exists (select 1 from public.imports      i where i.household_id = m.household_id) or
          exists (select 1 from public.categories   c where c.household_id = m.household_id)
        )
   );


-- ═══════════════════════════════════════════════════════════════
--  וזאת המחיקה עצמה
-- ═══════════════════════════════════════════════════════════════
-- ‏אם המספר למעלה נראה לך גדול מדי · אל תריץ את השורה הזאת,
-- ‏ותגיד לי. אפשר להעלות את הסף מ-14 יום ל-30 או ל-60.
select * from public.sweep_anon(14);
