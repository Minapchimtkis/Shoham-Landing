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
