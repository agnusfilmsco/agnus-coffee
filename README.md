# Agnus Coffee · app

App de café da Agnus: receitas ajustáveis, timer, estoque com foto, diário, cafeína por perfil, clube e radar de marcas.

- **app/**: o aplicativo (web app instalável no celular, PWA). HTML, CSS e JavaScript, sem etapa de build.
- **app/admin.html**: painel da equipe (cadastros, acessos, cliques, cupons, vendas, parceiros, radar).
- **supabase/migrations/**: banco de dados em etapas (001 base, 002 painel, 003 casa). Rode em ordem.
- **supabase/functions/ler-rotulo/**: função no servidor que lê o rótulo pela foto usando a API do Claude.
- **.github/workflows/pages.yml**: publica o app no GitHub Pages automaticamente.

Sem configuração, o app já abre em **modo local**: tudo funciona, mas os dados ficam só no aparelho, sem login e sem leitura de foto. Os passos abaixo ligam a nuvem.

---

## O que você precisa criar (contas)

| Conta | Para quê | Custo para começar |
|---|---|---|
| Supabase (supabase.com) | Login Google/e-mail, banco de dados, fotos, função de IA | Plano gratuito |
| Google Cloud Console | Botão "Continuar com Google" | Gratuito |
| Anthropic Console (console.anthropic.com) | Leitura do rótulo pela foto | Pago por uso (cada foto lida tem um custo pequeno) |
| GitHub (conta agnusfilmsco) | Hospedar o app com link próprio | Gratuito |

---

## Passo a passo

### 1. Criar o projeto no Supabase
1. Em supabase.com, crie um projeto (região: São Paulo).
2. Vá em **Project Settings › API** e copie **Project URL** e a chave **anon public**.
3. Abra `app/config.js` e cole os dois valores.

### 2. Criar o banco
No Supabase, abra **SQL Editor › New query** e rode, um de cada vez e nesta ordem:
1. `supabase/migrations/001_base.sql`: estado de cada pessoa, radar de marcas, equipe e fotos.
2. `supabase/migrations/002_painel.sql`: cadastros, acessos, eventos, parceiros (links e cupons) e vendas.
3. `supabase/migrations/003_casa.sql`: casas com estoque compartilhado.

### 3. Ligar o login com e-mail
Já vem ativo. A pessoa digita o e-mail e recebe um link para entrar, sem senha.
- Em **Authentication › URL Configuration**, coloque em **Site URL** o endereço final do app (passo 6) e adicione o mesmo endereço em **Redirect URLs**.
- Opcional: em **Authentication › Email Templates**, escreva o e-mail em português com a cara da Agnus.
- Para muitos usuários, configure um provedor de e-mail próprio em **Authentication › SMTP** (o envio padrão do Supabase tem limite baixo por hora).

### 4. Ligar o login com Google
1. No Google Cloud Console, crie um projeto e vá em **APIs e serviços › Tela de consentimento OAuth** (tipo Externo, nome "Agnus Coffee", logo e e-mail de suporte).
2. Em **Credenciais › Criar credenciais › ID do cliente OAuth**, tipo **Aplicativo da Web**.
3. Em **URIs de redirecionamento autorizados**, cole: `https://SEU-PROJETO.supabase.co/auth/v1/callback`
4. Copie **Client ID** e **Client Secret**.
5. No Supabase: **Authentication › Providers › Google**, ative e cole os dois valores.

### 5. Ligar a leitura de foto (IA)
1. Crie uma chave em console.anthropic.com e adicione créditos.
2. Instale a Supabase CLI no computador (instruções em supabase.com/docs/guides/cli).
3. Na pasta do projeto, rode:
   ```bash
   supabase login
   supabase link --project-ref SEU-PROJETO
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
   supabase functions deploy ler-rotulo
   ```
A chave fica só no servidor. A função aceita apenas quem está logado no app.

### 6. Publicar o app
**GitHub Pages (recomendado):**
1. Crie o repositório `agnus-coffee` na conta agnusfilmsco e envie esta pasta inteira.
2. Em **Settings › Pages › Build and deployment**, escolha **GitHub Actions**.
3. A cada envio para a branch `main`, o app é publicado em `https://agnusfilmsco.github.io/agnus-coffee/`.
4. Volte ao passo 3 e coloque esse endereço no Supabase.

Domínio próprio (ex.: `app.agnuscoffee.com.br`): em **Settings › Pages › Custom domain** e no DNS do domínio.

**Alternativa rápida:** em netlify.com, arraste a pasta `app/` para publicar.

### 7. Virar equipe (ver o radar de marcas)
Entre no app uma vez com seu e-mail. Depois, no **SQL Editor** do Supabase:
```sql
insert into public.admins (user_id) select id from auth.users where email = 'seu@email.com';
```
Repita para cada pessoa da equipe. Quem é equipe vê o **Radar de marcas** no fim da aba Clube, com todos os pacotes cadastrados pela comunidade, e pode marcar marcas como "Em conversa" ou "Fechou".

### 8. Painel da equipe
Abra `https://agnusfilmsco.github.io/agnus-coffee/admin.html` e entre com o mesmo e-mail cadastrado como equipe (passo 7). Lá você vê, ao vivo:
- **Resumo:** cadastros, novos na semana, ativos, acessos de hoje, cliques para comprar, cupons copiados, vendas e receita.
- **Cadastros:** nome, e-mail, se entrou por Google ou e-mail, data, último acesso, número de acessos, moedores, se quer assinar. Exporta CSV (abre no Excel ou Google Sheets).
- **Compras e cupons:** cliques e cupons copiados por parceiro e quem clicou.
- **Vendas:** a venda acontece no site do parceiro. Pegue o relatório de vendas por cupom com ele e lance aqui (data, cupom, valor). Depois dá para automatizar com webhook da loja.
- **Parceiros:** link da loja, cupom e benefício de cada marca. Salvou, o app já mostra no botão "Comprar".
- **Radar de marcas:** marcas que a comunidade tem em casa e status da conversa.

Os mesmos dados ficam no Supabase em **Table Editor** (tabelas `perfis`, `eventos`, `vendas`, `parceiros`), caso queira consultar direto.

### 9. Instalar no celular
- **iPhone:** abra o link no Safari › Compartilhar › Adicionar à Tela de Início.
- **Android:** abra no Chrome › menu › Instalar app.

---

## Versão 1.3 (25/11/2026)
- Banco: rodar `supabase/migrations/004_comunidade.sql` (já rodado no projeto). Cria vitrine, amizades, pre_cadastro_clube, recomendacoes e config.
- Locais de estoque (Casa, Produtora…): cada pacote tem `loc`; o local ativo define de onde sai o café. Estado do usuário migrado para STATE_V 3 sem perda.
- Nota de 1 a 5 para cada café (`cafeNotas`) e, em cada preparo, nota, % bebido (cafeína proporcional) e anotação.
- Receitas: Melitta com técnica própria (pré-infusão, dois despejos, escorrimento lento; medida ABIC 80 g/L) + Melitta especial 1:16; Chemex com bloom de 45 s e drenagem até 4:30.
- Comunidade: código de amigo de 6 caracteres, receitas e cafés favoritos dos amigos, opção de mostrar para toda a comunidade, Clube Agnus bloqueado com pré-cadastro e meta (editável no painel › Clube).
- Recomendações de compra na tela inicial, editáveis no painel › Recomendações.
- Leitura de rótulo: foto enviada em 2000 px (estoque inteiro em 2400 px) e prompt que transcreve o rótulo linha a linha.

## Recursos novos desta versão

- **Equipamento:** cada pessoa cadastra seus moedores (Comandante, Timemore, Baratza Encore ou qualquer outro, com a escala e o número que usa na V60). Em cada receita, o app mostra a faixa sugerida no moedor dela, deixa ajustar o número, salva o que foi usado e sugere esse número da próxima vez. A avaliação da xícara cita o número ("ficou ácido: tente 22, hoje foi 24").
- **Comprar com cupom:** cada café de marca parceira mostra o cupom (com botão copiar) e o botão "Comprar na marca", que abre a loja com o rastreio `utm_source=agnuscoffee`. O clique e a cópia do cupom vão para o painel.
- **Timer com som:** bipes nos 10 segundos antes de cada etapa, 3-2-1 mais forte, toque e vibração na hora de despejar e um toque final. O botão no topo do timer alterna entre bipes, bipes com voz (diz a etapa: "Despeje até 120 gramas") e mudo. No iPhone, o som do timer depende de o celular não estar no silencioso.
- **Casa:** estoque compartilhado. Uma pessoa cria a casa e manda o código. Quem entra junta seus pacotes ao estoque da casa. Cada preparo desconta para todos na hora (sem um apagar o desconto do outro), e a atividade mostra quem usou o quê. Quem sai leva uma cópia do estoque.

## Como os dados ficam guardados

- **user_state**: um registro por pessoa com estoque, diário, receitas, coleção, perfil de cafeína e preferências. O app salva sozinho a cada mudança (cerca de 1 segundo depois) e também guarda uma cópia no aparelho para funcionar sem internet.
- **radar_pacotes**: uma linha por pacote cadastrado (marca, café, país, região, variedade, processo, onde comprou e se a marca era parceira, conhecida ou nova). Só a equipe lê.
- **marcas**: status de negociação por marca. Só a equipe lê e altera.
- **Storage › pacotes**: fotos dos pacotes, uma pasta por pessoa. As fotos abrem por link público (não há dado pessoal nelas, só o pacote).

Quem entra pela primeira vez já com dados no aparelho (modo local) leva tudo para a conta automaticamente.

## Onde mexer

- **Marcas parceiras:** `PARTNERS` no `app/index.html`.
- **Catálogo de cafés:** `COFFEES`. **Receitas:** `RECIPES`. **Caixa do mês:** `BOX`. **Encontros:** `EVENTS`.
- **Cores e fontes:** bloco `:root` no início do `<style>`. O laranja da marca é `--agnus: #CF5737`.
- **Modelo de IA:** variável `ANTHROPIC_MODEL` nos secrets do Supabase (padrão `claude-sonnet-5-5`).

## Próximas etapas sugeridas

1. Logo e ícones oficiais no lugar da ovelha desenhada (`lamb()` no código e a pasta `app/icons/`).
2. Pagamento da assinatura do clube e da loja (Mercado Pago, Stripe ou Pagar.me), com webhook gravando o status no Supabase.
3. Painel da equipe em página separada: exportar o radar, mapa por cidade, gestão da caixa do mês.
4. Versão nas lojas (App Store e Google Play) com Capacitor ou Expo, reaproveitando este código.
5. Revisão dos textos de cafeína por um nutricionista antes do lançamento.

---

## Atualizar o app sem ninguém perder dados

Os dados de cada pessoa ficam no Supabase (tabela `user_state`), não nos arquivos do app. Atualizar o app troca só a "casca"; os dados continuam lá.

1. **Teste antes:** mantenha um segundo projeto Supabase de teste e uma cópia do app apontando para ele (outro `config.js`). Mude ali primeiro.
2. **Ao mudar o formato de algum dado** (ex.: estoque passa a guardar a cidade da compra): aumente `STATE_V` no `index.html` e escreva o passo em `MIGRATIONS`, convertendo o dado antigo para o novo. Nunca apague nem renomeie um campo sem converter.
3. **Ao mudar o banco:** crie um arquivo novo em `supabase/migrations/` (ex.: `004_cidade.sql`) só com `alter table ... add column ...`. Nunca use `drop` em tabela ou coluna com dados.
4. **Troque a versão do cache** em `app/sw.js` (ex.: `agnus-coffee-v2` → `v3`) e `APP_VERSION` no `index.html`.
5. **Publique:** envie para a branch `main`. Em 1 a 2 minutos o GitHub Pages atualiza; o celular de cada pessoa baixa a versão nova sozinho e mostra "App atualizado. Seus dados continuam salvos."
6. **Backup:** antes de cada mudança no banco, exporte em Supabase › Database › Backups (planos pagos fazem backup diário automático; no gratuito, exporte manualmente).

Proteções já no código: migração automática dos dados (`migrate`), carimbo de revisão em cada salvamento (`_rev`) para um celular desatualizado não sobrescrever o que foi feito em outro, e cópia local no aparelho para funcionar sem internet.
