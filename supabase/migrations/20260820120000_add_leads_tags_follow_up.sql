-- Columns backing the quick tags and the follow-up reminder in the leads
-- dashboard (admin/index.html). Without them the dashboard still loads and
-- reads fine, but "שמור שינויים" fails: the save writes both columns.
--
-- Run once in the Supabase SQL editor. Re-running is harmless.

alter table public.leads
  add column if not exists tags text[] not null default '{}',
  add column if not exists follow_up_at timestamptz;

-- The topbar export scans for leads that have a reminder set, and that is a
-- small slice of the table once it grows, so the index is partial.
create index if not exists leads_follow_up_at_idx
  on public.leads (follow_up_at)
  where follow_up_at is not null;

comment on column public.leads.tags is
  'Quick tags set from the admin dashboard. Free-form; the four presets are just UI defaults.';
comment on column public.leads.follow_up_at is
  'When to get back to this lead. Drives the row chip and the .ics export.';

-- New columns are covered by the table's existing row-level security
-- policies, so nothing to grant here.
