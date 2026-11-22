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

const CAMPOS = `"brand":texto|null,"name":texto|null,"country":texto em português|null,"region":texto|null,"producer":texto|null,"variety":texto|null,"process":texto em português|null,"roast":"clara"|"media"|"escura"|null,"species":"arabica"|"blend"|"conilon"|"descaf"|null,"notes":[até 4 notas sensoriais em português],"weight_g":número|null,"roast_date":"AAAA-MM-DD"|null,"altitude_m":número|null,"seller":texto|null`;

const PROMPTS: Record<string, string> = {
  single: `Você recebe a foto de um pacote de café, que pode ser de qualquer país e em qualquer idioma. Leia o rótulo com atenção e responda SOMENTE um objeto JSON, sem texto fora dele:
{${CAMPOS},"confidence":"alta"|"media"|"baixa"}
Regras: use null quando algo não estiver legível; não invente marca, data ou peso. "country" é o país de origem do grão. "seller" só se o rótulo indicar loja ou cafeteria. Torra média-clara conta como "clara"; média-escura como "escura".`,
  shelf: `Você recebe uma foto com um ou mais pacotes de café (o estoque de uma pessoa), de qualquer país e idioma. Identifique CADA pacote visível e responda SOMENTE um objeto JSON:
{"packages":[{${CAMPOS},"box":[x,y,largura,altura em % da imagem, de 0 a 100]}]}
Regras: um item por pacote, sem repetir; use null no que não estiver legível e não invente marca, peso ou data; "box" é o retângulo aproximado do pacote na foto. Torra média-clara conta como "clara"; média-escura como "escura".`,
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

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return json({ error: "ANTHROPIC_API_KEY não configurada" }, 500);

  let body: { mode?: string; image?: string; media_type?: string };
  try { body = await req.json(); } catch { return json({ error: "corpo inválido" }, 400); }

  const mode = body.mode === "shelf" ? "shelf" : "single";
  const image = (body.image ?? "").replace(/^data:[^,]+,/, "");
  const mediaType = ["image/jpeg", "image/png", "image/webp"].includes(body.media_type ?? "") ? body.media_type! : "image/jpeg";
  if (!image || image.length > 6_000_000) return json({ error: "imagem ausente ou grande demais" }, 400);

  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: mode === "shelf" ? 3000 : 1200,
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
