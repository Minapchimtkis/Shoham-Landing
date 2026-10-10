-- כמה יש לי · כל המיגרציות בקובץ אחד, לפי הסדר.
-- נוצר אוטומטית מהקבצים הבודדים. מריצים הכול בבת אחת בעורך
-- ה-SQL של Supabase. הרצה חוזרת אינה מזיקה.



-- ═══════════════════════════════════════════════════════════
-- 20261007120000_app_core.sql
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
--  אפליקציית התקציב, שלב ראשון: המבנה
-- ═══════════════════════════════════════════════════════════════
--
-- שלוש החלטות שקשה לשנות אחר כך, ולכן הן כאן מההתחלה:
--
-- 1. היחידה היא משק בית ולא משתמש. גם כשיש משתמש אחד, הכול תלוי
--    ב-household. זה מה שיאפשר להוסיף בן או בת זוג בלי הגירה.
--
-- 2. כסף נשמר כמספר שלם באגורות. לעולם לא עשרוני. 14500 ולא
--    145.00. זה הבאג שתופס כל מערכת פיננסית שלא עשתה את זה ביום
--    הראשון, והוא מתגלה רק כשכבר יש נתונים.
--
-- 3. חודש הוא תאריך של ה-1 בחודש, לא מחרוזת. מחרוזת לא יודעת
--    להשוות, למיין או לחסר חודשים.
--
-- וכל הגישה עוברת דרך household_members בלבד. אין שום מסלול אחר
-- לנתונים, ולכן אי אפשר לקרוא משק בית אחר גם מי שמשנה מזהה בכתובת.
--
-- להרצה בעורך ה-SQL של Supabase. הרצה חוזרת אינה מזיקה.

-- ───────────────────────────────────────────────── משקי בית ──
create table if not exists public.households(
  id         uuid primary key default gen_random_uuid(),
  name       text not null default 'משק הבית שלי',
  created_at timestamptz not null default now()
);

