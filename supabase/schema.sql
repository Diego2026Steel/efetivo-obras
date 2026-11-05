-- =====================================================================
-- Efetivo de Obras · iBUILD
-- Script do banco de dados (Supabase / PostgreSQL)
--
-- Como usar: Supabase > SQL Editor > New query > colar tudo > Run.
-- Pode ser executado mais de uma vez sem perder dados.
--
-- Modelo: cada tabela guarda o registro em "doc" (jsonb), no mesmo formato
-- usado pelo app. Colunas usadas pelas regras de acesso são geradas a
-- partir do doc, então ninguém consegue burlá-las pelo app.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------
create table if not exists public.perfis (
  id          uuid primary key references auth.users(id) on delete cascade,
  doc         jsonb not null default '{}'::jsonb,
  papel       text generated always as (doc->>'papel') stored,
  ativo       boolean generated always as (coalesce((doc->>'ativo')::boolean, true)) stored,
  atualizado_em timestamptz not null default now(),
  constraint perfis_papel_ok check (papel in ('RH','ENG','ENC'))
);

create table if not exists public.obras (
  id   text primary key default replace(gen_random_uuid()::text,'-',''),
  doc  jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

create table if not exists public.empresas (
  id   text primary key default replace(gen_random_uuid()::text,'-',''),
  doc  jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

create table if not exists public.colaboradores (
  id   text primary key default replace(gen_random_uuid()::text,'-',''),
  doc  jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

create table if not exists public.config (
  id   text primary key,
  doc  jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

-- Uma linha por obra e dia. id = "<obraId>_<AAAA-MM-DD>"
create table if not exists public.presencas (
  id       text primary key,
  doc      jsonb not null default '{}'::jsonb,
  obra_id  text generated always as (doc->>'obraId') stored,
  data     text generated always as (doc->>'data') stored,
  atualizado_por uuid default auth.uid(),
  atualizado_em  timestamptz not null default now(),
  constraint presencas_id_ok check (id = (doc->>'obraId') || '_' || (doc->>'data')),
  constraint presencas_data_ok check ((doc->>'data') ~ '^\d{4}-\d{2}-\d{2}$')
);
create index if not exists presencas_data_idx on public.presencas (data);
create index if not exists presencas_obra_idx on public.presencas (obra_id);

-- Mantém atualizado_em / atualizado_por em dia
create or replace function public.tg_touch() returns trigger
language plpgsql as $$
begin
  new.atualizado_em := now();
  if tg_table_name = 'presencas' then new.atualizado_por := auth.uid(); end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['perfis','obras','empresas','colaboradores','config','presencas'] loop
    execute format('drop trigger if exists touch on public.%I', t);
    execute format('create trigger touch before insert or update on public.%I for each row execute function public.tg_touch()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Funções de permissão (usadas pelas regras abaixo)
-- ---------------------------------------------------------------------
create or replace function public.meu_papel() returns text
language sql stable security definer set search_path = public as $$
  select papel from public.perfis where id = auth.uid() and ativo
$$;

create or replace function public.e_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.meu_papel() in ('RH','ENG'), false)
$$;

create or replace function public.tem_acesso() returns boolean
language sql stable security definer set search_path = public as $$
  select public.meu_papel() is not null
$$;

create or replace function public.pode_obra(o text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.perfis p
    where p.id = auth.uid() and p.ativo
      and (p.papel in ('RH','ENG') or (p.doc->'obras') ? o)
  )
$$;

create or replace function public.hoje_sp() returns text
language sql stable as $$
  select to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD')
$$;

-- Usada pela tela de primeiro acesso (antes de existir qualquer usuário)
create or replace function public.precisa_configurar() returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.perfis)
$$;

revoke all on function public.precisa_configurar() from public;
grant execute on function public.precisa_configurar() to anon, authenticated;
grant execute on function public.meu_papel(), public.e_admin(), public.tem_acesso(), public.pode_obra(text), public.hoje_sp() to authenticated;

-- ---------------------------------------------------------------------
-- Regras de acesso (Row Level Security)
--   RH e Engenharia: leem e alteram tudo
--   Encarregado: lê cadastros; lê presenças só das suas obras;
--                grava presença só das suas obras e só na data de hoje
--   Sem perfil ativo: não vê nada
-- ---------------------------------------------------------------------
alter table public.perfis        enable row level security;
alter table public.obras         enable row level security;
alter table public.empresas      enable row level security;
alter table public.colaboradores enable row level security;
alter table public.config        enable row level security;
alter table public.presencas     enable row level security;

do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies
           where schemaname = 'public'
             and tablename in ('perfis','obras','empresas','colaboradores','config','presencas')
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- perfis: cada um lê o próprio; admin lê e altera todos.
-- (Criar e excluir contas é feito pela API do app, com a chave de serviço.)
create policy perfis_ler on public.perfis for select to authenticated
  using (id = auth.uid() or public.e_admin());
create policy perfis_alterar on public.perfis for update to authenticated
  using (public.e_admin()) with check (public.e_admin());

-- cadastros: todos com acesso leem; só admin grava
do $$
declare t text;
begin
  foreach t in array array['obras','empresas','colaboradores','config'] loop
    execute format('create policy %I on public.%I for select to authenticated using (public.tem_acesso())', t||'_ler', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.e_admin())', t||'_incluir', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.e_admin()) with check (public.e_admin())', t||'_alterar', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.e_admin())', t||'_excluir', t);
  end loop;
end $$;

-- presenças
create policy presencas_ler on public.presencas for select to authenticated
  using (public.pode_obra(obra_id));
create policy presencas_incluir on public.presencas for insert to authenticated
  with check (public.e_admin() or (public.pode_obra(obra_id) and data = public.hoje_sp()));
create policy presencas_alterar on public.presencas for update to authenticated
  using (public.e_admin() or (public.pode_obra(obra_id) and data = public.hoje_sp()))
  with check (public.e_admin() or (public.pode_obra(obra_id) and data = public.hoje_sp()));
create policy presencas_excluir on public.presencas for delete to authenticated
  using (public.e_admin());

revoke all on public.perfis, public.obras, public.empresas, public.colaboradores, public.config, public.presencas from anon;
grant select, insert, update, delete on public.obras, public.empresas, public.colaboradores, public.config, public.presencas to authenticated;
grant select, update on public.perfis to authenticated;

-- ---------------------------------------------------------------------
-- Atualização em tempo real
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['perfis','obras','empresas','colaboradores','config','presencas'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
exception when undefined_object then
  raise notice 'Publicação supabase_realtime não encontrada; tempo real desativado.';
end $$;

-- ---------------------------------------------------------------------
-- Dados iniciais: lista de funções
-- ---------------------------------------------------------------------
insert into public.config (id, doc) values ('funcoes', jsonb_build_object('lista', jsonb_build_array(
  'Encarregado','PCP','Engenheiro','Montador Steel Frame','Montador Drywall','Eletricista',
  'Encanador','Pedreiro','Ajudante','Meio-Oficial Montagem LSF','Carpinteiro','Armador')))
on conflict (id) do nothing;
