-- Record which door each lead came through.
--
-- Four separate places already write this — quiz_submit, the WhatsApp click
-- handler, the duplicate merge — but every one of them checks first whether
-- the column exists and quietly skips when it does not. It never did, so the
-- dashboard has shown every lead the same way since the beginning: no chip,
-- no way to tell a questionnaire lead from someone who tapped WhatsApp.
--
-- Adding the column is the whole fix. From the moment it runs, new leads
-- label themselves.
--
-- Run in the Supabase SQL editor. Re-running is harmless.

alter table public.leads add column if not exists source text;

-- No default on purpose. The quiz and WhatsApp paths insert the lead first and
-- then set the source with coalesce(source, 'quiz'), so a default would win
-- over them and label everything wrongly.

create index if not exists leads_source_idx on public.leads (source);

-- Leads already in the table can still be placed: a questionnaire answer or a
-- WhatsApp click against a lead says where that person came from. Anything
-- with neither stays empty and shows as ישיר, which is the honest answer.
update public.leads l
   set source = 'quiz'
 where l.source is null
   and exists (select 1 from public.quiz_results q where q.lead_id = l.id);

update public.leads l
   set source = 'whatsapp'
 where l.source is null
   and exists (select 1 from public.wa_clicks c where c.lead_id = l.id);

notify pgrst, 'reload schema';

-- What it did, so you can see it worked:
--   select coalesce(source, '(ריק)') as source, count(*)
--     from public.leads group by 1 order by 2 desc;
