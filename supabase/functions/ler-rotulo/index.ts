// Agnus Coffee · função "ler-rotulo"
// Recebe a foto (base64) de um pacote ou de vários pacotes e devolve
// os dados lidos do rótulo em JSON, usando a API do Claude.
// A chave da API fica só aqui no servidor (secret ANTHROPIC_API_KEY).
//
// Deploy:  supabase functions deploy ler-rotulo
// Secret:  supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
// Só aceita chamadas de quem está logado no app (JWT do Supabase).

const MODEL = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5-5";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const CAMPOS = `"brand":texto|null,"name":texto|null,"country":texto em português|null,"region":texto|null,"farm":texto|null,"producer":texto|null,"variety":texto|null,"process":texto em português|null,"roast":"clara"|"media"|"escura"|null,"roast_label":texto exatamente como no rótulo|null,"species":"arabica"|"blend"|"conilon"|"descaf"|null,"notes":[notas sensoriais exatamente como impressas, traduzidas ao português se estiverem em outro idioma],"weight_g":número|null,"roast_date":"AAAA-MM-DD"|null,"best_before":"AAAA-MM-DD"|null,"altitude_m":número|null,"score":número|null,"harvest":texto|null,"seller":texto|null,"raw_text":texto com as principais linhas lidas do rótulo`;

const REGRAS = `Como ler:
1. Primeiro leia o rótulo inteiro, linha por linha, incluindo letras pequenas, verso, laterais e etiquetas coladas. Coloque em "raw_text" o que conseguiu ler.
2. Depois preencha cada campo copiando o texto exatamente como está escrito (mesma grafia, acentos e nome de fazenda, produtor e variedade). Não resuma nem troque por sinônimos.
3. "brand" é a torrefação ou marca (logotipo). "name" é o nome do café ou do lote, não a marca.
4. Peso: converta para gramas ("1 kg" = 1000, "12 oz" = 340, "500g" = 500). Use o peso líquido.
5. Datas: "torrado em", "torra", "roasted on", "data de torra" vão para roast_date; "validade", "best before", "consumir até" vão para best_before. Converta para AAAA-MM-DD. Se só houver mês e ano, use o dia 01.
6. Altitude: número em metros (se for faixa, use a média). "score" é a pontuação SCA (ex.: 86).
7. Torra: "clara", "media" ou "escura"; média-clara conta como "clara" e média-escura como "escura". Guarde o texto original em roast_label.
8. "country" é o país de origem do grão, em português. Para cafés do Brasil, "region" é a região produtora (ex.: Mantiqueira de Minas, Cerrado Mineiro).
9. Use null quando algo não estiver legível ou não existir. Nunca invente marca, data, peso ou nota.`;

const PROMPTS: Record<string, string> = {
  single: `Você recebe a foto de um pacote de café, que pode ser de qualquer país e em qualquer idioma.
${REGRAS}
Responda SOMENTE um objeto JSON, sem texto fora dele:
{${CAMPOS},"confidence":"alta"|"media"|"baixa"}`,
  shelf: `Você recebe uma foto com um ou mais pacotes de café (o estoque de uma pessoa), de qualquer país e idioma. Identifique CADA pacote visível.
${REGRAS}
Responda SOMENTE um objeto JSON:
{"packages":[{${CAMPOS},"box":[x,y,largura,altura em % da imagem, de 0 a 100]}]}
Um item por pacote, sem repetir; "box" é o retângulo aproximado do pacote na foto.`,
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

function extrairJSON(texto: string) {
  const ini = texto.indexOf("{"), fim = texto.lastIndexOf("}");
  if (ini < 0 || fim <= ini) throw new Error("resposta sem JSON");
  return JSON.parse(texto.slice(ini, fim + 1));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "use POST" }, 405);

  // Só quem está logado no app: confere o token do usuário no Supabase Auth.
  const auth = req.headers.get("Authorization") ?? "";
  const u = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/user`, {
    headers: { Authorization: auth, apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "" },
  });
  if (!u.ok) return json({ error: "entre na sua conta para ler rótulos" }, 401);

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return json({ error: "ANTHROPIC_API_KEY não configurada" }, 500);

  let body: { mode?: string; image?: string; media_type?: string };
  try { body = await req.json(); } catch { return json({ error: "corpo inválido" }, 400); }

  const mode = body.mode === "shelf" ? "shelf" : "single";
  const image = (body.image ?? "").replace(/^data:[^,]+,/, "");
  const mediaType = ["image/jpeg", "image/png", "image/webp"].includes(body.media_type ?? "") ? body.media_type! : "image/jpeg";
  if (!image || image.length > 8_000_000) return json({ error: "imagem ausente ou grande demais" }, 400);

  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: mode === "shelf" ? 6000 : 2000,
      messages: [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: mediaType, data: image } },
          { type: "text", text: PROMPTS[mode] },
        ],
      }],
    }),
  });

  if (!r.ok) {
    const detalhe = await r.text();
    return json({ error: "falha na leitura", status: r.status, detalhe: detalhe.slice(0, 300) }, r.status === 429 ? 429 : 502);
  }
  const out = await r.json();
  const texto = (out.content ?? []).filter((c: { type: string }) => c.type === "text").map((c: { text: string }) => c.text).join("");
  try {
    return json(extrairJSON(texto));
  } catch {
    return json({ error: "não consegui interpretar a resposta" }, 502);
  }
});
