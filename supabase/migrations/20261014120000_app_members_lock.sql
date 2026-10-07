-- ‏כמה יש לי · סגירת ההצטרפות העצמית למשק בית
-- ‏להרצה בעורך ה-SQL של Supabase, אחרי app_core. הרצה חוזרת אינה מזיקה.
--
-- ‏מה היה: המדיניות hm_self על household_members הייתה for all, כלומר
-- ‏גם INSERT, והתנאי היחיד שלה היה user_id = auth.uid(). משתמש מחובר
-- ‏יכול היה להוסיף לעצמו שורת חברות עם household_id של מישהו אחר,
-- ‏ומאותו רגע is_member מחזירה לו true וכל התנועות, התקציבים, הנכסים
-- ‏והמסמכים של אותו משק בית פתוחים בפניו לקריאה ולכתיבה.
-- ‏מזהה UUID אינו ניחוש סביר, אבל סודיות של מזהה אינה הרשאה.
--
-- ‏מה עכשיו: לטבלת החברות אין בכלל מדיניות INSERT או UPDATE. הדרך
-- ‏היחידה להיכנס למשק בית היא setup_household, שהיא security definer
-- ‏ועוקפת את ה-RLS בכוונה ובמקום אחד בלבד. כך גם כל פונקציית הזמנה
-- ‏שתיכתב בעתיד: היא תהיה definer, ותוכל לאכוף מי מזמין את מי.

-- ───────────────────────────────────────── טבלת החברות ──
drop policy if exists hm_self       on public.household_members;
drop policy if exists hm_read       on public.household_members;
drop policy if exists hm_read_self  on public.household_members;
drop policy if exists hm_read_house on public.household_members;
drop policy if exists hm_leave      on public.household_members;

-- ‏השורה של עצמי נראית תמיד, גם ברגע ההקמה שבו עוד אין משק בית
-- להיות חבר בו, ולכן is_member עוד לא יכולה להחזיר true.
create policy hm_read_self on public.household_members for select to authenticated
  using (user_id = auth.uid());

-- ‏ושורות החברים האחרים, רק במשק בית שאני כבר חבר בו.
create policy hm_read_house on public.household_members for select to authenticated
  using (public.is_member(household_id));

-- ‏לצאת אפשר תמיד, ורק את עצמי. הבעלים אינו יכול לצאת, כי משק בית
-- בלי בעלים הוא נתונים בלי אף אחד שאחראי עליהם · מי שרוצה לצאת
-- מוחק את משק הבית.
create policy hm_leave on public.household_members for delete to authenticated
  using (user_id = auth.uid() and role <> 'owner');

-- ‏חגורה נוספת מעל המדיניות: גם אם מישהו יכתוב מתישהו policy רחבה
-- מדי, בלי ההרשאה הזאת היא לא תוכל להכניס שורה.
revoke insert, update on table public.household_members from authenticated;

-- ────────────────────────────────────────── משק הבית ──
-- ‏קריאה ועדכון לכל חבר, אבל מחיקה רק לבעלים. מחיקת משק בית מוחקת
-- ‏בשרשרת את כל התנועות, התקציבים, הנכסים והמסמכים, וזה לא דבר
-- ‏שבן זוג או יועץ צריכים להיות מסוגלים לעשות לבד.
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

-- ‏אין policy ל-INSERT. משק בית נוצר רק בתוך setup_household.
revoke insert on table public.households from authenticated;