create table if not exists public.household_members(
  household_id uuid not null references public.households(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  -- owner פותח, partner בן או בת זוג, advisor הוא בהמשך ועם הסכמה
  role         text not null default 'owner'
               check (role in ('owner','partner','advisor')),
  created_at   timestamptz not null default now(),
  primary key (household_id, user_id)
);

create index if not exists hm_user_idx on public.household_members (user_id);

create table if not exists public.profiles(
  user_id      uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at   timestamptz not null default now()
);

-- פונקציית העזר שכל מדיניות נשענת עליה. stable כדי שהמתכנן יקרא
-- לה פעם אחת לשאילתה ולא לכל שורה.
create or replace function public.is_member(p_household uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.household_members
     where household_id = p_household and user_id = auth.uid()
  )
$$;

-- ───────────────────────────────────────────────── קטגוריות ──
-- household_id ריק הוא קטגוריית מערכת, שכולם רואים ואיש לא משנה.
create table if not exists public.categories(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid references public.households(id) on delete cascade,
  key          text,
  label        text not null,
  icon         text,
  kind         text not null default 'expense' check (kind in ('expense','income')),
  sort         integer not null default 100,
  archived     boolean not null default false,
  created_at   timestamptz not null default now()
);

create index if not exists categories_household_idx on public.categories (household_id);
create unique index if not exists categories_system_key_idx
  on public.categories (key) where household_id is null;

-- שש, ולא שלוש עשרה. רשימה ארוכה בהקמה הראשונה היא הדרך הבטוחה
-- לכך שאיש לא ימלא אותה. אפשר להוסיף אחר כך.
insert into public.categories (household_id, key, label, icon, kind, sort) values
  (null, 'housing',   'דיור',        '🏠', 'expense', 10),
  (null, 'food',      'מזון',        '🛒', 'expense', 20),
  (null, 'transport', 'תחבורה',      '🚗', 'expense', 30),
  (null, 'debt',      'החזרים',      '🏦', 'expense', 40),
  (null, 'fun',       'בילויים',     '🎬', 'expense', 50),
  (null, 'other',     'כל השאר',     '•',  'expense', 60),
  (null, 'salary',    'משכורת',      '💼', 'income',  10),
  (null, 'other_in',  'הכנסה אחרת',  '•',  'income',  20)
on conflict (key) where household_id is null do nothing;

-- ─────────────────────────────────────────────────── תקציב ──
create table if not exists public.budgets(
  household_id   uuid not null references public.households(id) on delete cascade,
  month          date not null,                       -- תמיד ה-1 בחודש
  category_id    uuid not null references public.categories(id) on delete cascade,
  planned_agorot bigint not null default 0 check (planned_agorot >= 0),
  updated_at     timestamptz not null default now(),
  primary key (household_id, month, category_id)
);

-- ─────────────────────────────────────────────────── תנועות ──
create table if not exists public.transactions(
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  occurred_on   date not null,
  amount_agorot bigint not null check (amount_agorot > 0),
  direction     text not null check (direction in ('in','out')),
  category_id   uuid references public.categories(id) on delete set null,
  description   text,
  source        text not null default 'manual' check (source in ('manual','import')),

  -- ישראל. קנייה ב-12 תשלומים מופיעה בפירוט כסכום חודשי, ואפליקציה
  -- שלא יודעת את זה סופרת אותה כהוצאה חודשית קבועה ומשקרת למשתמש.
  installment_no    integer check (installment_no    is null or installment_no    > 0),
  installment_total integer check (installment_total is null or installment_total > 0),

  -- כרטיס אשראי ישראלי מחייב בסכום אחד ב-2 או ב-10 לחודש, ולכן
  -- "ההוצאות של החודש" בחשבון אינן ההוצאות של החודש. מוצג לפי
  -- תאריך העסקה, ומועד החיוב נשמר בנפרד.
  charged_on    date,

  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now()
);

create index if not exists tx_household_date_idx on public.transactions (household_id, occurred_on desc);
create index if not exists tx_category_idx       on public.transactions (household_id, category_id);

-- ──────────────────────────────────────────── אבטחת שורות ──
-- חוסם כברירת מחדל. כל גישה נגזרת מ-is_member ומשום מקום אחר.
alter table public.households        enable row level security;
alter table public.household_members enable row level security;
alter table public.profiles          enable row level security;
alter table public.categories        enable row level security;
alter table public.budgets           enable row level security;
alter table public.transactions      enable row level security;

drop policy if exists hh_rw        on public.households;
drop policy if exists hh_read      on public.households;
drop policy if exists hh_update    on public.households;
drop policy if exists hh_delete    on public.households;
drop policy if exists hm_read      on public.household_members;
drop policy if exists hm_self      on public.household_members;
drop policy if exists hm_read_self on public.household_members;
drop policy if exists hm_read_house on public.household_members;
drop policy if exists hm_leave     on public.household_members;
drop policy if exists pr_rw        on public.profiles;
drop policy if exists cat_read     on public.categories;
drop policy if exists cat_write    on public.categories;
drop policy if exists bud_rw       on public.budgets;
drop policy if exists tx_rw        on public.transactions;

-- קריאה ועדכון לכל חבר, מחיקה רק לבעלים, ויצירה בשום מקום חוץ
-- מ-setup_household. מחיקת משק בית גוררת בשרשרת את כל מה שבתוכו.
create policy hh_read on public.households for select to authenticated
  using (public.is_member(id));
create policy hh_update on public.households for update to authenticated
  using (public.is_member(id)) with check (public.is_member(id));
create policy hh_delete on public.households for delete to authenticated
  using (exists (select 1 from public.household_members m
                  where m.household_id = households.id
                    and m.user_id = auth.uid()
                    and m.role = 'owner'));

-- שורת החברות של עצמך נראית תמיד, גם ברגע ההקמה שבו עוד אין
-- משק בית להיות חבר בו ולכן is_member עוד אינה יכולה להחזיר true.
create policy hm_read_self on public.household_members for select to authenticated
  using (user_id = auth.uid());
create policy hm_read_house on public.household_members for select to authenticated
  using (public.is_member(household_id));
-- לצאת אפשר רק את עצמך, ורק אם אינך הבעלים.
create policy hm_leave on public.household_members for delete to authenticated
  using (user_id = auth.uid() and role <> 'owner');
-- אין מדיניות INSERT ואין UPDATE על החברות. ההצטרפות היחידה
-- למשק בית עוברת ב-setup_household, שהיא security definer, וכך גם
-- כל פונקציית הזמנה שתיכתב בעתיד. בלי זה כל משתמש מחובר יכול
-- להוסיף את עצמו למשק בית שמזההו ידוע לו, ומזהה אינו הרשאה.

create policy pr_rw on public.profiles for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- קטגוריות המערכת גלויות לכולם, ושל משק בית רק לחבריו.
create policy cat_read on public.categories for select to authenticated
  using (household_id is null or public.is_member(household_id));
create policy cat_write on public.categories for all to authenticated
  using (household_id is not null and public.is_member(household_id))
  with check (household_id is not null and public.is_member(household_id));

create policy bud_rw on public.budgets for all to authenticated
  using (public.is_member(household_id)) with check (public.is_member(household_id));

create policy tx_rw on public.transactions for all to authenticated
  using (public.is_member(household_id)) with check (public.is_member(household_id));

revoke all on table public.households, public.household_members, public.profiles,
                    public.categories, public.budgets, public.transactions from anon;
grant select, insert, update, delete on table
  public.profiles, public.categories, public.budgets,
  public.transactions to authenticated;
-- משק בית נוצר, ומצורפים אליו, רק בתוך setup_household. ולכן אין
-- למשתמש הרשאת INSERT עליהם בכלל · לא במדיניות ולא בהרשאה עצמה.
grant select, update, delete on table public.households        to authenticated;
grant select,         delete on table public.household_members to authenticated;

-- ────────────────────────────────────────── ההקמה הראשונה ──
-- נקראת פעם אחת, אחרי ההרשמה. יוצרת משק בית, מצרפת את המשתמש
-- אליו, וכותבת את התקציב ההתחלתי משש המספרים.
--
-- הכול בקריאה אחת ובטרנזקציה אחת, אחרת משתמש שהדפדפן שלו נסגר
-- באמצע נשאר עם משק בית בלי תקציב ובלי דרך חזרה.
create or replace function public.setup_household(
  p_name    text,
  p_income  bigint,                  -- באגורות
  p_budget  jsonb                    -- {"housing":500000,"food":200000,...}
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user  uuid := auth.uid();
  v_hh    uuid;
  v_month date := date_trunc('month', current_date)::date;
  v_key   text;
  v_cat   uuid;
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;

  -- מי שכבר יש לו משק בית מקבל אותו בחזרה במקום עוד אחד.
  select household_id into v_hh from public.household_members
   where user_id = v_user limit 1;
  if v_hh is not null then
    return v_hh;
  end if;

  insert into public.households (name)
  values (left(coalesce(nullif(btrim(p_name),''),'משק הבית שלי'), 60))
  returning id into v_hh;

  insert into public.household_members (household_id, user_id, role)
  values (v_hh, v_user, 'owner');

  insert into public.profiles (user_id, display_name)
  values (v_user, left(nullif(btrim(p_name),''), 60))
  on conflict (user_id) do nothing;

  -- ההכנסה נשמרת כתקציב של קטגוריית ההכנסה, ולא כשדה נפרד, כדי
  -- שהיא תוכל להשתנות מחודש לחודש כמו כל השאר.
  if coalesce(p_income,0) > 0 then
    select id into v_cat from public.categories
     where household_id is null and key = 'salary';
    -- בלי הבדיקה הזאת, קטגוריה חסרה הופכת ל-category_id ריק
    -- והפונקציה נופלת על אילוץ במקום פשוט לדלג. זה לא אמור לקרות,
    -- אבל "לא אמור" הוא לא אותו דבר כמו "לא יכול".
    if v_cat is not null then
      insert into public.budgets (household_id, month, category_id, planned_agorot)
      values (v_hh, v_month, v_cat, greatest(p_income,0))
      on conflict (household_id, month, category_id) do update
        set planned_agorot = excluded.planned_agorot, updated_at = now();
    end if;
  end if;

  for v_key in select jsonb_object_keys(coalesce(p_budget,'{}'::jsonb)) loop
    select id into v_cat from public.categories
     where household_id is null and key = v_key;
    if v_cat is not null then
      insert into public.budgets (household_id, month, category_id, planned_agorot)
      values (v_hh, v_month, v_cat,
              greatest((p_budget ->> v_key)::bigint, 0))
      on conflict (household_id, month, category_id) do update
        set planned_agorot = excluded.planned_agorot, updated_at = now();
    end if;
  end loop;

  return v_hh;
end $$;

revoke all on function public.setup_household(text,bigint,jsonb) from public;
grant execute on function public.setup_household(text,bigint,jsonb) to authenticated;


-- ═══════════════════════════════════════════════════════════
-- 20261008120000_app_reflections.sql
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
--  אפליקציית התקציב, שלב שני: השכבה שאינה מספרים
-- ═══════════════════════════════════════════════════════════════
--
-- הטבלה הזאת היא מה שהופך את האפליקציה לכלי עם נשמה ולא למחשבון.
-- היא שומרת תשובות של אדם על הכסף שלו, ולא סכומים.
--
-- שני סוגים:
--
--   overspend  · קטגוריה עברה את התכנון, והאפליקציה שאלה למה.
--                לא נורה אדומה. נורה אדומה גורמת לאנשים להפסיק
--                לפתוח את האפליקציה, וזה בדיוק השד השני: פחד
--                להסתכל בחשבון.
--
--   month_end  · החודש נגמר. שאלה אחת, בלי ציון ובלי סיכום.
--
-- האילוץ החשוב כאן הוא שלא נשאל פעמיים את אותה שאלה. הוא נאכף
-- בבסיס ולא בדפדפן, כי הדפדפן נפתח בעשרה טאבים.
--
-- להרצה בעורך ה-SQL של Supabase, אחרי 20261007120000_app_core.
-- הרצה חוזרת אינה מזיקה.

create table if not exists public.reflections(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  kind         text not null check (kind in ('overspend','month_end')),
  month        date not null,                      -- תמיד ה-1 בחודש
  category_id  uuid references public.categories(id) on delete set null,
  -- מה שנבחר מתוך הצ'יפים, או skipped למי שבחר לא לענות. גם
  -- "לא עכשיו" הוא תשובה, ובלעדיה היינו שואלים אותו שוב מחר.
  choice       text,
  note         text,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),

  constraint reflections_choice_len check (choice is null or length(choice) <= 60),
  constraint reflections_note_len   check (note   is null or length(note)   <= 500),
  -- שאלת סוף חודש אינה שייכת לקטגוריה, ושאלת חריגה אינה קיימת
  -- בלעדיה. בלי זה היו נכנסות שורות ששתי השאילתות שקוראות אותן
  -- לא היו מוצאות.
  constraint reflections_shape check (
    (kind = 'overspend' and category_id is not null) or
    (kind = 'month_end' and category_id is null)
  )
);

create index if not exists reflections_hh_month_idx
  on public.reflections (household_id, month desc);

-- פעם אחת לכל שאלה. שני אינדקסים חלקיים ולא אחד עם coalesce,
-- כי null בתוך מפתח ייחודי אינו מתנגש עם null אחר, ולכן אינדקס
-- אחד היה מרשה עשר שאלות סוף חודש לאותו חודש.
create unique index if not exists reflections_once_cat_idx
  on public.reflections (household_id, kind, month, category_id)
  where category_id is not null;

create unique index if not exists reflections_once_month_idx
  on public.reflections (household_id, kind, month)
  where category_id is null;

alter table public.reflections enable row level security;

drop policy if exists refl_rw on public.reflections;
create policy refl_rw on public.reflections for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.reflections from anon;
grant select, insert, update, delete on table public.reflections to authenticated;


-- ═══════════════════════════════════════════════════════════
-- 20261009120000_app_documents.sql
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
--  אפליקציית התקציב, שלב שלישי: המסמכים
-- ═══════════════════════════════════════════════════════════════
--
-- לא כל קובץ שאדם מעלה הוא רשימת תנועות.
--
--   דף עו"ש ופירוט אשראי הם רשימות. הם נקראים, מוצגים לאישור,
--   והופכים לשורות ב-transactions. הם לא נשמרים כאן.
--
--   דוח יתרות וסילוקין וחשבון של חשמל הם מסמכים. יש בהם מספר
--   אחד או שניים שחשובים, והשאר הוא נייר שרוצים שיהיה שמור.
--   הם נשמרים כאן, עם מה שחולץ מהם.
--
-- הקובץ עצמו יושב ב-Storage ולא בטבלה. דוח סילוקין הוא מאות
-- קילובייטים, וטבלה שמחזיקה אותם הופכת כל שאילתה עליה לאיטית
-- גם כשלא ביקשו את הקובץ.
--
-- להרצה בעורך ה-SQL של Supabase, אחרי שני הקבצים שלפניו.
-- הרצה חוזרת אינה מזיקה.

create table if not exists public.documents(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,

  -- loan הוא דוח יתרות וסילוקין, bill הוא חשבון של ספק,
  -- statement הוא דף שנשמר כאסמכתא, other הוא כל השאר.
  kind         text not null default 'other'
               check (kind in ('loan','bill','statement','other')),

  title        text not null,
  provider     text,                      -- חברת חשמל, מזרחי טפחות
  period       date,                      -- לאיזה חודש המסמך שייך

  -- שני המספרים שנשלפים כמעט מכל מסמך: כמה, ועד מתי. השאר
  -- יושב ב-data, כי מה שיש בדוח סילוקין אינו מה שיש בחשבון מים
  -- ועמודה לכל שדה אפשרי הייתה טבלה עם ארבעים עמודות ריקות.
  amount_agorot bigint check (amount_agorot is null or amount_agorot >= 0),
  due_on       date,
  data         jsonb not null default '{}'::jsonb,

  -- הנתיב ב-Storage. תמיד מתחיל במזהה משק הבית, כי מדיניות
  -- הגישה לקבצים נגזרת מהתיקייה הראשונה בנתיב.
  storage_path text,
  mime         text,
  size_bytes   integer check (size_bytes is null or size_bytes >= 0),

  -- כשחשבון הופך להוצאה, הקשר נשמר. בלעדיו אותו חשבון נכנס
  -- פעמיים: פעם מהקובץ ופעם מדף העו"ש.
  transaction_id uuid references public.transactions(id) on delete set null,

  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),

  constraint documents_title_len check (length(btrim(title)) between 1 and 160),
  constraint documents_provider_len check (provider is null or length(provider) <= 80)
);

