-- Keep the dashboard's load flat as the data grows.
--
-- Two tables grow with traffic rather than with customers: quiz_funnel gets a
-- row for every visit to the questionnaire, and wa_clicks a row for every tap
-- on the WhatsApp button. The dashboard was downloading every one of those
-- rows, every refresh, only to count them in the browser. A year of ordinary
-- traffic turns that into a slow page for numbers that fit on one line.
--
-- These two do the counting in the database, so what crosses the wire stays
-- the same size forever. The dashboard falls back to reading the tables
-- directly if this file has not been run yet, so nothing breaks in between.
--
-- Run in the Supabase SQL editor. Re-running is harmless.

-- The funnel panel only ever asks: how many visits reached at least stage N,
-- inside the chosen date range. That is a handful of rows, not thousands.
create or replace function public.quiz_funnel_counts(
  p_from timestamptz default null,
  p_to   timestamptz default null
) returns table(stage_index integer, visits integer)
language sql
stable
security invoker          -- so the caller's row-level security still applies
set search_path = public, pg_temp
as $$
  select f.stage_index, count(*)::integer
    from public.quiz_funnel f
   where (p_from is null or f.created_at >= p_from)
     and (p_to   is null or f.created_at <= p_to)
   group by f.stage_index
$$;

revoke all on function public.quiz_funnel_counts(timestamptz, timestamptz) from public;
revoke all on function public.quiz_funnel_counts(timestamptz, timestamptz) from anon;
grant execute on function public.quiz_funnel_counts(timestamptz, timestamptz) to authenticated;

-- Per lead the dashboard shows how many times they went out to WhatsApp and
-- when the last time was. Both are one row per lead, whatever the traffic.
drop view if exists public.wa_clicks_summary;
create view public.wa_clicks_summary
with (security_invoker = on)
as
  select c.lead_id,
         count(*)::integer as clicks,
         max(c.created_at) as last_at
    from public.wa_clicks c
   group by c.lead_id;

revoke all on public.wa_clicks_summary from anon;
grant select on public.wa_clicks_summary to authenticated;

-- PostgREST caches the shape of the schema; without this the new function and
-- view stay invisible to the dashboard until the API restarts on its own.
notify pgrst, 'reload schema';
