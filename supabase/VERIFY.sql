with c(n, what, ok) as (values
 (1,'כל הטבלאות קיימות',
    (select count(*)=9 from pg_tables where schemaname='public' and tablename in
     ('households','household_members','profiles','categories','budgets',
      'transactions','reflections','documents','imports'))),
 (2,'גם מטרות ונכסים',
    (select count(*)=2 from pg_tables where schemaname='public' and tablename in ('goals','assets'))),
 (3,'אבטחת שורות דלוקה על כולן',
    (select bool_and(rowsecurity) from pg_tables where schemaname='public' and tablename in
     ('households','household_members','profiles','categories','budgets','transactions',
      'reflections','documents','imports','goals','assets'))),
 (4,'אי אפשר להצטרף למשק בית · אין מדיניות כתיבה',
    (select count(*)=0 from pg_policies where tablename='household_members'
      and cmd in ('INSERT','UPDATE','ALL'))),
 (5,'וגם אין הרשאת כתיבה בכלל',
    (select coalesce((select not has_table_privilege('authenticated','public.household_members','INSERT')
       and not has_table_privilege('authenticated','public.household_members','UPDATE')
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relname='household_members'), false))),
 (6,'אי אפשר ליצור משק בית ישירות',
    (select coalesce((select not has_table_privilege('authenticated','public.households','INSERT')
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relname='households'), false))),
 (7,'מחיקת משק בית רק לבעלים',
    (select count(*)=1 from pg_policies where tablename='households' and cmd='DELETE'
      and qual like '%owner%')),
 (8,'דלי המסמכים פרטי',
    (select not public from storage.buckets where id='docs')),
 (9,'מדיניות על הקבצים',
    (select count(*)=4 from pg_policies where schemaname='storage' and policyname like 'docs_%')),
 (10,'הפונקציות קיימות',
    (select count(*)=3 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in ('is_member','setup_household','wa_click'))),
 (11,'חודש תקציבי ניתן להזזה',
    (select count(*)=1 from information_schema.columns
      where table_name='households' and column_name='cycle_start')),
 (12,'אנונימי חסום',
    (select coalesce((select not has_table_privilege('anon','public.transactions','SELECT')
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relname='transactions'), false))),
 -- לא נוגעים בתוכן הטבלה · אזכור ישיר שלה מפיל את כל השאילתה
 -- אם היא עוד לא קיימת, במקום לדווח על כישלון אחד. שהיא אינה
 -- ריקה מובטח ממילא · המיגרציה עוצרת אם אין בה אף אחד.
 (13,'יש רשימת צוות ופונקציית is_staff',
    (select to_regclass('public.staff') is not null
        and exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'is_staff'))),
 (14,'רשימת הצוות עצמה סגורה לגמרי',
    (select not exists (select 1 from pg_policies
       where schemaname='public' and tablename='staff'))),
 -- טבלה שאינה קיימת אינה כישלון · bool_and על אפס שורות מחזיר
 -- ריק, ולכן הניסוח הוא "אין אף מדיניות שאינה דרך הצוות".
 (15,'הלידים נעולים לצוות בלבד',
    (select not exists (select 1 from pg_policies
      where schemaname='public' and tablename='leads'
        and coalesce(qual,'true') not like '%is_staff%'))),
 (16,'וגם תוצאות השאלון והמחשבון',
    (select not exists (select 1 from pg_policies
      where schemaname='public' and tablename in ('quiz_results','calc_results')
        and coalesce(qual,'true') not like '%is_staff%'))),
 (17,'וגם הקליקים והמשפכים',
    (select not exists (select 1 from pg_policies
      where schemaname='public' and tablename in
        ('wa_clicks','page_funnel','quiz_funnel','call_clicks','video_funnel')
        and coalesce(qual,'true') not like '%is_staff%'))),
 (18,'לא נשארה טבלה עסקית פתוחה לכל מי שמחובר',
    (select not exists (select 1 from pg_policies
      where schemaname='public' and 'authenticated' = any(roles)
        and coalesce(qual,'true')='true'
        and tablename not in ('households','household_members','profiles','categories',
                              'budgets','transactions','reflections','documents',
                              'imports','goals','assets'))))
)
select n as "#", what as "מה נבדק", case when ok then 'עובר' else '✗ נכשל' end as "תוצאה" from c
union all
select 99, '═══ סיכום ═══',
  (select count(*) filter (where ok)||' מתוך '||count(*) from c)
order by 1;