create index if not exists documents_hh_idx on public.documents (household_id, created_at desc);
create index if not exists documents_kind_idx on public.documents (household_id, kind, period desc);

alter table public.documents enable row level security;
drop policy if exists doc_rw on public.documents;
create policy doc_rw on public.documents for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.documents from anon;
grant select, insert, update, delete on table public.documents to authenticated;

-- ────────────────────────────────────────── מקור הייבוא ──
-- כדי שאפשר יהיה לבטל ייבוא שלם אחרי שהתברר שהוא היה הקובץ
-- הלא נכון, ולדעת מה כבר נקרא כדי לא לקרוא אותו פעמיים.
create table if not exists public.imports(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  source       text not null default 'file'
               check (source in ('file','manual')),
  kind         text not null default 'bank'
               check (kind in ('bank','credit','other')),
  file_name    text,
  -- טביעת אצבע של הקובץ. אותו קובץ שמועלה שוב מזוהה לפני
  -- שמציגים למשתמש מאתיים שורות שהוא כבר אישר פעם אחת.
  file_hash    text,
  rows_total   integer not null default 0 check (rows_total >= 0),
  rows_taken   integer not null default 0 check (rows_taken >= 0),
  charged_on   date,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now()
);

create index if not exists imports_hh_idx on public.imports (household_id, created_at desc);
create unique index if not exists imports_hash_idx
  on public.imports (household_id, file_hash) where file_hash is not null;

