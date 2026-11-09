-- Minimal stand-in for Supabase's auth schema, so schema.sql runs in plain Postgres (PGlite).
create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  phone text,
  phone_confirmed_at timestamptz,
  raw_user_meta_data jsonb default '{}'
);
-- Same contract as Supabase: the user id comes from the request.jwt.claims setting; unset/empty = null.
create function auth.uid() returns uuid language sql stable as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid
$$;
create role anon nologin;
create role authenticated nologin;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
