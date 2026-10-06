-- ═══════════════════════════════════════════════════════════════
--  אפליקציית התקציב, שלב רביעי: העברות ומטרות
-- ═══════════════════════════════════════════════════════════════
--
-- ‏שני דברים, ושניהם קטנים בכוונה.
--
-- 1. ‏העברה אינה הוצאה.
--
--    ‏כשאדם מעביר אלפיים שקל לחיסכון, הכסף לא יצא מהכיס שלו, הוא
--    עבר לכיס אחר. אפליקציה שסופרת את זה כהוצאה מראה לו שהוא
--    הוציא אלפיים שקל שהוא לא הוציא, ואז המספר הגדול במסך הבית,
--    שהוא כל האפליקציה, פשוט שקר.
--
--    ‏זה מתגלה דווקא בייבוא: דף עו"ש מלא בהעברות כאלה, ובלי העמודה
--    הזאת כל אחת מהן נכנסת כהוצאה.
--
--    ‏עמודה אחת ולא טבלת חשבונות. טבלת חשבונות נוגעת בכל שאילתה
--    באפליקציה, והיא לא נדרשת כדי לפתור את הבעיה הזאת.
--
-- 2. ‏מטרת חיסכון.
--
--    ‏סכום, תאריך יעד, וכמה כבר נצבר. בלי ריבית ובלי תחזיות: מי
--    שרוצה את אלה צריך יועץ, לא אפליקציה.
--
-- להרצה בעורך ה-SQL של Supabase, אחרי שלושת הקבצים שלפניו.
-- הרצה חוזרת אינה מזיקה.

-- ───────────────────────────────────────────── העברות ──
alter table public.transactions
  add column if not exists is_transfer boolean not null default false;

-- ‏אינדקס חלקי: ההעברות הן מיעוט קטן מהשורות, ומה שהשאילתות
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
  -- ‏יעד בעבר הוא כמעט תמיד טעות הקלדה בשנה, והוא הופך כל חישוב
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
