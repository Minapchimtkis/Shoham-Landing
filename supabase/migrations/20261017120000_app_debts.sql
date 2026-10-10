-- ═══════════════════════════════════════════════════════════════
--  אפליקציית התקציב, שלב שביעי: החובות וההתחייבויות
-- ═══════════════════════════════════════════════════════════════
--
-- עד היום חוב יכול היה להיכתב רק בשתי דרכים, ושתיהן חלקיות:
-- כקטגוריית הוצאה בשם "החזרים", שמראה כמה יוצא בחודש אבל לא
-- כמה נשאר לשלם, או כשדה liability על נכס, שקיים רק לנדל"ן.
-- מינוס, הלוואה אישית וחוב בכרטיס לא יכלו להיכתב בכלל.
--
-- הטבלה הזאת עונה על שתי שאלות שאין להן היום תשובה: כמה אני
-- חייב בסך הכל, וכמה מזה יוצא לי כל חודש.
--
-- הריבית נשמרת בנקודות בסיס ולא כמספר עשרוני, מאותה סיבה שכסף
-- נשמר באגורות: 5.25 אחוז הם 525, והחשבון נשאר מדויק. היא
-- אופציונלית, כי רוב האנשים אינם זוכרים אותה ואסור שזה יעצור
-- אותם מלרשום את החוב עצמו.
--
-- משכנתא יכולה להיכתב כאן וגם כהתחייבות על הדירה. השווי הפיננסי
-- מחשב את שתיהן, ולכן כפילות היא טעות אמיתית · האפליקציה מזהה
-- את המצב הזה ואומרת אותו למשתמש במסך, במקום לתקן בשקט מאחורי
-- הגב שלו ולהציג מספר שהוא לא מבין מאיפה הגיע.
--
-- אין כאן שום המלצה. לא "כדאי לסגור קודם", לא דירוג בין סוגי
-- חוב, ולא תחזית. זה כלי מיפוי, כמו מסך הנכסים.
--
-- להרצה בעורך ה-SQL של Supabase. הרצה חוזרת אינה מזיקה.

create table if not exists public.debts(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,

  kind text not null check (kind in (
    'mortgage',      -- משכנתא
    'loan',          -- הלוואה
    'overdraft',     -- מינוס בעובר ושב
    'credit',        -- חוב בכרטיס אשראי
    'other'
  )),

  name text not null,

  -- כמה נשאר לשלם, ולא כמה נלקח. זה המספר שהמשתמש רואה בדוח
  -- היתרות, והוא גם היחיד שמשפיע על השווי הפיננסי.
  balance_agorot bigint not null default 0 check (balance_agorot >= 0),

  -- ההחזר החודשי. הוא אינו נגזר מהיתרה · הלוואת בלון מחזירה
  -- אפס בחודש ויתרתה מלאה, וחישוב אוטומטי היה משקר בדיוק שם.
  monthly_agorot bigint not null default 0 check (monthly_agorot >= 0),

  -- ריבית שנתית בנקודות בסיס. 5.25 אחוז = 525. אופציונלית.
  rate_bp integer check (rate_bp is null or (rate_bp between 0 and 10000)),

  -- מתי זה נגמר. אופציונלי.
  ends_on date,

  note     text,
  archived boolean not null default false,

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint debts_name_len check (length(btrim(name)) between 1 and 60),
  constraint debts_note_len check (note is null or length(note) <= 300),
  constraint debts_date_sane check (ends_on is null or ends_on >= date '2000-01-01')
);

create index if not exists debts_hh_idx on public.debts (household_id, archived, kind);

alter table public.debts enable row level security;
drop policy if exists debt_rw on public.debts;
create policy debt_rw on public.debts for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.debts from anon;
grant select, insert, update, delete on table public.debts to authenticated;


-- ─────────────────────────────── קרן כספית ──
-- הסוג היחיד שחסר ברשימת הנכסים שביקש שוהם. אין דרך להוסיף ערך
-- לאילוץ check קיים, ולכן מפילים ובונים מחדש.
--
-- האילוץ המקורי נכתב בתוך הגדרת העמודה ולכן הוא ללא שם מפורש
-- ו-Postgres נתן לו שם משלו. במקום לנחש אותו, מחפשים את האילוץ
-- שמזכיר bank_savings · כך זה עובד גם אם מישהו שינה שם בדרך.
do $$
declare c text;
begin
  select conname into c
    from pg_constraint
   where conrelid = 'public.assets'::regclass
     and contype  = 'c'
     and pg_get_constraintdef(oid) like '%bank_savings%'
   limit 1;
  if c is not null then
    execute format('alter table public.assets drop constraint %I', c);
  end if;
end $$;

alter table public.assets drop constraint if exists assets_kind_allowed;
alter table public.assets add constraint assets_kind_allowed
  check (kind in (
    'bank_savings','deposit','cash','money_market',
    'portfolio','crypto','mutual_fund',
    'study_fund','provident','pension',
    'realestate','other'
  ));
