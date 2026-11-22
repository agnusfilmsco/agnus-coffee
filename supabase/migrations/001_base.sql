-- =====================================================================
-- Agnus Coffee · banco de dados (Supabase / Postgres)
-- Rode este arquivo inteiro no Supabase: SQL Editor > New query > Run.
-- Pode rodar de novo sem problema: tudo usa "if not exists".
-- =====================================================================

-- 1) Estado do app de cada pessoa (estoque, diário, receitas, perfil).
--    Um documento JSON por usuário. Simples para o MVP; dá para
--    normalizar em tabelas depois sem mudar o app por fora.
create table if not exists public.user_state (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  state      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- 2) Equipe Agnus (quem vê o radar de marcas e muda status de parceria).
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now()
);

-- 3) Radar: cada pacote cadastrado pela comunidade vira uma linha.
create table if not exists public.radar_pacotes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  coffee_id  text not null,
  brand      text,
  name       text,
  country    text,
  region     text,
  variety    text,
  process    text,
  seller     text,
  status     text,                 -- parceira | conhecida | nova (no momento do cadastro)
  created_at timestamptz not null default now(),
  unique (user_id, coffee_id)
);
create index if not exists radar_brand_idx on public.radar_pacotes (lower(brand));

-- 4) Status de negociação por marca (só equipe).
create table if not exists public.marcas (
  slug       text primary key,     -- marca normalizada, ex.: "cafe-cuervo"
  status     text not null,        -- conversa | fechada | descartada
  nota       text,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

-- Função auxiliar: a pessoa logada é da equipe?
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------------------------------------------------------------------
-- Segurança (Row Level Security): cada um só mexe no que é seu.
-- ---------------------------------------------------------------------
alter table public.user_state    enable row level security;
alter table public.admins        enable row level security;
alter table public.radar_pacotes enable row level security;
alter table public.marcas        enable row level security;

drop policy if exists "estado: dono le"      on public.user_state;
drop policy if exists "estado: dono grava"   on public.user_state;
drop policy if exists "estado: dono atualiza" on public.user_state;
create policy "estado: dono le"       on public.user_state for select using (user_id = auth.uid());
create policy "estado: dono grava"    on public.user_state for insert with check (user_id = auth.uid());
create policy "estado: dono atualiza" on public.user_state for update using (user_id = auth.uid());

drop policy if exists "admins: ve a si mesmo" on public.admins;
create policy "admins: ve a si mesmo" on public.admins for select using (user_id = auth.uid() or public.is_admin());

drop policy if exists "radar: dono insere"  on public.radar_pacotes;
drop policy if exists "radar: dono apaga"   on public.radar_pacotes;
drop policy if exists "radar: equipe le"    on public.radar_pacotes;
drop policy if exists "radar: dono atualiza" on public.radar_pacotes;
create policy "radar: dono insere"   on public.radar_pacotes for insert with check (user_id = auth.uid());
create policy "radar: dono atualiza" on public.radar_pacotes for update using (user_id = auth.uid());
create policy "radar: dono apaga"    on public.radar_pacotes for delete using (user_id = auth.uid());
create policy "radar: equipe le"     on public.radar_pacotes for select using (public.is_admin() or user_id = auth.uid());

drop policy if exists "marcas: equipe le"    on public.marcas;
drop policy if exists "marcas: equipe grava" on public.marcas;
create policy "marcas: equipe le"    on public.marcas for select using (public.is_admin());
create policy "marcas: equipe grava" on public.marcas for all    using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- Fotos dos pacotes (Storage). Leitura pública pelo link; cada pessoa
-- só envia e apaga fotos dentro da própria pasta (<user_id>/...).
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('pacotes', 'pacotes', true)
on conflict (id) do nothing;

drop policy if exists "fotos: dono envia"   on storage.objects;
drop policy if exists "fotos: dono troca"   on storage.objects;
drop policy if exists "fotos: dono apaga"   on storage.objects;
create policy "fotos: dono envia" on storage.objects for insert to authenticated
  with check (bucket_id = 'pacotes' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "fotos: dono troca" on storage.objects for update to authenticated
  using (bucket_id = 'pacotes' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "fotos: dono apaga" on storage.objects for delete to authenticated
  using (bucket_id = 'pacotes' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- Visão para a equipe: marcas agrupadas, com contagem de pacotes.
-- ---------------------------------------------------------------------
create or replace view public.radar_marcas with (security_invoker = true) as
select lower(brand)                     as marca_key,
       min(brand)                       as marca,
       count(*)                         as pacotes,
       count(distinct user_id)          as pessoas,
       array_agg(distinct country)      as paises,
       max(created_at)                  as ultimo_cadastro
from public.radar_pacotes
group by lower(brand);

-- Para virar equipe (rode trocando o e-mail, depois do primeiro login):
-- insert into public.admins (user_id) select id from auth.users where email = 'seu@email.com';
