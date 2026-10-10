-- להעתיק את כל הקובץ הזה לעורך ה-SQL של Supabase וללחוץ Run.
-- הרצה חוזרת אינה מזיקה.
-- ═══════════════════════════════════════════════════════════════
--  תצלומי הון עצמי · הקו השני בגרף
-- ═══════════════════════════════════════════════════════════════
--
-- בלי הטבלה הזאת הגרף במסך סיכום השנה מראה קו אחד בלבד, "מה
-- שנשאר", והאפליקציה ממשיכה לעבוד בדיוק כמו קודם. אחריה מופיע
-- גם הקו השני.
--
-- למה בכלל צריך טבלה: assets מחזיקה את הסכום הנוכחי בלבד,
-- ו-debts את היתרה הנוכחית בלבד. כשאתה מעדכן את הפנסיה
-- מ-200,000 ל-210,000, המספר הקודם נמחק ואין לאן לחזור. לכן
-- אי אפשר לצייר הון עצמי לאחור · הנתון אינו קיים, וציור שלו
-- בכל זאת היה המצאה.
--
-- מכאן והלאה הוא כן קיים. האפליקציה כותבת שורה אחת לחודש בכל
-- פתיחה, כך שהחודש הנוכחי תמיד עדכני והחודשים שעברו קפואים
-- כפי שהיו. הקו יתחיל להיראות מהחודש השני.
--
-- לא נכתב כלום למי שאין לו נכסים ואין לו חובות. אפס כזה אינו
-- "אין לי כלום" אלא "עוד לא הזנתי", וקו שטוח על אפס הוא שקר
-- שקט.

create table if not exists public.net_worth_snapshots(
  household_id uuid not null references public.households(id) on delete cascade,

  -- תמיד ה-1 בחודש, כמו budgets. נקודה אחת לחודש היא הרזולוציה
  -- שאדם באמת מסתכל עליה, ויומית הייתה יוצרת רעש בלי מידע.
  as_of date not null,

  assets_agorot      bigint not null default 0 check (assets_agorot >= 0),
  -- ההתחייבויות שרובצות על נכסים · משכנתא על דירה
  liabilities_agorot bigint not null default 0 check (liabilities_agorot >= 0),
  -- החובות העומדים בפני עצמם · הלוואה, מינוס, אשראי
  debts_agorot       bigint not null default 0 check (debts_agorot >= 0),

  net_agorot bigint generated always as
    (assets_agorot - liabilities_agorot - debts_agorot) stored,

  updated_at timestamptz not null default now(),

  primary key (household_id, as_of),
  constraint nws_first_of_month check (extract(day from as_of) = 1),
  -- תצלום בעתיד אינו תצלום. בלי זה שעון מוטעה בטלפון היה פותח
  -- נקודה בעוד שנה ומותח את כל הגרף.
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

-- אבטחת השורות קובעת מי רואה מה, אבל בלי ההרשאה הזאת איש אינו
-- מגיע לטבלה בכלל דרך ה-API. שאר הטבלאות באפליקציה מעניקות
-- אותה במפורש, וגם זאת.
grant select, insert, update, delete on table public.net_worth_snapshots to authenticated;


-- ─────────────────────────────── בדיקה ──
-- ארבע שורות של "תקין".
select 'הטבלה קיימת' as what,
       case when to_regclass('public.net_worth_snapshots') is not null
            then 'תקין' else 'חסרה' end as status
union all
select 'אבטחת שורות',
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
            then 'תקין' else 'חסר' end;