alter table public.imports enable row level security;
drop policy if exists imp_rw on public.imports;
create policy imp_rw on public.imports for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.imports from anon;
grant select, insert, update, delete on table public.imports to authenticated;

-- כל תנועה יודעת מאיזה ייבוא היא הגיעה. מחיקת הייבוא משאירה
-- את התנועות ומנתקת אותן, כי מחיקה של היסטוריה כלכלית בגלל
-- ניקיון של רשומת ייבוא היא לא מה שמישהו התכוון אליו.
alter table public.transactions
  add column if not exists import_id uuid references public.imports(id) on delete set null;

create index if not exists tx_import_idx on public.transactions (import_id)
  where import_id is not null;

-- ───────────────────────────────────── הקבצים עצמם ──
-- דלי פרטי. בלי הדלי הזה אין איפה לשמור את הקובץ, ואם הוא
-- נוצר ציבורי, כל מי שמנחש נתיב מוריד דוח סילוקין של מישהו.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('docs', 'docs', false, 15728640,
        array['application/pdf','image/jpeg','image/png','image/webp',
              'text/csv','application/vnd.ms-excel',
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- התיקייה הראשונה בנתיב היא מזהה משק הבית, ולכן היא גם
-- ההרשאה. קובץ בנתיב של משק בית אחר אינו נראה ואינו נכתב.
drop policy if exists docs_read   on storage.objects;
drop policy if exists docs_write  on storage.objects;
drop policy if exists docs_update on storage.objects;
drop policy if exists docs_delete on storage.objects;

create policy docs_read on storage.objects for select to authenticated
  using (bucket_id = 'docs'
         and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));

create policy docs_write on storage.objects for insert to authenticated
  with check (bucket_id = 'docs'
              and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));

