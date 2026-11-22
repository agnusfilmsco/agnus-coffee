-- =====================================================================
-- Agnus Coffee · 003: Casa (estoque compartilhado entre família/amigos)
-- Rode depois do 002. Pode rodar de novo sem problema.
-- =====================================================================

create table if not exists public.casas (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  codigo     text not null unique,            -- convite, ex.: "K7Q2MX"
  criada_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.casa_membros (
  casa_id  uuid not null references public.casas(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  nome     text,
  papel    text not null default 'membro',     -- dono | membro
  entrou_em timestamptz not null default now(),
  primary key (casa_id, user_id)
);

-- O estoque da casa: cafés cadastrados e quanto resta de cada pacote.
create table if not exists public.casa_estoque (
  casa_id    uuid primary key references public.casas(id) on delete cascade,
  cafes      jsonb not null default '[]'::jsonb,
  estoque    jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

-- O que cada um fez: "Rebeca usou 20 g do Prelúdio 001".
create table if not exists public.casa_atividade (
  id        bigserial primary key,
  casa_id   uuid not null references public.casas(id) on delete cascade,
  user_id   uuid references auth.users(id) on delete set null,
  nome      text,
  texto     text not null,
  created_at timestamptz not null default now()
);
create index if not exists casa_atividade_idx on public.casa_atividade (casa_id, created_at desc);

create or replace function public.is_membro(p_casa uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from casa_membros where casa_id = p_casa and user_id = auth.uid());
$$;

alter table public.casas          enable row level security;
alter table public.casa_membros   enable row level security;
alter table public.casa_estoque   enable row level security;
alter table public.casa_atividade enable row level security;

drop policy if exists "casas: membros leem" on public.casas;
create policy "casas: membros leem" on public.casas for select using (public.is_membro(id));
drop policy if exists "membros: membros leem" on public.casa_membros;
create policy "membros: membros leem" on public.casa_membros for select using (public.is_membro(casa_id));
drop policy if exists "estoque: membros leem" on public.casa_estoque;
drop policy if exists "estoque: membros gravam" on public.casa_estoque;
create policy "estoque: membros leem"   on public.casa_estoque for select using (public.is_membro(casa_id));
create policy "estoque: membros gravam" on public.casa_estoque for update using (public.is_membro(casa_id)) with check (public.is_membro(casa_id));
drop policy if exists "atividade: membros leem" on public.casa_atividade;
drop policy if exists "atividade: membros escrevem" on public.casa_atividade;
create policy "atividade: membros leem"     on public.casa_atividade for select using (public.is_membro(casa_id));
create policy "atividade: membros escrevem" on public.casa_atividade for insert with check (public.is_membro(casa_id) and user_id = auth.uid());

-- Criar casa: gera o código, entra como dono e leva o estoque atual da pessoa.
create or replace function public.criar_casa(p_nome text, p_meu_nome text, p_cafes jsonb, p_estoque jsonb)
returns public.casas language plpgsql security definer set search_path = public as $$
declare c casas; cod text;
begin
  if auth.uid() is null then raise exception 'login necessário'; end if;
  loop
    cod := upper(substr(translate(md5(random()::text || clock_timestamp()::text), '01', 'XY'), 1, 6));
    exit when length(cod) = 6 and not exists (select 1 from casas where codigo = cod);
  end loop;
  insert into casas (nome, codigo, criada_por) values (coalesce(nullif(p_nome,''),'Minha casa'), cod, auth.uid()) returning * into c;
  insert into casa_membros (casa_id, user_id, nome, papel) values (c.id, auth.uid(), p_meu_nome, 'dono');
  insert into casa_estoque (casa_id, cafes, estoque, updated_by) values (c.id, coalesce(p_cafes,'[]'), coalesce(p_estoque,'{}'), auth.uid());
  insert into casa_atividade (casa_id, user_id, nome, texto) values (c.id, auth.uid(), p_meu_nome, 'criou a casa');
  return c;
end $$;

-- Entrar com código: junta os pacotes da pessoa ao estoque da casa (ninguém perde nada).
create or replace function public.entrar_casa(p_codigo text, p_meu_nome text, p_cafes jsonb, p_estoque jsonb)
returns public.casas language plpgsql security definer set search_path = public as $$
declare c casas; e casa_estoque; novos jsonb;
begin
  if auth.uid() is null then raise exception 'login necessário'; end if;
  select * into c from casas where codigo = upper(trim(p_codigo));
  if c.id is null then raise exception 'código não encontrado'; end if;
  insert into casa_membros (casa_id, user_id, nome) values (c.id, auth.uid(), p_meu_nome) on conflict do nothing;
  select * into e from casa_estoque where casa_id = c.id for update;
  select coalesce(jsonb_agg(x), '[]') into novos from jsonb_array_elements(coalesce(p_cafes,'[]')) x
    where not exists (select 1 from jsonb_array_elements(e.cafes) y where y->>'id' = x->>'id');
  update casa_estoque set cafes = e.cafes || novos, estoque = coalesce(p_estoque,'{}') || e.estoque,
         updated_by = auth.uid(), updated_at = now() where casa_id = c.id;
  insert into casa_atividade (casa_id, user_id, nome, texto) values (c.id, auth.uid(), p_meu_nome, 'entrou na casa');
  return c;
end $$;

-- Descontar a dose de um pacote sem perder o que outra pessoa usou ao mesmo tempo.
create or replace function public.casa_descontar(p_casa uuid, p_cafe text, p_gramas numeric, p_texto text, p_meu_nome text)
returns numeric language plpgsql security definer set search_path = public as $$
declare restante numeric;
begin
  if not is_membro(p_casa) then raise exception 'sem acesso'; end if;
  update casa_estoque
     set estoque = jsonb_set(estoque, array[p_cafe,'left'],
                   to_jsonb(greatest(0, coalesce((estoque->p_cafe->>'left')::numeric,0) - p_gramas))),
         updated_by = auth.uid(), updated_at = now()
   where casa_id = p_casa and estoque ? p_cafe
   returning (estoque->p_cafe->>'left')::numeric into restante;
  insert into casa_atividade (casa_id, user_id, nome, texto) values (p_casa, auth.uid(), p_meu_nome, p_texto);
  return restante;
end $$;

create or replace function public.sair_casa(p_casa uuid)
returns void language sql security definer set search_path = public as $$
  delete from casa_membros where casa_id = p_casa and user_id = auth.uid();
$$;

grant execute on function public.criar_casa(text, text, jsonb, jsonb) to authenticated;
grant execute on function public.entrar_casa(text, text, jsonb, jsonb) to authenticated;
grant execute on function public.casa_descontar(uuid, text, numeric, text, text) to authenticated;
grant execute on function public.sair_casa(uuid) to authenticated;

do $$ begin
  begin alter publication supabase_realtime add table public.casa_estoque;   exception when others then null; end;
  begin alter publication supabase_realtime add table public.casa_atividade; exception when others then null; end;
end $$;
