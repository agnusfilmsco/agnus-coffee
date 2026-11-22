-- =====================================================================
-- Agnus Coffee · 002: painel da equipe (cadastros, acessos, compras)
-- Rode depois do 001_base.sql. Pode rodar de novo sem problema.
-- =====================================================================

-- Perfil de cada pessoa cadastrada (atualizado a cada acesso).
create table if not exists public.perfis (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  nome           text,
  email          text,
  provedor       text,                       -- google | email
  metodos        text[],
  moedores       text[],
  assinante      boolean not null default false,
  criado_em      timestamptz not null default now(),
  ultimo_acesso  timestamptz not null default now(),
  acessos        integer not null default 1
);

-- Eventos: acesso, cadastro, clique_compra, cupom_copiado, preparo, lista_espera...
create table if not exists public.eventos (
  id         bigserial primary key,
  user_id    uuid references auth.users(id) on delete set null,
  tipo       text not null,
  dados      jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists eventos_tipo_idx on public.eventos (tipo, created_at desc);

-- Parceiros: link da loja e cupom de cada marca (a equipe edita no painel).
create table if not exists public.parceiros (
  slug       text primary key,               -- ex.: "dropit"
  nome       text not null,
  url_loja   text,
  cupom      text,
  desconto   text,                           -- ex.: "15% na primeira compra"
  ativo      boolean not null default true,
  updated_at timestamptz not null default now()
);

-- Vendas confirmadas (lançadas pela equipe a partir do relatório de cupom do parceiro,
-- ou por integração automática no futuro).
create table if not exists public.vendas (
  id         bigserial primary key,
  parceiro   text references public.parceiros(slug) on delete set null,
  cupom      text,
  valor      numeric(10,2),
  cliente    text,                           -- e-mail ou nome, se o parceiro informar
  data       date not null default current_date,
  origem     text not null default 'manual', -- manual | integracao
  created_at timestamptz not null default now()
);

alter table public.perfis    enable row level security;
alter table public.eventos   enable row level security;
alter table public.parceiros enable row level security;
alter table public.vendas    enable row level security;

drop policy if exists "perfis: dono"        on public.perfis;
drop policy if exists "perfis: equipe le"   on public.perfis;
create policy "perfis: dono"      on public.perfis for all    using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "perfis: equipe le" on public.perfis for select using (public.is_admin());

drop policy if exists "eventos: registra" on public.eventos;
drop policy if exists "eventos: equipe le" on public.eventos;
create policy "eventos: registra"  on public.eventos for insert with check (user_id = auth.uid());
create policy "eventos: equipe le" on public.eventos for select using (public.is_admin());

drop policy if exists "parceiros: todos leem"   on public.parceiros;
drop policy if exists "parceiros: equipe grava" on public.parceiros;
create policy "parceiros: todos leem"   on public.parceiros for select using (true);
create policy "parceiros: equipe grava" on public.parceiros for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "vendas: equipe" on public.vendas;
create policy "vendas: equipe" on public.vendas for all using (public.is_admin()) with check (public.is_admin());

-- Registra acesso: cria o perfil no 1º login (evento "cadastro") e soma acessos depois.
create or replace function public.registrar_acesso(p_nome text, p_provedor text, p_metodos text[], p_moedores text[])
returns void language plpgsql security definer set search_path = public as $$
declare novo boolean;
begin
  if auth.uid() is null then return; end if;
  insert into perfis (user_id, nome, email, provedor, metodos, moedores)
  values (auth.uid(), p_nome, (select email from auth.users where id = auth.uid()), p_provedor, p_metodos, p_moedores)
  on conflict (user_id) do nothing
  returning true into novo;
  if novo then
    insert into eventos (user_id, tipo, dados) values (auth.uid(), 'cadastro', jsonb_build_object('provedor', p_provedor));
  else
    update perfis set ultimo_acesso = now(), acessos = acessos + 1,
           nome = coalesce(p_nome, nome), metodos = coalesce(p_metodos, metodos), moedores = coalesce(p_moedores, moedores)
    where user_id = auth.uid();
  end if;
  insert into eventos (user_id, tipo) values (auth.uid(), 'acesso');
end $$;
grant execute on function public.registrar_acesso(text, text, text[], text[]) to authenticated;

-- Visões do painel (só a equipe enxerga, pelas regras das tabelas).
create or replace view public.painel_resumo with (security_invoker = true) as
select
  (select count(*) from perfis)                                                        as cadastros,
  (select count(*) from perfis where criado_em > now() - interval '7 days')            as cadastros_7d,
  (select count(*) from perfis where ultimo_acesso > now() - interval '7 days')        as ativos_7d,
  (select count(*) from eventos where tipo = 'acesso' and created_at::date = current_date) as acessos_hoje,
  (select count(*) from eventos where tipo = 'clique_compra')                          as cliques_compra,
  (select count(*) from eventos where tipo = 'cupom_copiado')                          as cupons_copiados,
  (select count(*) from vendas)                                                        as vendas,
  (select coalesce(sum(valor),0) from vendas)                                          as receita_vendas;

create or replace view public.painel_compras_por_marca with (security_invoker = true) as
select coalesce(e.dados->>'parceiro','?')               as parceiro,
       count(*) filter (where e.tipo = 'clique_compra') as cliques,
       count(*) filter (where e.tipo = 'cupom_copiado') as cupons_copiados,
       count(distinct e.user_id)                        as pessoas,
       max(e.created_at)                                as ultimo
from eventos e
where e.tipo in ('clique_compra','cupom_copiado')
group by 1;

-- Parceiros iniciais (troque links e cupons pelo painel).
insert into public.parceiros (slug, nome, url_loja, cupom, desconto) values
  ('agnus-coffee','Agnus Coffee', null, 'AGNUS', 'Café da casa'),
  ('dropit','Dropit', null, 'AGNUS10', '10% para a comunidade Agnus'),
  ('unique-cafes','Unique Cafés', null, 'AGNUS10', '10% para a comunidade Agnus')
on conflict (slug) do nothing;

-- Tempo real no painel (novos cadastros, cliques e eventos aparecem sem recarregar).
do $$ begin
  begin alter publication supabase_realtime add table public.eventos; exception when others then null; end;
  begin alter publication supabase_realtime add table public.perfis;  exception when others then null; end;
end $$;
