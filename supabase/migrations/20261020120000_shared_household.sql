-- ═══════════════════════════════════════════════════════════════
--  אפליקציית התקציב, שלב עשירי: תקציב משותף לשניים
-- ═══════════════════════════════════════════════════════════════
--
-- מה שהיה חסר כדי ששני אנשים ינהלו תקציב אחד:
--
--   1. דרך להצטרף. טבלת החברות שוללת insert מ-authenticated
--      בכוונה, ולכן ההצטרפות חייבת לעבור דרך פונקציה
--      security definer שאוכפת מי מצטרף לאן. זה נכתב במפורש
--      במיגרציה app_members_lock, וזאת הפונקציה שהיא ציפתה לה.
--
--   2. שם של בן הזוג. מדיניות הפרופילים הרשתה לכל אחד לקרוא
--      את עצמו בלבד, ולכן אי אפשר היה להציג "מי הוציא".
--
--   3. צבע לכל אחד. נשמר על החברות ולא על המשתמש, כי הוא
--      שייך לזוג הזה.
--
-- הצבע אינו נגזר ממגדר ואין בשום מקום שדה מגדר. כל אחד בוחר
-- לעצמו מתוך לוח, והשני מקבל ברירת מחדל אחרת. זה מה שעובד
-- לכל שילוב של שני אנשים בלי מקרה קצה.
--
-- להרצה בעורך ה-SQL של Supabase, אחרי app_members_lock.
-- הרצה חוזרת אינה מזיקה.

-- ─────────────────────────────── סוג משק הבית ──
-- אישי או משותף. נקבע בהרשמה, ואפשר לשנות אחר כך.
alter table public.households
  add column if not exists kind text not null default 'solo';

do $$
begin
  alter table public.households drop constraint if exists households_kind_check;
  alter table public.households add constraint households_kind_check
    check (kind in ('solo','shared'));
end $$;

-- ─────────────────────────────── צבע לכל חבר ──
-- מזהה צבע מתוך לוח שיושב בקוד, ולא ערך hex. כך שינוי בלוח
-- אינו מצריך מיגרציה, ולא ניתן לכתוב כאן ערך שישבור את העיצוב.
--
-- ארבעה ולא יותר, וזה נמדד. באפליקציה הזאת לכל צבע כבר יש
-- משמעות: סגול הוא הפעולה, ענבר הוא "שים לב", אדום הוא חריגה,
-- ירוק הוא בשליטה וזהב הוא הרצף. צבע של אדם שמתנגש באחד מהם
-- נקרא כמשמעות ולא כזהות.
--
-- נמדד מול המשטח המגוון: ענבר הוא אפס מעלות מהמשמעות שלו
-- ונפסל. coral הוא שמונה מעלות מענבר וגם 4.44 בלבד, מתחת
-- לסף הקריאות, ונפסל. הארבעה שנשארו רחוקים לפחות ארבעים
-- מעלות זה מזה, וכולם מעל 4.69 על הקרקע.
alter table public.household_members
  add column if not exists color text;

do $$
begin
  alter table public.household_members drop constraint if exists hm_color_check;
  alter table public.household_members add constraint hm_color_check
    check (color is null or color in ('teal','indigo','plum','rose'));
end $$;

-- כל אחד משנה את הצבע של עצמו בלבד. update נשלל מהטבלה כולה
-- במיגרציית הנעילה, ולכן צריך להחזיר אותו בצמצום: רק העמודה
-- הזאת, ורק על השורה של עצמי.
grant update (color) on table public.household_members to authenticated;

drop policy if exists hm_color on public.household_members;
create policy hm_color on public.household_members for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ─────────────────────────────── הפרופיל של השני ──
-- בלי זה אי אפשר להציג שם ליד תנועה. קריאה בלבד, ורק של מי
-- שחבר באותו משק בית.
drop policy if exists pr_read_house on public.profiles;
create policy pr_read_house on public.profiles for select to authenticated
  using (exists (
    select 1
      from public.household_members me
      join public.household_members them
        on them.household_id = me.household_id
     where me.user_id = auth.uid()
       and them.user_id = profiles.user_id
  ));