create policy docs_update on storage.objects for update to authenticated
  using (bucket_id = 'docs'
         and public.is_member(nullif((storage.foldername(name))[1], '')::uuid))
  with check (bucket_id = 'docs'
              and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));

create policy docs_delete on storage.objects for delete to authenticated
  using (bucket_id = 'docs'
         and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));


-- ═══════════════════════════════════════════════════════════
-- 20261010120000_app_transfers_goals.sql
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
--  אפליקציית התקציב, שלב רביעי: העברות ומטרות
-- ═══════════════════════════════════════════════════════════════
--
-- שני דברים, ושניהם קטנים בכוונה.
--
-- 1. העברה אינה הוצאה.
--
--    כשאדם מעביר אלפיים שקל לחיסכון, הכסף לא יצא מהכיס שלו, הוא
--    עבר לכיס אחר. אפליקציה שסופרת את זה כהוצאה מראה לו שהוא
--    הוציא אלפיים שקל שהוא לא הוציא, ואז המספר הגדול במסך הבית,
--    שהוא כל האפליקציה, פשוט שקר.
--
--    זה מתגלה דווקא בייבוא: דף עו"ש מלא בהעברות כאלה, ובלי העמודה
--    הזאת כל אחת מהן נכנסת כהוצאה.
--
--    עמודה אחת ולא טבלת חשבונות. טבלת חשבונות נוגעת בכל שאילתה
--    באפליקציה, והיא לא נדרשת כדי לפתור את הבעיה הזאת.
--
-- 2. מטרת חיסכון.
--
--    סכום, תאריך יעד, וכמה כבר נצבר. בלי ריבית ובלי תחזיות: מי
--    שרוצה את אלה צריך יועץ, לא אפליקציה.
--
-- להרצה בעורך ה-SQL של Supabase, אחרי שלושת הקבצים שלפניו.
-- הרצה חוזרת אינה מזיקה.

