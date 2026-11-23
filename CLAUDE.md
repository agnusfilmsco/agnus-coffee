# Agnus Coffee · regras do projeto

## Branding (obrigatório em todo o app e no painel)
Fonte: AGNUS_BRANDBOOK.pdf e Key Visual da Agnus.

- **Cores (únicas):** laranja `#F43A0F` (principal), laranja claro `#EF5941`, marrom `#633523`, cinza `#9B9B9B`, preto `#0A0A0A`, mais branco e cinza-claro de fundo. Não usar tons rosados nem outros marrons.
- **Tipografia:** Helvetica Neue em tudo; títulos em caixa alta, negrito, entrelinha curta (~0.92) e espaçamento negativo (~-0.045em). Destaques curtos em **Playfair Display itálico**, normalmente entre parênteses `(a the story co.)` ou como linha de apoio.
- **Recursos gráficos da marca:** frases entre chaves `{CAFÉS QUE CONTAM HISTÓRIAS}`, microtexto em caixa alta "AGNUS 2026. TODOS OS DIREITOS RESERVADOS. BRASÍLIA // BSB // BRASIL", coordenadas `15°47′38″ SUL 47°52′58″ OESTE`, separador `//`.
- **Logo:** usar só os arquivos oficiais em `app/brand/` (`agnus-wordmark*.png`, `agnus-mark.png` = ovelha preta no quadrado laranja, `agnus-sheep.png`). Nunca redesenhar a ovelha nem o logotipo.
- Blocos de cor chapada (laranja com texto preto, marrom, preto). Sem degradês decorativos.

## Dados
- Supabase projeto `skdsxymoeikfjuwxikkx` (São Paulo). Mudanças de banco só como novos arquivos em `supabase/migrations/` (004, 005…), nunca apagando colunas.
- Formato do estado do usuário mudou? Aumentar `STATE_V` e escrever o passo em `MIGRATIONS` no `app/index.html`.
- Toda publicação: trocar a versão do cache em `app/sw.js`.
