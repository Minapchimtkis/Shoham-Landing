-- ═══════════════════════════════════════════════════════════════
--  בדיקה בלבד · לא משנה כלום, לא כותב כלום, אפשר להריץ בכל רגע
-- ═══════════════════════════════════════════════════════════════
-- מה שהיא בודקת: שכל מה שמסך החובות צריך באמת קיים בפרויקט.
-- כל שורה שחוזרת "תקין" היא דבר אחד שעובד. כל "חסר" הוא הסיבה
-- שהמסך לא יעבוד, והיא אומרת מה להריץ כדי לתקן.

with c(n, ord, ok) as (values

  ('טבלת החובות קיימת', 1,
   to_regclass('public.debts') is not null),

  ('כל העמודות שלה', 2,
   (select count(*) = 9 from information_schema.columns
     where table_schema='public' and table_name='debts'
       and column_name in ('id','household_id','kind','name',
         'balance_agorot','monthly_agorot','rate_bp','ends_on','archived'))),

  ('הגנת השורות דלוקה', 3,
   coalesce((select relrowsecurity from pg_class
              where oid = to_regclass('public.debts')), false)),

  ('ומדיניות הגישה קיימת', 4,
   exists(select 1 from pg_policies
           where schemaname='public' and tablename='debts' and policyname='debt_rw')),

  ('למשתמש מחובר יש הרשאה מלאה', 5,
   (select count(*) = 4 from information_schema.role_table_grants
     where table_schema='public' and table_name='debts' and grantee='authenticated'
       and privilege_type in ('SELECT','INSERT','UPDATE','DELETE'))),

  ('ולאורח אנונימי אין גישה לטבלה', 6,
   to_regclass('public.debts') is not null
   and not exists(select 1 from information_schema.role_table_grants
                   where table_schema='public' and table_name='debts' and grantee='anon')),

  ('קרן כספית מותרת ברשימת הנכסים', 7,
   exists(select 1 from pg_constraint
           where conrelid = to_regclass('public.assets')
             and contype='c'
             and pg_get_constraintdef(oid) like '%money_market%')),

  ('טבלת תצלומי ההון קיימת', 8,
   to_regclass('public.net_worth_snapshots') is not null),

  ('ויש לה הרשאה', 9,
   (select count(*) = 4 from information_schema.role_table_grants
     where table_schema='public' and table_name='net_worth_snapshots'
       and grantee='authenticated'
       and privilege_type in ('SELECT','INSERT','UPDATE','DELETE')))
)
select
  ord                             as "#",
  n                               as "מה נבדק",
  case when ok then 'תקין' else 'חסר' end as "מצב"
from c
union all
select 99, '═══ סיכום ═══',
  case when bool_and(ok)
       then 'הכל תקין · מסך החובות אמור לעבוד'
       else 'חסר משהו · להריץ את 20261017120000_app_debts.sql'
  end
from c
order by 1;