-- ───────────────────────────────────────────── העברות ──
alter table public.transactions
  add column if not exists is_transfer boolean not null default false;

-- אינדקס חלקי: ההעברות הן מיעוט קטן מהשורות, ומה שהשאילתות
-- מבקשות הוא דווקא את כל מה שאינו העברה.
create index if not exists tx_not_transfer_idx
  on public.transactions (household_id, occurred_on desc)
  where is_transfer = false;

-- ────────────────────────────────────────────── מטרות ──
create table if not exists public.goals(
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  title         text not null,
  target_agorot bigint not null check (target_agorot > 0),
  saved_agorot  bigint not null default 0 check (saved_agorot >= 0),
  target_date   date,
  icon          text,
  archived      boolean not null default false,
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint goals_title_len check (length(btrim(title)) between 1 and 60),
  -- יעד בעבר הוא כמעט תמיד טעות הקלדה בשנה, והוא הופך כל חישוב
  -- של "כמה להפריש כל חודש" למספר שלילי.
  constraint goals_date_sane check (target_date is null or target_date >= date '2020-01-01')
);

create index if not exists goals_hh_idx on public.goals (household_id, archived, created_at);

alter table public.goals enable row level security;
drop policy if exists goal_rw on public.goals;
create policy goal_rw on public.goals for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.goals from anon;
grant select, insert, update, delete on table public.goals to authenticated;


-- ═══════════════════════════════════════════════════════════
-- 20261011120000_app_cycle.sql
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
--  אפליקציית התקציב, שלב חמישי: מתי מתחיל החודש
-- ═══════════════════════════════════════════════════════════════
--
-- כרטיס אשראי ישראלי מחייב ב-2 או ב-10 לחודש, ולכן "מה הוצאתי
-- החודש" לפי הכרטיס אינו מה שהוצאתי בחודש הקלנדרי. יש אנשים
-- שמנהלים תקציב מהעשירי עד העשירי, וזה מה שהם רואים בדף.
--
-- מבחינת יועץ פיננסי זה לא נכון כמסגרת ראשית, ובוודאי לא לסיכום
-- שנתי: חודש של עשירי עד עשירי זוחל, שנה כזאת אינה שנים עשר
-- חודשים שלמים, ואי אפשר להשוות בה ינואר לינואר.
--
-- לכן ההחלטה כאן אינה "לתת למשתמש לבחור" אלא איפה בדיוק הבחירה
-- חלה:
--
--   התקציב נשאר תמיד מקובע לחודש קלנדרי. שורת תקציב של תקופה
--   שמתחילה ב-10 באוקטובר נשמרת תחת 1 באוקטובר, בדיוק כמו קודם.
--
--   מה שמשתנה הוא החלון שדרכו רואים את התנועות, ותו לא.
--
-- מכאן נובע שסיכום השנה הוא קלנדרי מעצם המבנה, ולא מפני שמישהו
-- זכר לכתוב תנאי. וגם שאפשר לשנות את יום ההתחלה ולחזור ממנו בלי
-- שאף שורת תקציב תאבד את המפתח שלה.
--
-- להרצה בעורך ה-SQL של Supabase, אחרי ארבעת הקבצים שלפניו.
-- הרצה חוזרת אינה מזיקה.