-- ─────────────────────────────── ההזמנה ──
-- קוד קצר שהמזמין מקריא או שולח. לא אימייל: האפליקציה אינה
-- שולחת דואר, ומנגנון שתלוי במשהו שאינו קיים הוא מנגנון שבור.
create table if not exists public.household_invites(
  code         text primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '14 days',
  used_by      uuid references auth.users(id) on delete set null,
  used_at      timestamptz,

  constraint hi_code_shape check (code ~ '^[A-Z0-9]{6}$')
);

create index if not exists hi_hh_idx on public.household_invites (household_id);

alter table public.household_invites enable row level security;

-- חברי משק הבית רואים ויוצרים את ההזמנות שלו. את ההצטרפות
-- עצמה אי אפשר לעשות דרך הטבלה הזאת, אלא רק דרך הפונקציה:
-- המצטרף עוד אינו חבר, ולכן אינו רואה כאן שורה בכלל.
drop policy if exists hi_rw on public.household_invites;
create policy hi_rw on public.household_invites for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.household_invites from anon;
grant select, insert, delete on table public.household_invites to authenticated;

-- ─────────────────────────────── יצירת קוד ──
-- מוחק הזמנות ישנות של אותו משק בית, כדי שקוד שהוקרא פעם
-- לא יישאר תקף לנצח לצד החדש.
create or replace function public.make_invite()
returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_hh   uuid;
  v_code text;
  i      int := 0;
begin
  if v_user is null then raise exception 'not signed in'; end if;

  select household_id into v_hh from public.household_members
   where user_id = v_user limit 1;
  if v_hh is null then raise exception 'no household'; end if;

  delete from public.household_invites
   where household_id = v_hh and used_by is null;

  -- בלי אותיות ומספרים שמתבלבלים כשמקריאים אותם בקול:
  -- O ו-0, I ו-1.
  loop
    i := i + 1;
    select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                             (floor(random() * 32) + 1)::int, 1), '')
      into v_code from generate_series(1, 6);
    exit when not exists (select 1 from public.household_invites where code = v_code);
    if i > 20 then raise exception 'could not allocate code'; end if;
  end loop;

  insert into public.household_invites (code, household_id, created_by)
  values (v_code, v_hh, v_user);

  -- משק בית שמזמין מישהו הוא משותף, גם לפני שהשני נכנס.
  update public.households set kind = 'shared' where id = v_hh;

  return v_code;
end $$;

revoke all on function public.make_invite() from public, anon;
grant execute on function public.make_invite() to authenticated;

-- ─────────────────────────────── ההצטרפות ──
-- זאת הפונקציה שמיגרציית הנעילה ציפתה לה. היא עוקפת את ה-RLS
-- בכוונה, ולכן כל תנאי כאן הוא תנאי אבטחה ולא נוחות.
create or replace function public.join_household(p_code text)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_inv  public.household_invites%rowtype;
  v_n    int;
begin
  if v_user is null then raise exception 'not signed in'; end if;

  -- מי שכבר במשק בית אינו מצטרף לעוד אחד. מעבר בין משקי בית
  -- היה מנתק אותו מהנתונים שלו בלי שיבין.
  if exists (select 1 from public.household_members where user_id = v_user) then
    raise exception 'already in a household';
  end if;

  select * into v_inv from public.household_invites
   where code = upper(btrim(coalesce(p_code,'')))
   for update;

  if v_inv.code is null        then raise exception 'invite not found'; end if;
  if v_inv.used_by is not null then raise exception 'invite already used'; end if;
  if v_inv.expires_at < now()  then raise exception 'invite expired'; end if;

  -- שניים, ולא יותר. "תקציב משותף" כאן הוא של זוג, וכל מספר
  -- אחר הוא מוצר אחר עם שאלות אחרות.
  select count(*) into v_n from public.household_members
   where household_id = v_inv.household_id;
  if v_n >= 2 then raise exception 'household is full'; end if;

  insert into public.household_members (household_id, user_id, role, color)
  values (v_inv.household_id, v_user, 'partner', 'rose');

  insert into public.profiles (user_id) values (v_user)
  on conflict (user_id) do nothing;

  update public.household_invites
     set used_by = v_user, used_at = now()
   where code = v_inv.code;

  update public.households set kind = 'shared' where id = v_inv.household_id;

  return v_inv.household_id;
end $$;

revoke all on function public.join_household(text) from public, anon;
grant execute on function public.join_household(text) to authenticated;
