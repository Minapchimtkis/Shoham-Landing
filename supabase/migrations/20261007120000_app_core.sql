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
