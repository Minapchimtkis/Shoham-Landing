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
