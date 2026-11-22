// Agnus Coffee · configuração do servidor (Supabase)
// Supabase > Project Settings > API: copie "Project URL" e a chave "anon public".
// A chave anon pode ficar no app: a segurança vem das regras (RLS) do schema.sql.
// Enquanto estiver com os valores de exemplo, o app funciona em modo local (sem login).
window.AGNUS_CONFIG = {
  SUPABASE_URL: "https://SEU-PROJETO.supabase.co",
  SUPABASE_ANON_KEY: "COLE-AQUI-A-CHAVE-ANON-PUBLIC"
};
