-- Fix: the intake questionnaires were open to every signed-in user.
--
-- 20261021120000_intake.sql created the table with policies written
-- "to authenticated using (true)". In this project that is not a
-- restriction at all. The budget app is open to the world by design, so
-- anyone who signs up there becomes authenticated in this same Supabase
-- project, holding the publishable key that is printed in the page source.
-- One GET /rest/v1/intake_submissions would have returned every name,
-- phone, email and answer, and DELETE would have removed them.
--
-- 20261015120000_lock_business_tables.sql already settled how this project
-- decides who is allowed in: an explicit staff list and is_staff(). The
-- intake table has to be held to the same rule, and this file does nothing
-- else.
--
-- Run in the Supabase SQL editor, right after the intake migration.
-- Re-running is harmless.

-- The staff list must exist before anything here can lean on it. Failing
-- loudly is better than quietly leaving the table open.
do $$
begin
  if to_regclass('public.staff') is null
     or to_regprocedure('public.is_staff()') is null then
    raise exception using message =
      'is_staff() or the staff table is missing. Run ' ||
      '20261015120000_lock_business_tables.sql first, then this file.';
  end if;
  if not exists (select 1 from public.staff) then
    raise exception using message =
      'The staff list is empty, so this would lock you out of your own ' ||
      'dashboard. Add yourself first: insert into public.staff(user_id) ' ||
      'select id from auth.users where lower(email)=lower(''your email'');';
  end if;
end $$;

-- Drop every policy on the table, including any written outside this repo,
-- and rebuild only staff-gated ones.
do $$
declare p text;
begin
  if to_regclass('public.intake_submissions') is null then
    raise exception using message =
      'public.intake_submissions is missing. Run 20261021120000_intake.sql first.';
  end if;

  for p in select policyname from pg_policies
            where schemaname = 'public' and tablename = 'intake_submissions' loop
    execute format('drop policy %I on public.intake_submissions', p);
  end loop;
end $$;

alter table public.intake_submissions enable row level security;

create policy intake_staff_read on public.intake_submissions
  for select to authenticated using (public.is_staff());

create policy intake_staff_update on public.intake_submissions
  for update to authenticated using (public.is_staff()) with check (public.is_staff());

create policy intake_staff_delete on public.intake_submissions
  for delete to authenticated using (public.is_staff());

-- The column grants stay as they were: the dashboard may move a status,
-- write a note and attach a lead, and may not rewrite what somebody
-- answered. Restated here so this file is the whole truth about the table.
revoke all on public.intake_submissions from anon;
revoke all on public.intake_submissions from authenticated;
grant select, delete on public.intake_submissions to authenticated;
grant update (status, notes, updated_at, lead_id) on public.intake_submissions to authenticated;

-- Proof, printed where you run it. A non-staff signed-in user must see
-- nothing at all.
do $$
declare n int;
begin
  select count(*) into n from pg_policies
   where schemaname = 'public' and tablename = 'intake_submissions'
     and qual like '%is_staff%';
  raise notice 'intake_submissions: % staff-gated policies', n;

  select count(*) into n from pg_policies
   where schemaname = 'public' and tablename = 'intake_submissions'
     and qual not like '%is_staff%';
  if n > 0 then
    raise exception using message =
      'There is still a policy on intake_submissions that does not check is_staff().';
  end if;
end $$;

notify pgrst, 'reload schema';
