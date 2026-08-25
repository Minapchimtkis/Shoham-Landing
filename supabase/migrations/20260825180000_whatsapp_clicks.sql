-- Records that someone left the site for WhatsApp.
--
-- The site cannot see who that is: their number only appears once their
-- message arrives in WhatsApp. So the button now offers a name and phone
-- first, and whoever fills it in becomes a lead like any other. Whoever
-- skips is still counted, without a name, so the advisor knows to expect a
-- message he cannot match to anything.
--
-- Run in the Supabase SQL editor. Re-running is harmless.

do $$
declare id_type text;
begin
  select format_type(a.atttypid, a.atttypmod) into id_type
    from pg_attribute a
   where a.attrelid = 'public.leads'::regclass and a.attname = 'id' and a.attnum > 0;

  if to_regclass('public.wa_clicks') is null then
    execute format($f$
      create table public.wa_clicks(
        id         uuid primary key default gen_random_uuid(),
        lead_id    %s references public.leads(id) on delete set null,
        page       text        not null default 'landing',
        created_at timestamptz not null default now()
      )$f$, id_type);
  end if;
end $$;

create index if not exists wa_clicks_lead_idx    on public.wa_clicks (lead_id);
create index if not exists wa_clicks_created_idx on public.wa_clicks (created_at desc);

alter table public.wa_clicks enable row level security;
drop policy if exists wa_clicks_read   on public.wa_clicks;
drop policy if exists wa_clicks_delete on public.wa_clicks;
create policy wa_clicks_read   on public.wa_clicks for select to authenticated using (true);
create policy wa_clicks_delete on public.wa_clicks for delete to authenticated using (true);
revoke all on table public.wa_clicks from anon;
grant select, delete on table public.wa_clicks to authenticated;

-- The one way in, guarded like quiz_submit for the same reasons.
create or replace function public.wa_click(
  p_page         text    default 'landing',
  p_token        uuid    default null,
  p_name         text    default null,
  p_phone        text    default null,
  p_consent      boolean default false,
  p_consent_text text    default null,
  p_page_lang    text    default 'he'
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_lead  public.leads%rowtype;
  v_fresh integer;
  v_hour  integer;
  v_name  text := left(btrim(coalesce(p_name,'')), 80);
  v_page  text := case when p_page in ('landing','quiz') then p_page else 'landing' end;
begin
  -- A ceiling on the table itself, so a script cannot fill it with clicks.
  select count(*) into v_hour from public.wa_clicks
   where created_at > now() - interval '1 hour';
  if v_hour >= 200 then
    return jsonb_build_object('ok', false, 'reason', 'busy');
  end if;

  if p_token is not null then
    select * into v_lead from public.leads where quiz_token = p_token;
  end if;

  if v_lead.id is null and length(norm_phone(p_phone)) = 9 then
    select * into v_lead from public.leads
     where norm_phone(phone) = norm_phone(p_phone)
     order by created_at desc limit 1;
  end if;

  -- Details were given and this is someone new: a real lead, like the form.
  if v_lead.id is null and v_name <> '' and length(norm_phone(p_phone)) = 9 then
    select count(*) into v_fresh from public.leads
     where created_at > now() - interval '1 hour';
    if v_fresh < 40 then
      insert into public.leads (name, phone, consent, consent_text, consent_at, page_lang)
      values (v_name, btrim(p_phone), p_consent, p_consent_text,
              case when p_consent then now() end, coalesce(p_page_lang,'he'))
      returning * into v_lead;

      if exists (
        select 1 from pg_attribute
         where attrelid = 'public.leads'::regclass
           and attname = 'source' and attnum > 0 and not attisdropped
      ) then
        execute 'update public.leads set source = coalesce(source, ''whatsapp'') where id = $1'
          using v_lead.id;
      end if;
    end if;
  end if;

  insert into public.wa_clicks (lead_id, page) values (v_lead.id, v_page);
  return jsonb_build_object('ok', true, 'identified', v_lead.id is not null);
end $$;

revoke all on function public.wa_click(text,uuid,text,text,boolean,text,text) from public;
grant execute on function public.wa_click(text,uuid,text,text,boolean,text,text) to anon, authenticated;

notify pgrst, 'reload schema';
