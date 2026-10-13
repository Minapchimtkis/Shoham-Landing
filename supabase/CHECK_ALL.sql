-- ‏מה כבר רץ ומה עוד לא.
-- ═══════════════════════════════════════════════════════════════
--
-- ‏לקרוא בלבד. אינה כותבת, אינה משנה ואינה מוחקת כלום, ואפשר
-- ‏להריץ אותה בכל רגע ובכל מספר פעמים.
--
-- ‏להדביק בעורך ה-SQL של סופהבייס וללחוץ Run. כל שורה שחוזרת
-- ‏עם ✗ היא דבר שהאפליקציה מחפשת ולא מוצאת, ולידה כתוב איזו
-- ‏מיגרציה מביאה אותו.

with c(n, what, fix, ok) as (values

-- ── ‏הטבלאות ──
 (1,'כל טבלאות הליבה', '20261007120000_app_core',
    (select count(*)=9 from pg_tables where schemaname='public' and tablename in
     ('households','household_members','profiles','categories','budgets',
      'transactions','reflections','documents','imports'))),
 (2,'מטרות ונכסים', '20261010120000 + 20261012120000',
    (select count(*)=2 from pg_tables where schemaname='public' and tablename in ('goals','assets'))),
 (3,'חובות', '20261017120000_app_debts',
    (select count(*)=1 from pg_tables where schemaname='public' and tablename='debts')),
 (4,'תצלומי ההון העצמי', '20261018120000_net_worth_snapshots',
    (select count(*)=1 from pg_tables where schemaname='public' and tablename='net_worth_snapshots')),
 (5,'מה שהייבוא לומד', '20261019120000_merchant_rules',
    (select count(*)=1 from pg_tables where schemaname='public' and tablename='merchant_rules')),
 (6,'הזמנות לתקציב משותף', '20261020120000_shared_household',
    (select count(*)=1 from pg_tables where schemaname='public' and tablename='household_invites')),

-- ── ‏העמודות שנוספו בדרך ──
 (7,'יום תחילת המחזור', '20261011120000_app_cycle',
    (select count(*)=1 from information_schema.columns
      where table_schema='public' and table_name='households' and column_name='cycle_start')),
 (8,'סוג משק הבית · לבד או בשניים', '20261020120000_shared_household',
    (select count(*)=1 from information_schema.columns
      where table_schema='public' and table_name='households' and column_name='kind')),
 (9,'הצבע של כל אחד', '20261020120000_shared_household',
    (select count(*)=1 from information_schema.columns
      where table_schema='public' and table_name='household_members' and column_name='color')),

-- ── ‏הפונקציות ──
 (10,'פתיחת משק בית', '20261007120000_app_core',
    (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='setup_household')),
 (11,'יצירת קוד הזמנה', '20261020120000_shared_household',
    (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='make_invite')),
 (12,'הצטרפות עם קוד', '20261020120000_shared_household',
    (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='join_household')),

-- ── ‏מדיניות הקריאה של השם השני ──
 (13,'כל אחד רואה את שם השני', '20261020120000_shared_household',
    (select count(*)=1 from pg_policies
      where schemaname='public' and tablename='profiles' and policyname='pr_read_house')),
 (14,'וכל אחד בוחר את הצבע שלו', '20261020120000_shared_household',
    (select count(*)=1 from pg_policies
      where schemaname='public' and tablename='household_members' and policyname='hm_color')),

-- ── ‏האבטחה. לא תכונה · אם אחת מאלה ✗, הנתונים חשופים ──
 (15,'אין טבלה בלי אבטחת שורות', 'בדיקת אבטחה · לא מיגרציה',
    (select count(*) filter (where not rowsecurity) = 0
       from pg_tables where schemaname='public' and tablename in
     ('households','household_members','profiles','categories','budgets','transactions',
      'reflections','documents','imports','goals','assets','debts',
      'net_worth_snapshots','merchant_rules','household_invites'))),
 (16,'אנונימי אינו רואה תנועות', 'בדיקת אבטחה · לא מיגרציה',
    (select coalesce((select not has_table_privilege('anon','public.transactions','SELECT')
       where to_regclass('public.transactions') is not null
         and exists(select 1 from pg_roles where rolname='anon')), false))),
 (17,'אי אפשר להצטרף למשק בית בלי קוד', 'בדיקת אבטחה · לא מיגרציה',
    (select coalesce((select not has_table_privilege('authenticated','public.household_members','INSERT')
       where to_regclass('public.household_members') is not null
         and exists(select 1 from pg_roles where rolname='authenticated')), false)))
)
select n as "#",
       case when ok then '✓' else '✗' end as "מצב",
       what as "מה",
       case when ok then '' else fix end as "מה מביא את זה"
from c order by n;
