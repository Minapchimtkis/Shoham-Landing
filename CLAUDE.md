# Shoham-Landing

Static site, no build step. `index.html` is the landing page and
`admin/index.html` is the leads dashboard; both are single files with their
CSS and JS inline. GitHub Pages serves the repo from `main`, so `main` is
the live site.

## Git

**Commit and push straight to `main`.** When asked to commit, push, or save
changes, that means `main` — not a feature branch, and without asking which
branch each time. `main` is the address the site is served from, so a push
publishes it.

Use `git push -u origin main`, and retry a few times on network errors.

## Supabase

Both pages talk to the Supabase project `vplqocqmlquajwwnyeby`. The landing
form POSTs to the `submit-lead` edge function; the dashboard reads and writes
the `leads` table directly under RLS, authenticated with email + password.

Only the publishable key belongs in these files — never a service-role key.
Schema changes go in `supabase/migrations/` and have to be run by hand in the
Supabase SQL editor; this environment's network policy blocks `supabase.co`,
so they cannot be applied from a session here.
