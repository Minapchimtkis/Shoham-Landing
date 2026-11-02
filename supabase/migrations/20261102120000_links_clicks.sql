-- דף הקישורים · מי לוחץ על מה
--
-- הדף יושב בביו באינסטגרם ויש בו שלוש אפשרויות: וואטסאפ, דף
-- הנחיתה, והמחשבון. בלי מדידה אי אפשר לדעת אם אנשים הולכים
-- לדבר או ללמוד, ולכן אי אפשר לדעת מה צריך לשבת ראשון.
--
-- אותו קו בדיוק כמו page_funnel ו-call_clicks, ובכוונה: בלי שם,
-- בלי טלפון, בלי כתובת, בלי עוגייה, ובלי מזהה ששורד סגירת
-- לשונית. הדף ממציא מזהה אקראי לכל ביקור ושוכח אותו. מה שכן
-- נשמר הוא רק מה שמשנה את משמעות המספר: מאיזה אתר הגיעו ברמת
-- שם האתר בלבד, וטלפון או מחשב.
--
-- שורה אחת לכל ביקור לכל יעד. מי שלחץ על אותו כפתור שלוש פעמים
-- הוא אדם אחד שהחליט, לא שלוש החלטות · אינדקס ייחודי אוכף את
-- זה במסד ולא בדפדפן.
--
-- להריץ בעורך ה-SQL של סופאבייס. הרצה חוזרת אינה מזיקה.

create table if not exists public.links_clicks(
  id         uuid primary key default gen_random_uuid(),
  -- open הוא פתיחת הדף · כל השאר הם לחיצה על כפתור, וכך אפשר
  -- לדעת מה האחוז ולא רק את המספר.
  target     text        not null,
  visit      uuid,
  ref        text,
  device     text,
  created_at timestamptz not null default now(),
  constraint links_clicks_target_ck
    check (target in ('open','whatsapp','landing','calculator'))
);

create unique index if not exists links_clicks_visit_target_idx
  on public.links_clicks (visit, target) where visit is not null;
create index if not exists links_clicks_created_idx on public.links_clicks (created_at desc);
create index if not exists links_clicks_target_idx  on public.links_clicks (target, created_at desc);

alter table public.links_clicks enable row level security;
drop policy if exists links_clicks_read   on public.links_clicks;
drop policy if exists links_clicks_delete on public.links_clicks;
create policy links_clicks_read   on public.links_clicks for select to authenticated using (true);
create policy links_clicks_delete on public.links_clicks for delete to authenticated using (true);
revoke all on table public.links_clicks from anon;
grant select, delete on table public.links_clicks to authenticated;

-- ------------------------------------------------------------ הדרך פנימה --
-- אנונימי יכול לקרוא לזה ולשום דבר אחר. הפונקציה אינה מחזירה
-- שורה, ולכן המפתח הפומבי שיושב בדף נשאר חסר ערך למי שימצא אותו.
create or replace function public.links_click(
  p_target text,
  p_visit  uuid default null,
  p_ref    text default null,
  p_device text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_hour integer;
begin
  if p_target is null or p_target not in ('open','whatsapp','landing','calculator') then
    return jsonb_build_object('ok', false, 'reason', 'target');
  end if;

  -- תקרה על הטבלה עצמה, כדי שסקריפט לא ימלא אותה בלחיצות.
  select count(*) into v_hour from public.links_clicks
   where created_at > now() - interval '1 hour';
  if v_hour >= 1000 then
    return jsonb_build_object('ok', false, 'reason', 'busy');
  end if;

  insert into public.links_clicks (target, visit, ref, device)
  values (p_target, p_visit,
          nullif(left(btrim(coalesce(p_ref, '')), 120), ''),
          case when p_device in ('mobile','desktop') then p_device end)
  on conflict do nothing;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.links_click(text,uuid,text,text) from public;
grant execute on function public.links_click(text,uuid,text,text) to anon, authenticated;

-- ----------------------------------------------------------- הדרך החוצה --
-- הלוח שואל שאלה אחת ומקבל שורה אחת לכל יעד, במקום למשוך את כל
-- הטבלה ולספור בדפדפן. רק מחובר יכול לקרוא לזה.
create or replace function public.links_click_counts(
  p_from timestamptz default null,
  p_to   timestamptz default null
) returns table(target text, visits bigint)
language sql security definer set search_path = public, pg_temp as $$
  select c.target, count(*)::bigint
    from public.links_clicks c
   where (p_from is null or c.created_at >= p_from)
     and (p_to   is null or c.created_at <= p_to)
   group by c.target
$$;

revoke all on function public.links_click_counts(timestamptz,timestamptz) from public;
grant execute on function public.links_click_counts(timestamptz,timestamptz) to authenticated;

-- מאיפה הגיעו, לאותו טווח. אותו היגיון, שאילתה נפרדת, כדי
-- שהלוח לא יצטרך להצליב שתי טבלאות בדפדפן.
create or replace function public.links_click_sources(
  p_from timestamptz default null,
  p_to   timestamptz default null
) returns table(ref text, visits bigint, clicks bigint)
language sql security definer set search_path = public, pg_temp as $$
  select coalesce(c.ref, '') as ref,
         count(*) filter (where c.target = 'open')::bigint,
         count(*) filter (where c.target <> 'open')::bigint
    from public.links_clicks c
   where (p_from is null or c.created_at >= p_from)
     and (p_to   is null or c.created_at <= p_to)
   group by 1
   order by 2 desc
$$;

revoke all on function public.links_click_sources(timestamptz,timestamptz) from public;
grant execute on function public.links_click_sources(timestamptz,timestamptz) to authenticated;

notify pgrst, 'reload schema';

-- מה זה עשה, כדי שתראה שזה עבד:
--   select target, count(*) from public.links_clicks group by 1 order by 2 desc;
--   select * from public.links_click_counts();
