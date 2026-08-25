-- Deleting a lead should take their WhatsApp handoffs with them.
--
-- The key was written as "on delete set null", so clearing a lead left its
-- clicks behind with nobody attached — and the dashboard counts a click with
-- no lead as someone who went to WhatsApp without leaving details. Deleted
-- test leads therefore showed up as strangers who had made contact.
-- quiz_results already cascades; this makes the two agree.
--
-- Run in the Supabase SQL editor. Re-running is harmless.

do $$
declare id_type text;
begin
  select format_type(a.atttypid, a.atttypmod) into id_type
    from pg_attribute a
   where a.attrelid = 'public.leads'::regclass and a.attname = 'id' and a.attnum > 0;

  if exists (
    select 1 from pg_constraint
     where conrelid = 'public.wa_clicks'::regclass
       and contype = 'f' and conname = 'wa_clicks_lead_id_fkey'
  ) then
    alter table public.wa_clicks drop constraint wa_clicks_lead_id_fkey;
  end if;

  alter table public.wa_clicks
    add constraint wa_clicks_lead_id_fkey
    foreign key (lead_id) references public.leads(id) on delete cascade;
end $$;

notify pgrst, 'reload schema';
