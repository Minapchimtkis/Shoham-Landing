-- One person, one lead — enforced where the rows are actually created.
--
-- quiz_submit and wa_click both look a phone up before creating anything, so
-- neither makes a duplicate. The landing form goes through the submit-lead
-- edge function, which inserts without checking, and that function's code
-- lives only in the Supabase dashboard. This closes the gap from the database
-- side instead, so it holds no matter what calls it.
--
-- When a row arrives for a phone that already exists, whatever it carries
-- that the existing lead lacks is merged in and the new row is dropped. The
-- caller still receives its row — INSERT ... RETURNING hands back what was
-- inserted before this runs — so nothing upstream sees an error.
--
-- The advisor's own work is never overwritten: status, notes, tags and the
-- follow-up date stay exactly as they were, and so does the original
-- created_at, because the first contact is the one that counts.
--
-- Run in the Supabase SQL editor. Re-running is harmless.

create or replace function public.merge_duplicate_lead()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.leads%rowtype;
begin
  -- An escape hatch for restoring a backup: set local app.skip_lead_dedupe = 'on'
  if coalesce(current_setting('app.skip_lead_dedupe', true), '') = 'on' then
    return null;
  end if;

  -- Only the outermost insert; never a cascade of our own making.
  if pg_trigger_depth() > 1 then return null; end if;

  -- Without a usable phone there is nothing to match on, so the row stays.
  if length(norm_phone(new.phone)) <> 9 then return null; end if;

  select * into v_old from public.leads
   where id <> new.id
     and norm_phone(phone) = norm_phone(new.phone)
   order by created_at asc
   limit 1;

  if v_old.id is null then return null; end if;

  update public.leads set
    name         = coalesce(nullif(btrim(v_old.name),''), new.name),
    message      = case
                     when coalesce(btrim(new.message),'') = '' then v_old.message
                     when coalesce(btrim(v_old.message),'') = '' then new.message
                     when v_old.message like '%' || new.message || '%' then v_old.message
                     else left(v_old.message || E'\n\n— ' || to_char(now(),'DD/MM HH24:MI') || E' —\n' || new.message, 8000)
                   end,
    -- A later, explicit consent is better evidence than none at all.
    consent      = greatest(coalesce(v_old.consent,false)::int, coalesce(new.consent,false)::int)::boolean,
    consent_text = coalesce(nullif(btrim(v_old.consent_text),''), new.consent_text),
    consent_at   = coalesce(v_old.consent_at, new.consent_at),
    page_lang    = coalesce(nullif(btrim(v_old.page_lang),''), new.page_lang),
    updated_at   = now()
  where id = v_old.id;

  -- source only exists in some installs, so it is set separately.
  if exists (
    select 1 from pg_attribute
     where attrelid = 'public.leads'::regclass
       and attname = 'source' and attnum > 0 and not attisdropped
  ) then
    execute 'update public.leads set source = coalesce(source, $1) where id = $2'
      using (to_jsonb(new) ->> 'source'), v_old.id;
  end if;

  delete from public.leads where id = new.id;
  return null;
end $$;

drop trigger if exists merge_duplicate_lead_t on public.leads;
create trigger merge_duplicate_lead_t
  after insert on public.leads
  for each row execute function public.merge_duplicate_lead();

notify pgrst, 'reload schema';
