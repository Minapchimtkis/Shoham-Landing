-- מי מגיע לסרטון, מי לוחץ עליו, וכמה מזה הוא רואה.
--
-- הדף מדד עד היום עד כמה גללו בו, וזה כל מה שהיה. הסרטון הוא הדבר
-- היקר ביותר בעמוד, שישה וחצי מגה ופנים וקול, ולא הייתה שום דרך
-- לדעת אם מישהו בכלל לוחץ עליו.
--
-- אותה צורה בדיוק כמו page_funnel, ובכוונה: שורה אחת לכל ביקור,
-- שמחזיקה את הנקודה הרחוקה ביותר שאותו ביקור הגיע אליה. בלי שם,
-- בלי טלפון, בלי עוגייה, ובלי שום מזהה ששורד סגירת לשונית.
--
-- והעיקר: זה אותו p_visit של page_funnel. אותו מזהה אקראי שהדף
-- ממציא לכל טעינה ושוכח. לכן אפשר לחבר בין השתיים ולענות על
-- השאלה שבגללה כל זה נבנה, האם מי שצפה משאיר פרטים יותר ממי
-- שלא, בלי להוסיף שום מזהה חדש ובלי עוגייה אחת.
--
-- להרצה בעורך ה-SQL של Supabase. הרצה חוזרת אינה מזיקה.

create table if not exists public.video_funnel(
  visit       uuid        not null,
  video       text        not null default 'intro',
  reached     boolean     not null default false,  -- הסרטון נכנס למסך
  played      boolean     not null default false,  -- נלחץ נגן
  max_percent integer     not null default 0,      -- 25 / 50 / 75 / 100
  seconds     integer     not null default 0,      -- כמה שניות נצפו בפועל
  lang        text,
  device      text,
  ref         text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (visit, video)
);

create index if not exists video_funnel_created_idx on public.video_funnel (created_at desc);
create index if not exists video_funnel_played_idx  on public.video_funnel (video, played);

alter table public.video_funnel enable row level security;
drop policy if exists video_funnel_read   on public.video_funnel;
drop policy if exists video_funnel_delete on public.video_funnel;
create policy video_funnel_read   on public.video_funnel for select to authenticated using (true);
create policy video_funnel_delete on public.video_funnel for delete to authenticated using (true);
revoke all on table public.video_funnel from anon;
grant select, delete on table public.video_funnel to authenticated;

