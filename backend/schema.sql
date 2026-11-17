-- ANASOL · esquema do banco (cole inteiro no SQL Editor do Supabase e clique em Run)
-- Antes: crie o usuário Master em Authentication > Users (e-mail abaixo) e desmarque confirmação se pedir.

create table if not exists public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  role text not null default 'user' check (role in ('master','user')),
  created_at timestamptz not null default now());

create table if not exists public.proposals(
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  number text not null unique,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
create index if not exists proposals_owner_idx on public.proposals(owner_id);

create table if not exists public.counters(year int primary key, last int not null default 0);

alter table public.profiles  enable row level security;
alter table public.proposals enable row level security;
alter table public.counters  enable row level security;

create or replace function public.is_master() returns boolean
language sql security definer stable set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'master')
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id,email,full_name,role)
  values(new.id,new.email,new.raw_user_meta_data->>'full_name','user') on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- numeração única AS-AAAA-NNNN para todo o sistema
create or replace function public.assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare y int := extract(year from (now() at time zone 'America/Sao_Paulo')); n int;
begin
  insert into public.counters(year,last) values(y,1)
  on conflict (year) do update set last = public.counters.last + 1 returning last into n;
  new.number := 'AS-' || y || '-' || lpad(n::text,4,'0');
  return new;
end $$;
drop trigger if exists proposals_number on public.proposals;
create trigger proposals_number before insert on public.proposals for each row execute function public.assign_number();

-- permissões
revoke all on public.profiles, public.proposals, public.counters from anon;
grant select on public.profiles to authenticated;
grant select, insert, update, delete on public.proposals to authenticated;
grant execute on function public.is_master() to authenticated;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_master());

drop policy if exists proposals_select on public.proposals;
drop policy if exists proposals_insert on public.proposals;
drop policy if exists proposals_update on public.proposals;
drop policy if exists proposals_delete on public.proposals;
create policy proposals_select on public.proposals for select to authenticated
  using (owner_id = auth.uid() or public.is_master());
create policy proposals_insert on public.proposals for insert to authenticated
  with check (owner_id = auth.uid());
create policy proposals_update on public.proposals for update to authenticated
  using (owner_id = auth.uid() or public.is_master())
  with check (owner_id = auth.uid() or public.is_master());
create policy proposals_delete on public.proposals for delete to authenticated
  using (owner_id = auth.uid() or public.is_master());

-- usuário Master
insert into public.profiles(id,email,full_name,role)
select id, email, 'Master', 'master' from auth.users
where lower(email) = lower('alissonrodrigomartins1@gmail.com')
on conflict (id) do update set role = 'master';
