-- Permissions for the admin dashboard.
--
-- Every policy here only ADDS access for accounts whose profile has
-- role = 'admin'; existing policies for regular users are left untouched
-- (Postgres combines permissive policies with OR). Safe to run more than once.
--
-- Apply with:  supabase db push   (or paste into the SQL editor)

-- Helper used by the policies below. SECURITY DEFINER lets it read
-- `profiles` without tripping that table's own policies (no recursion).
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Lookup lists (book types, parties, statuses) are edited from the dashboard.
alter table public.options add column if not exists sort_order integer not null default 0;

drop policy if exists "dashboard: admins manage options" on public.options;
create policy "dashboard: admins manage options" on public.options
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Admins see and manage every profile (the user list).
drop policy if exists "dashboard: admins manage profiles" on public.profiles;
create policy "dashboard: admins manage profiles" on public.profiles
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Admins manage every document and task record.
drop policy if exists "dashboard: admins manage documents" on public.documents;
create policy "dashboard: admins manage documents" on public.documents
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "dashboard: admins manage tasks" on public.tasks;
create policy "dashboard: admins manage tasks" on public.tasks
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Admins manage the attachment files (bulk upload, replace, backup).
drop policy if exists "dashboard: admins manage attachment files" on storage.objects;
create policy "dashboard: admins manage attachment files" on storage.objects
  for all to authenticated
  using (bucket_id in ('attachments', 'tasks') and public.is_admin())
  with check (bucket_id in ('attachments', 'tasks') and public.is_admin());
