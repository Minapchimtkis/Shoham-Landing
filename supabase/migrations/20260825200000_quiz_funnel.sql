-- How far people get into the quiz before they leave.
--
-- Someone who starts and gives up currently leaves nothing behind, so there
-- is no way to tell a questionnaire that works from one that loses everyone
-- at the third question. This records the furthest point of each visit and
-- nothing else: no name, no phone, no address — just a random id for the
-- visit so a person is counted once rather than at every step.
--
-- Run in the Supabase SQL editor. Re-running is harmless.

create table if not exists public.quiz_funnel(
  visit       uuid primary key,
  stage       text        not null,
  stage_index integer     not null,
  track       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists quiz_funnel_created_idx on public.quiz_funnel (created_at desc);
create index if not exists quiz_funnel_stage_idx   on public.quiz_funnel (stage_index);

alter table public.quiz_funnel enable row level security;
drop policy if exists quiz_funnel_read   on public.quiz_funnel;
drop policy if exists quiz_funnel_delete on public.quiz_funnel;
create policy quiz_funnel_read   on public.quiz_funnel for select to authenticated using (true);
create policy quiz_funnel_delete on public.quiz_funnel for delete to authenticated using (true);
revoke all on table public.quiz_funnel from anon;
grant select, delete on table public.quiz_funnel to authenticated;

-- One row per visit, always holding the deepest point reached. A step that
-- goes backwards — someone using the back button — never overwrites it.
create or replace function public.quiz_stage(
  p_visit uuid,
  p_stage text,
  p_index integer,
  p_track text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_hour integer;
begin
  if p_visit is null or coalesce(btrim(p_stage),'') = '' or p_index is null then
    return jsonb_build_object('ok', false);
  end if;

  -- A ceiling on fresh visits per hour, so the table cannot be filled by a
  -- script. Steps for visits already recorded keep working past it.
  if not exists (select 1 from public.quiz_funnel where visit = p_visit) then
    select count(*) into v_hour from public.quiz_funnel
     where created_at > now() - interval '1 hour';
    if v_hour >= 500 then
      return jsonb_build_object('ok', false, 'reason', 'busy');
    end if;
  end if;

  insert into public.quiz_funnel (visit, stage, stage_index, track)
  values (p_visit, left(btrim(p_stage), 40), p_index, left(coalesce(p_track,''), 20))
  on conflict (visit) do update
    set stage       = excluded.stage,
        stage_index = excluded.stage_index,
        track       = coalesce(nullif(excluded.track,''), public.quiz_funnel.track),
        updated_at  = now()
   where excluded.stage_index > public.quiz_funnel.stage_index;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.quiz_stage(uuid,text,integer,text) from public;
grant execute on function public.quiz_stage(uuid,text,integer,text) to anon, authenticated;

notify pgrst, 'reload schema';