alter table public.households
  add column if not exists cycle_start smallint not null default 1;

-- עד 28 ולא עד 31: יום 30 אינו קיים בפברואר, ותקופה שמתחילה
-- ביום שלא קיים היא תקופה שלא מתחילה.
alter table public.households
  drop constraint if exists households_cycle_start_range;
alter table public.households
  add constraint households_cycle_start_range
  check (cycle_start between 1 and 28);


-- ═══════════════════════════════════════════════════════════
-- 20261012120000_app_assets.sql
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
--  אפליקציית התקציב, שלב שישי: החסכונות והנכסים
-- ═══════════════════════════════════════════════════════════════
--
-- ספר חשבונות שני, ובכוונה נפרד לגמרי מהראשון.
--
-- תנועות עונות על "כמה הוצאתי החודש". נכסים עונים על "כמה יש
-- לי בכלל". אלה שתי שאלות שונות, והערבוב ביניהן הוא מה שגורם
-- לאפליקציות להציג מספר אחד שלא אומר כלום: אין שום שאילתה
-- שמחברת את הטבלה הזאת ל-transactions.
--
-- הסכום כאן הוא מה שהאדם הקליד, ולא ציטוט חי משום מקום. לכן
-- updated_at אינו קישוט: בלעדיו אי אפשר להגיד למשתמש מתי הוא
-- עדכן בפעם האחרונה, והמסך מתחיל להיראות כמו מסוף מסחר.
--
-- ההתחייבות יושבת על אותה שורה כמו הנכס, ולא בטבלה משלה. משכנתא
-- בלי הדירה שהיא עליה היא לא מידע, ושורה אחת גם מונעת את המצב
-- שבו מוחקים נכס ונשארת התחייבות יתומה שמקטינה את השווי לנצח.
--
-- אין כאן שום דירוג, העדפה או סיווג "טוב" ו"פחות טוב" בין סוגי
-- נכסים. זה כלי מיפוי.
--
-- להרצה בעורך ה-SQL של Supabase, אחרי חמשת הקבצים שלפניו.
-- הרצה חוזרת אינה מזיקה.

create table if not exists public.assets(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,

  kind text not null check (kind in (
    'bank_savings',  -- חיסכון בבנק
    'deposit',       -- פיקדון
    'cash',          -- מזומן
    'portfolio',     -- תיק השקעות
    'crypto',        -- קריפטו
    'mutual_fund',   -- קרן נאמנות
    'study_fund',    -- קרן השתלמות
    'provident',     -- קופת גמל
    'pension',       -- פנסיה
    'realestate',    -- נדל"ן
    'other'
  )),

  name text not null,

  -- בנכס רגיל זה הסכום. בנדל"ן זה שווי הנכס, לא ההון העצמי.
  amount_agorot bigint not null default 0 check (amount_agorot >= 0),

  -- יתרת ההלוואה שרובצת על הנכס. ההון העצמי הוא ההפרש, והוא
  -- מחושב ולא נשמר: ערך שמור ששני מספרים אחרים אמורים להסביר
  -- אותו הוא ערך שיסתור אותם ביום שבו מישהו יעדכן רק אחד מהם.
  liability_agorot bigint not null default 0 check (liability_agorot >= 0),

  note text,
  archived boolean not null default false,

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  -- מתי הסכום עודכן בפעם האחרונה. המשתמש רואה את זה, כדי שלא
  -- יחשוב שהמספר מתעדכן מעצמו.
  updated_at timestamptz not null default now(),

  constraint assets_name_len check (length(btrim(name)) between 1 and 60),
  constraint assets_note_len check (note is null or length(note) <= 300),
  -- התחייבות קיימת רק במקום שהיא נשאלת עליו. בלי זה אפשר לשמור
  -- משכנתא על חשבון מזומן, וההון העצמי הכולל יוצא שגוי בשקט.
  constraint assets_liability_where_asked check (
    liability_agorot = 0 or kind in ('realestate','other')
  )
);

