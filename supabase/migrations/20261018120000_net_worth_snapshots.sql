-- ‏תצלומי הון עצמי
-- ‏להרצה בעורך ה-SQL של Supabase. הרצה חוזרת אינה מזיקה.
--
-- ‏טבלת assets מחזיקה את הסכום הנוכחי בלבד, ו-debts את היתרה
-- ‏הנוכחית בלבד. כשאדם מעדכן את הפנסיה מ-200,000 ל-210,000,
-- ‏המספר הקודם נמחק ואין לאן לחזור. לכן אי אפשר לצייר הון עצמי
-- ‏לאחור · הנתון פשוט אינו קיים.
--
-- ‏הטבלה הזאת מתחילה לצבור אותו מהיום. שורה אחת לחודש למשק בית,
-- ‏והיא נכתבת מחדש בכל פתיחה של האפליקציה באותו חודש · כך
-- ‏התצלום של החודש הנוכחי תמיד עדכני, והתצלומים של החודשים
-- ‏שעברו קפואים כפי שהיו.
--
-- ‏ההון העצמי עצמו אינו נשמר אלא מחושב. ערך שמור ששלושה מספרים
-- ‏אחרים אמורים להסביר אותו הוא ערך שיסתור אותם ביום שבו מישהו
-- ‏יעדכן רק אחד מהם.

create table if not exists public.net_worth_snapshots(
  household_id uuid not null references public.households(id) on delete cascade,

  -- ‏תמיד ה-1 בחודש, כמו budgets. נקודה אחת לחודש היא הרזולוציה
  -- ‏שאדם באמת מסתכל עליה, ויומית הייתה יוצרת רעש בלי מידע.
  as_of date not null,

  assets_agorot      bigint not null default 0 check (assets_agorot >= 0),
  -- ‏ההתחייבויות שרובצות על נכסים · משכנתא על דירה
  liabilities_agorot bigint not null default 0 check (liabilities_agorot >= 0),
  -- ‏החובות העומדים בפני עצמם · הלוואה, מינוס, אשראי
  debts_agorot       bigint not null default 0 check (debts_agorot >= 0),

  net_agorot bigint generated always as
    (assets_agorot - liabilities_agorot - debts_agorot) stored,

  updated_at timestamptz not null default now(),

  primary key (household_id, as_of),
  constraint nws_first_of_month check (extract(day from as_of) = 1),
  -- ‏תצלום בעתיד אינו תצלום. בלי זה שעון מוטעה בטלפון היה פותח
  -- ‏נקודה בעוד שנה ומותח את כל הגרף.
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

-- ‏אבטחת השורות קובעת מי רואה מה, אבל בלי ההרשאה הזאת איש אינו
-- ‏מגיע לטבלה בכלל דרך ה-API. שאר הטבלאות באפליקציה מעניקות
-- ‏אותה במפורש, וגם זאת.
grant select, insert, update, delete on table public.net_worth_snapshots to authenticated;
