-- ═══════════════════════════════════════════════════════════════
--  אפליקציית התקציב, שלב תשיעי: הייבוא לומד
-- ═══════════════════════════════════════════════════════════════
--
-- הייבוא מזהה היום קטגוריה לפי טבלת מילים קבועה, כמאה וחמישים
-- בתי עסק ישראליים. היא עובדת טוב, ויש לה חיסרון אחד שמבטל
-- חלק גדול מהערך שלה: היא לא זוכרת כלום.
--
-- מי שמתקן "ארומה" ממזון לאוכל בחוץ מקבל את אותה טעות בחודש
-- הבא, ובחודש שאחריו. על פני שנה זה אותם עשרים תיקונים שתים
-- עשרה פעמים.
--
-- הטבלה הזאת זוכרת. כל תיקון במסך האישור נשמר, ובייבוא הבא
-- הוא מנצח את טבלת המילים.
--
-- המפתח הוא המילה הראשונה בתיאור, ולא התיאור המלא. נמדד על
-- עשרים ושבעה תיאורים אמיתיים מדפי אשראי: תיאור מלא נתן עשרים
-- ושבעה מפתחות שונים, כלומר אפס למידה. המילה הראשונה נתנה
-- שמונה עשרה, בלי אף התנגשות · "שופרסל שלי רמת גן" ו"שופרסל
-- דיל חולון" הם אותו בית עסק, והמשתמש מתקן אותו פעם אחת.
--
-- מילה ראשונה שאינה מזהה עסק בפני עצמה ("חברת", "עיריית",
-- "מי") לוקחת איתה את השנייה, ולכן "חברת חשמל" ו"מי אביבים"
-- נשארים מובחנים. הרשימה עצמה יושבת בקוד ולא כאן.
--
-- להרצה בעורך ה-SQL של Supabase. הרצה חוזרת אינה מזיקה.

create table if not exists public.merchant_rules(
  household_id uuid not null references public.households(id) on delete cascade,

  -- המפתח, כפי שחושב בקוד. מנורמל: בלי ספרות, בלי סימני פיסוק
  -- ובאותיות קטנות.
  merchant text not null,

  -- לאן הוא שייך. אחד משניים: קטגוריה, או סימון שזאת העברה
  -- ולא הוצאה כלל.
  category_id uuid references public.categories(id) on delete cascade,
  is_move     boolean not null default false,

  -- כמה פעמים הכלל הזה אושר. לא בשימוש היום, והוא זול לשמור
  -- ויקר להוסיף אחר כך.
  hits integer not null default 1 check (hits >= 0),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  primary key (household_id, merchant),

  constraint merchant_rules_len check (length(btrim(merchant)) between 1 and 80),
  -- כלל חייב להצביע לאנשהו: או לקטגוריה, או להעברה.
  constraint merchant_rules_target check (is_move or category_id is not null)
);

create index if not exists merchant_rules_hh_idx
  on public.merchant_rules (household_id);

alter table public.merchant_rules enable row level security;
drop policy if exists mrule_rw on public.merchant_rules;
create policy mrule_rw on public.merchant_rules for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

-- אבטחת השורות קובעת מי רואה מה, אבל בלי ההרשאה הזאת איש אינו
-- מגיע לטבלה בכלל דרך ה-API.
revoke all on table public.merchant_rules from anon;
grant select, insert, update, delete on table public.merchant_rules to authenticated;
