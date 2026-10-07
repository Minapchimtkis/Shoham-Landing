-- ‏נעילת הטבלאות העסקיות לצוות בלבד
-- ‏להרצה בעורך ה-SQL של Supabase. הרצה חוזרת אינה מזיקה.
--
-- ‏מה היה: כל הטבלאות של דף הנחיתה · לידים, תוצאות שאלון, תוצאות
-- ‏מחשבון, קליקים לוואטסאפ והמשפכים · נפתחו למי שמחובר, בתנאי
-- ‏"using (true)". כשזה נכתב, "מחובר" פירושו היה שוהם ואף אחד אחר,
-- ‏כי לא הייתה שום דרך אחרת לפתוח חשבון בפרויקט הזה.
--
-- ‏אפליקציית "כמה יש לי" שינתה את זה מהיסוד. כל אדם בעולם יכול
-- ‏לפתוח בה חשבון · זאת כל מטרתה · ומאותו רגע הוא authenticated
-- ‏באותו פרויקט עצמו, עם אותו מפתח פרסום שמודפס בקוד המקור של
-- ‏הדף. קריאה אחת ל-/rest/v1/leads הייתה מחזירה לו את כל השמות
-- ‏והטלפונים, ואחת ל-/rest/v1/calc_results את כל התמונות
-- ‏הפיננסיות שאנשים מילאו במחשבון.
--
-- ‏מה עכשיו: "מחובר" כבר אינו הרשאה. יש רשימת צוות מפורשת, והיא
-- ‏התנאי בכל מדיניות. משתמש של האפליקציה מקבל אפס שורות.

-- ───────────────────────────────────────────── רשימת הצוות ──
create table if not exists public.staff(
  user_id    uuid primary key references auth.users(id) on delete cascade,
  note       text,
  created_at timestamptz not null default now()
);

-- ‏הטבלה עצמה אינה נגישה דרך ה-API בכלל · לא לקריאה ולא לכתיבה.
-- ‏אין לה אף מדיניות, ולכן RLS חוסם הכול, והדרך היחידה לשנות אותה
-- ‏היא עורך ה-SQL הזה.
alter table public.staff enable row level security;
revoke all on table public.staff from anon, authenticated;

create or replace function public.is_staff()
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.staff where user_id = auth.uid())
$$;
revoke all on function public.is_staff() from public, anon;
grant execute on function public.is_staff() to authenticated;

-- ──────────────────────────────────────────────── האכלוס ──
-- ‏לפי כתובת, כי מזהה המשתמש אינו ידוע מראש. מי שהמייל שלו אינו
-- ‏ברשימה פשוט לא ייכנס, והבדיקה מיד אחרי תעצור את ההרצה.
-- ‏שתי הכתובות של שוהם · הפרטית, שהיא המשתמש שקיים היום בפרויקט,
-- ‏והעסקית, שתיכנס לרשימה ברגע שיהיה לה משתמש. הרשימה לפי כתובת
-- ‏ולא לפי מזהה, ולכן אפשר להריץ שוב אחרי יצירת המשתמש השני
-- ‏והוא ייכנס מעצמו.
--
-- ‏להוספת מישהו אחר, שורה אחת:
--   insert into public.staff(user_id, note)
--   select id, 'מי זה' from auth.users where lower(email) = 'כתובת'
--   on conflict (user_id) do nothing;
insert into public.staff (user_id, note)
select id, 'שוהם' from auth.users
 where lower(email) in (
   'shohamabo@gmail.com',          -- הפרטי · המשתמש שקיים היום
   'shohamfinance23@gmail.com'     -- העסקי · ברגע שייווצר
 )
on conflict (user_id) do nothing;

-- ‏עצירה בטוחה. עדיף שההרצה תיפול מאשר שהדשבורד יינעל בפני בעליו.
do $$
begin
  if not exists (select 1 from public.staff) then
    raise exception using message =
      'רשימת הצוות ריקה, ולכן עצרתי לפני שנעלתי לך את הדשבורד. ' ||
      'הוסף את עצמך והרץ שוב: ' ||
      'insert into public.staff(user_id) select id from auth.users where lower(email)=lower(''המייל שלך'');';
  end if;