create index if not exists assets_hh_idx on public.assets (household_id, archived, kind);

alter table public.assets enable row level security;
drop policy if exists asset_rw on public.assets;
create policy asset_rw on public.assets for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.assets from anon;
grant select, insert, update, delete on table public.assets to authenticated;


-- ═══════════════════════════════════════════════════════════
-- 20261013120000_wa_click_app.sql
-- ═══════════════════════════════════════════════════════════

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


-- ═══════════════════════════════════════════════════════════
-- 20261014120000_app_members_lock.sql
-- ═══════════════════════════════════════════════════════════

-- כמה יש לי · סגירת ההצטרפות העצמית למשק בית
-- להרצה בעורך ה-SQL של Supabase, אחרי app_core. הרצה חוזרת אינה מזיקה.
--
-- מה היה: המדיניות hm_self על household_members הייתה for all, כלומר
-- גם INSERT, והתנאי היחיד שלה היה user_id = auth.uid(). משתמש מחובר
-- יכול היה להוסיף לעצמו שורת חברות עם household_id של מישהו אחר,
-- ומאותו רגע is_member מחזירה לו true וכל התנועות, התקציבים, הנכסים
-- והמסמכים של אותו משק בית פתוחים בפניו לקריאה ולכתיבה.
-- מזהה UUID אינו ניחוש סביר, אבל סודיות של מזהה אינה הרשאה.
--
-- מה עכשיו: לטבלת החברות אין בכלל מדיניות INSERT או UPDATE. הדרך
-- היחידה להיכנס למשק בית היא setup_household, שהיא security definer
-- ועוקפת את ה-RLS בכוונה ובמקום אחד בלבד. כך גם כל פונקציית הזמנה
-- שתיכתב בעתיד: היא תהיה definer, ותוכל לאכוף מי מזמין את מי.

-- ───────────────────────────────────────── טבלת החברות ──
drop policy if exists hm_self       on public.household_members;
drop policy if exists hm_read       on public.household_members;
drop policy if exists hm_read_self  on public.household_members;
drop policy if exists hm_read_house on public.household_members;
drop policy if exists hm_leave      on public.household_members;

-- השורה של עצמי נראית תמיד, גם ברגע ההקמה שבו עוד אין משק בית
-- להיות חבר בו, ולכן is_member עוד לא יכולה להחזיר true.
create policy hm_read_self on public.household_members for select to authenticated
  using (user_id = auth.uid());

-- ושורות החברים האחרים, רק במשק בית שאני כבר חבר בו.
create policy hm_read_house on public.household_members for select to authenticated
  using (public.is_member(household_id));

-- לצאת אפשר תמיד, ורק את עצמי. הבעלים אינו יכול לצאת, כי משק בית
-- בלי בעלים הוא נתונים בלי אף אחד שאחראי עליהם · מי שרוצה לצאת
-- מוחק את משק הבית.
create policy hm_leave on public.household_members for delete to authenticated
  using (user_id = auth.uid() and role <> 'owner');

-- חגורה נוספת מעל המדיניות: גם אם מישהו יכתוב מתישהו policy רחבה
-- מדי, בלי ההרשאה הזאת היא לא תוכל להכניס שורה.
revoke insert, update on table public.household_members from authenticated;

-- ────────────────────────────────────────── משק הבית ──
-- קריאה ועדכון לכל חבר, אבל מחיקה רק לבעלים. מחיקת משק בית מוחקת
-- בשרשרת את כל התנועות, התקציבים, הנכסים והמסמכים, וזה לא דבר
-- שבן זוג או יועץ צריכים להיות מסוגלים לעשות לבד.
drop policy if exists hh_rw     on public.households;
drop policy if exists hh_read   on public.households;
drop policy if exists hh_update on public.households;
drop policy if exists hh_delete on public.households;

create policy hh_read on public.households for select to authenticated
  using (public.is_member(id));

create policy hh_update on public.households for update to authenticated
  using (public.is_member(id)) with check (public.is_member(id));

create policy hh_delete on public.households for delete to authenticated
  using (exists (select 1 from public.household_members m
                  where m.household_id = households.id
                    and m.user_id = auth.uid()
                    and m.role = 'owner'));

-- אין policy ל-INSERT. משק בית נוצר רק בתוך setup_household.
revoke insert on table public.households from authenticated;
