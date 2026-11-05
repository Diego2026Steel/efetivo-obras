# Efetivo de Obras · iBUILD

Controle diário de efetivo por obra: presença lançada pelo encarregado; cadastros de obras, empresas e colaboradores pelo RH e pela Engenharia; painel, consolidado e relatórios.

- **Front-end:** `index.html` (página única, sem build), instalável no celular.
- **Banco e login:** Supabase (PostgreSQL + Auth). As permissões de cada perfil são travas do próprio banco (Row Level Security).
- **Servidor:** funções da Vercel em `api/`. Elas criam e gerenciam usuários com a chave de serviço, que nunca chega ao navegador.

## Perfis

| Perfil | O que pode fazer |
|---|---|
| RH / escritório | Tudo: cadastros, presença de qualquer dia, relatórios, CSV, acessos |
| Engenharia | Igual ao RH |
| Encarregado | Lança presença **só hoje** e **só nas obras liberadas**; vê os relatórios dessas obras; não exporta CSV nem vê cadastros |

## Implantação (primeira vez)

### 1. Supabase
1. Crie um projeto na região **South America (São Paulo)**.
2. Vá em **SQL Editor → New query**, cole todo o conteúdo de [`supabase/schema.sql`](supabase/schema.sql) e clique em **Run**. A mensagem esperada é "Success. No rows returned".
3. Vá em **Authentication → Sign In / Providers → Email** e:
   - **desligue "Allow new users to sign up"** (só o RH cria contas);
   - desligue **"Confirm email"**.
4. Vá em **Project Settings → API Keys** e anote:
   - a **Project URL** (`https://xxxx.supabase.co`), em Project Settings → Data API;
   - a chave **anon / public**;
   - a chave **service_role / secret** (**secreta**: não compartilhe e não coloque no código).

   Se aparecerem as abas "API Keys" e "Legacy API Keys", use as chaves da aba **Legacy** (anon e service_role).

### 2. Vercel
1. **Add New → Project** e importe o repositório `efetivo-obras` do GitHub.
2. Framework Preset: **Other**. Não precisa de comando de build.
3. Em **Environment Variables**, adicione:

| Nome | Valor |
|---|---|
| `SUPABASE_URL` | Project URL do Supabase |
| `SUPABASE_ANON_KEY` | chave anon / public |
| `SUPABASE_SERVICE_ROLE_KEY` | chave service_role / secret |

4. Clique em **Deploy**. O endereço fica como `https://efetivo-obras.vercel.app`. Um domínio próprio pode ser configurado em Settings → Domains.

### 3. Primeiro acesso
1. Abra o endereço do app. Aparece a tela de **Configuração inicial**.
2. Crie o seu usuário (nome, usuário e senha). Ele já entra como **RH**.
3. Cadastre **Obras**, **Empresas** e **Colaboradores** (dá para importar do Excel).
4. Em **Acessos → Novo usuário**, crie os encarregados (usuário, senha inicial e obras) e as pessoas de Engenharia/RH.

### 4. Instalar no celular
- **iPhone (Safari):** botão Compartilhar → **Adicionar à Tela de Início**.
- **Android (Chrome):** menu ⋮ → **Instalar app** (ou "Adicionar à tela inicial").

## Atualizações
Cada alteração enviada ao GitHub (branch `main`) é publicada sozinha pela Vercel em cerca de 1 minuto.

Se o `schema.sql` mudar, rode-o de novo no SQL Editor. O script pode ser executado várias vezes sem apagar dados.

## Dúvidas comuns
- **"App não configurado"**: falta alguma variável de ambiente na Vercel. Depois de corrigir, use **Redeploy**.
- **Encarregado esqueceu a senha:** RH → Acessos → abrir o usuário → **Redefinir senha**.
- **Bloquear alguém:** Acessos → abrir o usuário → desligar **Acesso ativo**. O login e os dados ficam bloqueados na hora.
- **Backup:** o Supabase faz backup diário (plano gratuito: 7 dias via suporte; plano Pro: restauração no painel). Os relatórios também podem ser exportados em CSV.

## Estrutura
```
index.html              app (HTML + CSS + JS)
manifest.webmanifest    instalação no celular
icons/                  ícones do app
api/config.js           entrega URL e chave pública do Supabase ao navegador
api/usuarios.js         criar, redefinir senha, bloquear e excluir usuários
supabase/schema.sql     tabelas, regras de acesso e dados iniciais
vercel.json             cabeçalhos de segurança
```