end $$;

-- ───────────────────────────────────────────── הנעילה ──
-- ‏עובר על כל טבלה עסקית, מוחק ממנה כל מדיניות קיימת · גם כאלה
-- ‏שנכתבו מחוץ לריפו ואיני יכול לראות אותן מכאן · ובונה במקומן
-- ‏מדיניות אחת לקריאה ואחת למחיקה, שתיהן מותנות בחברות בצוות.
do $$
declare
  t   text;
  p   text;
  tbl text[] := array[
    'leads', 'quiz_results', 'calc_results', 'wa_clicks',
    'page_funnel', 'quiz_funnel', 'call_clicks', 'video_funnel'
  ];
begin
  foreach t in array tbl loop
    if to_regclass('public.' || t) is null then
      raise notice 'אין טבלה בשם %, מדלג', t;
      continue;
    end if;

    for p in select policyname from pg_policies
              where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', p, t);
    end loop;

    execute format('alter table public.%I enable row level security', t);

    execute format(
      'create policy %I on public.%I for select to authenticated using (public.is_staff())',
      t || '_staff_read', t);
    execute format(
      'create policy %I on public.%I for delete to authenticated using (public.is_staff())',
      t || '_staff_del', t);

    -- ‏לידים גם מתעדכנים מהדשבורד · תגיות, מעקב, הערות.
    if t = 'leads' then
      execute format(
        'create policy %I on public.%I for update to authenticated '
        'using (public.is_staff()) with check (public.is_staff())',
        t || '_staff_upd', t);
      execute format('grant select, update, delete on table public.%I to authenticated', t);
    else
      execute format('grant select, delete on table public.%I to authenticated', t);
    end if;

    -- ‏Supabase נותן ל-anon הרשאות על טבלה חדשה כברירת מחדל, ואז
    -- ‏RLS הוא הדבר היחיד שעומד בין מבקר לבין הכול. אומרים את זה
    -- ‏במפורש במקום להישען על זה.
    execute format('revoke all on table public.%I from anon', t);
  end loop;
end $$;

-- ─────────────────────────────── מה שאולי פספסתי ──
-- ‏את הטבלאות שלמעלה אני מכיר מהריפו. ייתכן שיש בפרויקט טבלאות
-- ‏שנוצרו מחוץ לו, ואיני יכול לראות אותן מכאן. הבלוק הזה אינו
-- ‏נוגע בכלום · הוא רק מדפיס כל טבלה שעוד פתוחה ל"כל מי שמחובר",
-- ‏כדי שתראה אותה ותחליט.
do $$
declare row_ record; n int := 0;
begin
  for row_ in
    select tablename, policyname, cmd
      from pg_policies
     where schemaname = 'public'
       and 'authenticated' = any(roles)
       and coalesce(qual, 'true') = 'true'
       and tablename not in ('households','household_members','profiles','categories',
                             'budgets','transactions','reflections','documents',
                             'imports','goals','assets')
     order by tablename, policyname
  loop
    n := n + 1;
    raise warning 'עוד פתוח לכל מי שמחובר: %.% (%)', row_.tablename, row_.policyname, row_.cmd;
  end loop;
  if n = 0 then
    raise notice 'לא נשארה אף טבלה עסקית שפתוחה לכל מי שמחובר.';
  else
    raise notice 'נשארו % מדיניות פתוחות. ראה את האזהרות שלמעלה.', n;
  end if;
end $$;

-- ‏הכתיבה עצמה לא נגעתי בה. כל מה שכותב לטבלאות האלה הוא פונקציית
-- ‏security definer · submit_lead, quiz_submit, wa_click, הפינגים
-- ‏של המשפכים · והן רצות בהרשאות הבעלים ועוקפות RLS בכוונה. הטופס
-- ‏בדף הנחיתה ימשיך לעבוד בדיוק כמו קודם.

notify pgrst, 'reload schema';
