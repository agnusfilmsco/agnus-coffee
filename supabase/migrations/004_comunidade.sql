-- Agnus Coffee · 004 · comunidade, amigos, pré-cadastro do clube e recomendações
-- Só adiciona tabelas e funções novas. Nada existente é apagado ou alterado.

-- Vitrine: o que cada pessoa mostra aos amigos (e à comunidade, se quiser)
create table if not exists public.vitrine (
  user_id    uuid primary key references auth.users on delete cascade,
  nome       text,
  codigo     text unique,
  publico    boolean not null default false,
  dados      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.amizades (
  user_id    uuid not null references auth.users on delete cascade,
  amigo_id   uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, amigo_id)
);

create table if not exists public.pre_cadastro_clube (
  user_id    uuid primary key references auth.users on delete cascade,
  nome       text,
  email      text,
  cidade     text,
  interesses text[] not null default '{}',
  created_at timestamptz not null default now()
);

create table if not exists public.recomendacoes (
  id         uuid primary key default gen_random_uuid(),
  titulo     text not null,
  descricao  text,
  categoria  text,
  preco      text,
  url        text,
  cupom      text,
  para       text not null default 'todos',
  ordem      int  not null default 100,
  ativo      boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.config (
  chave text primary key,
  valor jsonb
);

alter table public.vitrine            enable row level security;
alter table public.amizades           enable row level security;
alter table public.pre_cadastro_clube enable row level security;
alter table public.recomendacoes      enable row level security;
alter table public.config             enable row level security;

create or replace function public.e_amigo(p_outro uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.amizades where user_id = auth.uid() and amigo_id = p_outro);
$$;

drop policy if exists "vitrine: le" on public.vitrine;
drop policy if exists "vitrine: grava a sua" on public.vitrine;
create policy "vitrine: le" on public.vitrine for select
  using (user_id = auth.uid() or publico or public.e_amigo(user_id) or public.is_admin());
create policy "vitrine: grava a sua" on public.vitrine for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "amizades: le as suas" on public.amizades;
create policy "amizades: le as suas" on public.amizades for select
  using (user_id = auth.uid() or amigo_id = auth.uid() or public.is_admin());

drop policy if exists "pre-cadastro: o seu" on public.pre_cadastro_clube;
drop policy if exists "pre-cadastro: equipe le" on public.pre_cadastro_clube;
create policy "pre-cadastro: o seu" on public.pre_cadastro_clube for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "pre-cadastro: equipe le" on public.pre_cadastro_clube for select using (public.is_admin());

drop policy if exists "recomendacoes: todos leem" on public.recomendacoes;
drop policy if exists "recomendacoes: equipe grava" on public.recomendacoes;
create policy "recomendacoes: todos leem" on public.recomendacoes for select using (ativo or public.is_admin());
create policy "recomendacoes: equipe grava" on public.recomendacoes for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "config: todos leem" on public.config;
drop policy if exists "config: equipe grava" on public.config;
create policy "config: todos leem" on public.config for select using (true);
create policy "config: equipe grava" on public.config for all using (public.is_admin()) with check (public.is_admin());

-- Adicionar amigo pelo código (amizade nos dois sentidos)
create or replace function public.adicionar_amigo(p_codigo text)
returns text language plpgsql security definer set search_path = public as $$
declare v record;
begin
  if auth.uid() is null then raise exception 'entre na sua conta'; end if;
  select user_id, nome into v from public.vitrine where codigo = upper(trim(p_codigo));
  if v.user_id is null then raise exception 'código não encontrado'; end if;
  if v.user_id = auth.uid() then raise exception 'esse é o seu código'; end if;
  insert into public.amizades (user_id, amigo_id) values (auth.uid(), v.user_id), (v.user_id, auth.uid())
    on conflict do nothing;
  return coalesce(v.nome, 'Amigo');
end $$;

create or replace function public.remover_amigo(p_amigo uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.amizades
   where (user_id = auth.uid() and amigo_id = p_amigo) or (user_id = p_amigo and amigo_id = auth.uid());
$$;

-- Contador público do pré-cadastro (só o número)
create or replace function public.contar_pre_cadastro()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.pre_cadastro_clube;
$$;

grant execute on function public.adicionar_amigo(text) to authenticated;
grant execute on function public.remover_amigo(uuid) to authenticated;
grant execute on function public.contar_pre_cadastro() to anon, authenticated;

insert into public.config (chave, valor) values ('clube_meta', '200'::jsonb) on conflict (chave) do nothing;

insert into public.recomendacoes (titulo, descricao, categoria, preco, para, ordem)
select * from (values
  ('Moedor manual de rebarbas', 'O passo que mais muda a xícara: moagem uniforme na hora.', 'Equipamento', null, 'sem_moedor', 10),
  ('Balança com timer', 'Pesa café e água e marca o tempo. Repetir receita fica fácil.', 'Equipamento', null, 'sem_balanca', 20),
  ('Chaleira bico de ganso', 'Controle do fio de água para V60, Melitta e Chemex.', 'Equipamento', null, 'todos', 30),
  ('Kit V60 para começar', 'Suporte, filtros e jarra para o primeiro coado especial.', 'Método', null, 'todos', 40),
  ('Prelúdio 001 · Agnus Coffee', 'Doce de leite, caramelo e chocolate. O café da casa.', 'Café', null, 'todos', 5)
) as v(titulo, descricao, categoria, preco, para, ordem)
where not exists (select 1 from public.recomendacoes);