-- ------------------------------------------------------------- the writer --
-- anon יכול לקרוא לזה ולא לשום דבר אחר. הפונקציה לא מחזירה שורה
-- החוצה, ולכן המפתח הציבורי שבדף נשאר בדיוק כפי שהוא היום.
--
-- שום דבר כאן לא יורד. אחוז נמוך שמגיע באיחור על קו איטי לא מוחק
-- אחוז גבוה שכבר נרשם, ולחיצה על נגן לא מתבטלת.
create or replace function public.video_watch(
  p_visit   uuid,
  p_video   text    default 'intro',
  p_reached boolean default false,
  p_played  boolean default false,
  p_percent integer default 0,
  p_seconds integer default 0,
  p_lang    text    default null,
  p_device  text    default null,
  p_ref     text    default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_hour  integer;
  v_ref   text;
  v_video text;
begin
  if p_visit is null then
    return jsonb_build_object('ok', false);
  end if;

  v_video := left(coalesce(nullif(btrim(p_video),''),'intro'), 20);

  -- הדף שולח מארח ותו לא. גם כאן זה מצומצם שוב למארח, כדי שכתובת
  -- מלאה לא תוכל לנחות בטבלה בטעות.
  v_ref := lower(btrim(coalesce(p_ref, '')));
  v_ref := regexp_replace(v_ref, '^[a-z][a-z0-9+.\-]*://', '');
  v_ref := regexp_replace(v_ref, '[/?#:].*$', '');
  v_ref := regexp_replace(v_ref, '^www\.', '');
  if v_ref !~ '^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$'
    then v_ref := null; end if;
  v_ref := left(v_ref, 60);

  -- תקרה על ביקורים חדשים בשעה, כדי שסקריפט לא ימלא את הטבלה.
  -- עדכונים לביקור שכבר נרשם ממשיכים לעבוד מעבר לה, כך שמי שבאמת
  -- צופה לא נקטע באמצע.
  if not exists (select 1 from public.video_funnel where visit = p_visit and video = v_video) then
    select count(*) into v_hour from public.video_funnel
     where created_at > now() - interval '1 hour';
    if v_hour >= 1000 then
      return jsonb_build_object('ok', false, 'reason', 'busy');
    end if;
  end if;

  insert into public.video_funnel (visit, video, reached, played, max_percent, seconds, lang, device, ref)
  values (
    p_visit,
    v_video,
    coalesce(p_reached, false),
    coalesce(p_played,  false),
    least(greatest(coalesce(p_percent, 0), 0), 100),
    least(greatest(coalesce(p_seconds, 0), 0), 86400),
    left(coalesce(p_lang,''), 5),
    left(coalesce(p_device,''), 10),
    v_ref
  )
  on conflict (visit, video) do update
    set reached     = public.video_funnel.reached or excluded.reached,
        played      = public.video_funnel.played  or excluded.played,
        max_percent = greatest(excluded.max_percent, public.video_funnel.max_percent),
        seconds     = greatest(excluded.seconds,     public.video_funnel.seconds),
        -- אלה נקבעים בקריאה הראשונה, וקריאה מאוחרת לא תרוקן אותם
        lang        = coalesce(nullif(excluded.lang,''),   public.video_funnel.lang),
        device      = coalesce(nullif(excluded.device,''), public.video_funnel.device),
        ref         = coalesce(public.video_funnel.ref,    excluded.ref),
        updated_at  = now();

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.video_watch(uuid,text,boolean,boolean,integer,integer,text,text,text) from public;
grant execute on function public.video_watch(uuid,text,boolean,boolean,integer,integer,text,text,text) to anon, authenticated;

-- ------------------------------------------------------------- the reader --
-- שורה אחת עם כל מה שהדשבורד צריך להציג, כולל ההשוואה שבגללה בנינו
-- את זה: אחוז ההמרה של מי שצפה מול מי שלא.
--
-- "צפה" הוא ביקור שלחץ נגן. "לא צפה" הוא ביקור שנרשם ב-page_funnel
-- ולא לחץ. ההמרה עצמה נלקחת מ-page_funnel, שם היא כבר נרשמת.
create or replace function public.video_funnel_summary(
  p_from  timestamptz default null,
  p_to    timestamptz default null,
  p_video text        default 'intro'
) returns table(
  reached              bigint,
  played               bigint,
  pct25                bigint,
  pct50                bigint,
  pct75                bigint,
  completed            bigint,
  median_seconds       integer,
  watchers             bigint,
  watchers_converted   bigint,
  others               bigint,
  others_converted     bigint
)
language sql
security invoker
stable
set search_path = public, pg_temp
as $$
  with v as (
    select * from public.video_funnel f
     where f.video = coalesce(p_video, 'intro')
       and (p_from is null or f.created_at >= p_from)
       and (p_to   is null or f.created_at <  p_to)
  ),
  p as (
    select * from public.page_funnel g
     where g.page = 'landing'
       and (p_from is null or g.created_at >= p_from)
       and (p_to   is null or g.created_at <  p_to)
  )
  select
    count(*) filter (where v.reached)                      ::bigint,
    count(*) filter (where v.played)                       ::bigint,
    count(*) filter (where v.max_percent >= 25)            ::bigint,
    count(*) filter (where v.max_percent >= 50)            ::bigint,
    count(*) filter (where v.max_percent >= 75)            ::bigint,
    count(*) filter (where v.max_percent >= 100)           ::bigint,
    coalesce(percentile_disc(0.5) within group (
      order by v.seconds) filter (where v.played), 0)::integer,
    (select count(*) from p where exists (
       select 1 from v where v.visit = p.visit and v.played))::bigint,
    (select count(*) from p where p.converted and exists (
       select 1 from v where v.visit = p.visit and v.played))::bigint,
    (select count(*) from p where not exists (
       select 1 from v where v.visit = p.visit and v.played))::bigint,
    (select count(*) from p where p.converted and not exists (
       select 1 from v where v.visit = p.visit and v.played))::bigint
  from v
$$;

revoke all on function public.video_funnel_summary(timestamptz,timestamptz,text) from public;
grant execute on function public.video_funnel_summary(timestamptz,timestamptz,text) to authenticated;
