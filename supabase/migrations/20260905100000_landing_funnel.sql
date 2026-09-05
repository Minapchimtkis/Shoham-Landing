-- How far people get down the landing page before they leave.
--
-- The questionnaire has had this since the beginning: quiz_funnel says which
-- question loses people. The landing page itself has had nothing. Twelve
-- screens on a phone, one place to leave details near the bottom, and no way
-- to tell whether anyone reaches it or whether they all leave at the second
-- section.
--
-- Same shape as quiz_funnel, on purpose: one row per visit holding the
-- deepest point that visit reached. No name, no phone, no address, no cookie
-- and no id that survives the tab closing — the page makes up a random id per
-- load and forgets it. The only extras kept are things that change what the
-- number means: which language the page was in, phone or desktop, and the
-- host that sent them (instagram.com, google.com), never the full address.
--
-- Run in the Supabase SQL editor. Re-running is harmless.

create table if not exists public.page_funnel(
  visit       uuid primary key,
  page        text        not null default 'landing',
  stage       text        not null,
  stage_index integer     not null,
  lang        text,
  device      text,
  ref         text,
  converted   boolean     not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists page_funnel_created_idx on public.page_funnel (created_at desc);
create index if not exists page_funnel_stage_idx   on public.page_funnel (stage_index);

alter table public.page_funnel enable row level security;
drop policy if exists page_funnel_read   on public.page_funnel;
drop policy if exists page_funnel_delete on public.page_funnel;
create policy page_funnel_read   on public.page_funnel for select to authenticated using (true);
create policy page_funnel_delete on public.page_funnel for delete to authenticated using (true);
revoke all on table public.page_funnel from anon;
grant select, delete on table public.page_funnel to authenticated;

-- ------------------------------------------------------------- the writer --
-- Anon can call this and nothing else. It cannot read a row back out, so the
-- publishable key in the page stays as harmless as it is today.
--
-- Scrolling back up never lowers what was recorded, and neither does a stage
-- arriving out of order over a slow line.
create or replace function public.page_stage(
  p_visit     uuid,
  p_stage     text,
  p_index     integer,
  p_page      text    default 'landing',
  p_lang      text    default null,
  p_device    text    default null,
  p_ref       text    default null,
  p_converted boolean default false
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_hour integer;
  v_ref  text;
begin
  if p_visit is null or coalesce(btrim(p_stage),'') = '' or p_index is null then
    return jsonb_build_object('ok', false);
  end if;

  -- The page sends the host and nothing else. This reduces it to the host a
  -- second time anyway, so a full address can never land in the table by
  -- accident: scheme off, everything from the first slash or colon off, www.
  -- off, and anything that is then not shaped like a host thrown away.
  v_ref := lower(btrim(coalesce(p_ref, '')));
  v_ref := regexp_replace(v_ref, '^[a-z][a-z0-9+.\-]*://', '');
  v_ref := regexp_replace(v_ref, '[/?#:].*$', '');
  v_ref := regexp_replace(v_ref, '^www\.', '');
  -- a real host has at least one dot in it; anything else is not one
  if v_ref !~ '^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$'
    then v_ref := null; end if;
  v_ref := left(v_ref, 60);

  -- A ceiling on fresh visits per hour so a script cannot fill the table.
  -- Steps for visits already recorded keep working past it, so nobody who is
  -- genuinely reading the page is cut off halfway.
  if not exists (select 1 from public.page_funnel where visit = p_visit) then
    select count(*) into v_hour from public.page_funnel
     where created_at > now() - interval '1 hour';
    if v_hour >= 1000 then
      return jsonb_build_object('ok', false, 'reason', 'busy');
    end if;
  end if;

  insert into public.page_funnel (visit, page, stage, stage_index, lang, device, ref, converted)
  values (
    p_visit,
    left(coalesce(nullif(btrim(p_page),''),'landing'), 20),
    left(btrim(p_stage), 40),
    p_index,
    left(coalesce(p_lang,''), 5),
    left(coalesce(p_device,''), 10),
    v_ref,
    coalesce(p_converted, false)
  )
  on conflict (visit) do update
    set stage       = case when excluded.stage_index > public.page_funnel.stage_index
                           then excluded.stage else public.page_funnel.stage end,
        stage_index = greatest(excluded.stage_index, public.page_funnel.stage_index),
        -- these are settled on the first call; later ones must not blank them
        lang        = coalesce(nullif(excluded.lang,''),   public.page_funnel.lang),
        device      = coalesce(nullif(excluded.device,''), public.page_funnel.device),
        ref         = coalesce(public.page_funnel.ref,     excluded.ref),
        converted   = public.page_funnel.converted or excluded.converted,
        updated_at  = now();

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.page_stage(uuid,text,integer,text,text,text,text,boolean) from public;
grant execute on function public.page_stage(uuid,text,integer,text,text,text,text,boolean) to anon, authenticated;

-- ------------------------------------------------------------- the reader --
-- The dashboard wants one thing from a table that grows with every visit:
-- how many visits reached each stage in the chosen range. That is a dozen
-- rows however large the table gets, so the range goes down with the query
-- instead of the table coming up.
create or replace function public.page_funnel_counts(
  p_from timestamptz default null,
  p_to   timestamptz default null,
  p_page text        default 'landing'
) returns table(stage_index integer, visits bigint)
language sql
security invoker
stable
set search_path = public, pg_temp
as $$
  select f.stage_index, count(*)::bigint
    from public.page_funnel f
   where f.page = coalesce(p_page, 'landing')
     and (p_from is null or f.created_at >= p_from)
     and (p_to   is null or f.created_at <  p_to)
   group by f.stage_index
$$;

revoke all on function public.page_funnel_counts(timestamptz,timestamptz,text) from public;
revoke all on function public.page_funnel_counts(timestamptz,timestamptz,text) from anon;
grant execute on function public.page_funnel_counts(timestamptz,timestamptz,text) to authenticated;

-- Where they came from, and whether that source is worth anything. A source
-- that sends forty people and no details is a different problem from one that
-- sends four and closes two.
create or replace function public.page_sources(
  p_from timestamptz default null,
  p_to   timestamptz default null,
  p_page text        default 'landing'
) returns table(ref text, visits bigint, reached_form bigint, converted bigint)
language sql
security invoker
stable
set search_path = public, pg_temp
as $$
  select coalesce(f.ref, '') as ref,
         count(*)::bigint,
         count(*) filter (where f.stage_index >= 9)::bigint,
         count(*) filter (where f.converted)::bigint
    from public.page_funnel f
   where f.page = coalesce(p_page, 'landing')
     and (p_from is null or f.created_at >= p_from)
     and (p_to   is null or f.created_at <  p_to)
   group by 1
   order by 2 desc
$$;

revoke all on function public.page_sources(timestamptz,timestamptz,text) from public;
revoke all on function public.page_sources(timestamptz,timestamptz,text) from anon;
grant execute on function public.page_sources(timestamptz,timestamptz,text) to authenticated;

notify pgrst, 'reload schema';

-- Nothing here needs pruning to work, but the table only ever grows. When it
-- gets large, a year is more history than the panel ever shows:
--   delete from public.page_funnel where created_at < now() - interval '1 year';
