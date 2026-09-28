-- Someone who taps the number and telephones him was, until now, invisible:
-- the call arrives with nothing behind it, and no record that the site sent
-- it. This makes that tap a lead like any other, labelled 'call'.
--
-- What the site can and cannot know, stated plainly. It cannot see the
-- caller's number — a tel: link hands the number to the dialler and the page
-- learns nothing back, exactly as with WhatsApp. What it can do is pass on a
-- number the person already typed on this device, into the form or into the
-- WhatsApp panel. When there is one the lead arrives complete; when there is
-- not, it arrives as a call at a time, and the caller's own number is on his
-- phone, which is the one place it does exist.
--
-- Run in the Supabase SQL editor. Re-running is harmless.

do $$
declare id_type text;
begin
  select format_type(a.atttypid, a.atttypmod) into id_type
    from pg_attribute a
   where a.attrelid = 'public.leads'::regclass and a.attname = 'id' and a.attnum > 0;

  if to_regclass('public.call_clicks') is null then
    execute format($f$
      create table public.call_clicks(
        id         uuid primary key default gen_random_uuid(),
        lead_id    %s references public.leads(id) on delete cascade,
        -- The browser that tapped, so repeat taps by one person do not become
        -- a row of identical leads.
        client     uuid,
        page       text        not null default 'landing',
        created_at timestamptz not null default now()
      )$f$, id_type);
  end if;
end $$;

create index if not exists call_clicks_lead_idx    on public.call_clicks (lead_id);
create index if not exists call_clicks_client_idx  on public.call_clicks (client, created_at desc);
create index if not exists call_clicks_created_idx on public.call_clicks (created_at desc);

alter table public.call_clicks enable row level security;
drop policy if exists call_clicks_read   on public.call_clicks;
drop policy if exists call_clicks_delete on public.call_clicks;
create policy call_clicks_read   on public.call_clicks for select to authenticated using (true);
create policy call_clicks_delete on public.call_clicks for delete to authenticated using (true);
revoke all on table public.call_clicks from anon;
grant select, delete on table public.call_clicks to authenticated;

-- The one way in, guarded exactly as wa_click is and for the same reasons.
create or replace function public.call_click(
  p_page      text default 'landing',
  p_client    uuid default null,
  p_phone     text default null,
  p_page_lang text default 'he'
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_lead  public.leads%rowtype;
  v_fresh integer;
  v_hour  integer;
  v_page  text := case when p_page in ('landing','quiz') then p_page else 'landing' end;
  v_norm  text := norm_phone(p_phone);
begin
  -- A ceiling on the table itself, so a script cannot fill it with taps.
  select count(*) into v_hour from public.call_clicks
   where created_at > now() - interval '1 hour';
  if v_hour >= 200 then
    return jsonb_build_object('ok', false, 'reason', 'busy');
  end if;

  -- Someone who already gave that number is that person, not a new one.
  if length(v_norm) = 9 then
    select * into v_lead from public.leads
     where norm_phone(phone) = norm_phone(p_phone)
     order by created_at desc limit 1;
  end if;

  -- Tapping twice, or ringing again an hour later, is one person deciding to
  -- call — not two leads. Anything this browser already opened today is
  -- reused before a new one is made.
  if v_lead.id is null and p_client is not null then
    select l.* into v_lead
      from public.call_clicks c
      join public.leads l on l.id = c.lead_id
     where c.client = p_client
       and c.created_at > now() - interval '12 hours'
     order by c.created_at desc limit 1;
  end if;

  if v_lead.id is null then
    select count(*) into v_fresh from public.leads
     where created_at > now() - interval '1 hour';
    if v_fresh < 40 then
      -- No name: there is none to have. The dashboard already renders a lead
      -- without one as a dash, and the source chip says where it came from.
      --
      -- Unless the table will not have it. This migration cannot see the
      -- original leads definition — it is not among the migrations here — so
      -- rather than assume the columns are nullable, it asks, and fills in a
      -- placeholder only where a null would be refused.
      declare
        v_name_req  boolean;
        v_phone_req boolean;
      begin
        select coalesce(bool_or(attname = 'name'  and attnotnull), false),
               coalesce(bool_or(attname = 'phone' and attnotnull), false)
          into v_name_req, v_phone_req
          from pg_attribute
         where attrelid = 'public.leads'::regclass
           and attname in ('name','phone') and attnum > 0 and not attisdropped;

        insert into public.leads (name, phone, page_lang)
        values (case when v_name_req then 'שיחת טלפון' end,
                coalesce(case when length(v_norm) = 9 then btrim(p_phone) end,
                         case when v_phone_req then '' end),
                coalesce(p_page_lang, 'he'))
        returning * into v_lead;
      end;

      if exists (
        select 1 from pg_attribute
         where attrelid = 'public.leads'::regclass
           and attname = 'source' and attnum > 0 and not attisdropped
      ) then
        execute 'update public.leads set source = coalesce(source, ''call'') where id = $1'
          using v_lead.id;
      end if;
    end if;
  end if;

  insert into public.call_clicks (lead_id, client, page)
  values (v_lead.id, p_client, v_page);

  -- Identified means there is a number to ring back, not merely a column.
  return jsonb_build_object('ok', true,
    'identified', length(norm_phone(v_lead.phone)) = 9);
end $$;

revoke all on function public.call_click(text,uuid,text,text) from public;
grant execute on function public.call_click(text,uuid,text,text) to anon, authenticated;

notify pgrst, 'reload schema';

-- What it did, so you can see it worked:
--   select coalesce(source,'(ריק)') as source, count(*)
--     from public.leads group by 1 order by 2 desc;
--   select created_at, lead_id from public.call_clicks order by created_at desc limit 10;
