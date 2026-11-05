// Entrega ao navegador apenas os dados públicos de conexão com o Supabase.
// A chave de serviço (SUPABASE_SERVICE_ROLE_KEY) nunca sai do servidor.
module.exports = (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  const url = (process.env.SUPABASE_URL || "").replace(/\/+$/, "");
  const anonKey = process.env.SUPABASE_ANON_KEY || "";
  if (!url || !anonKey) {
    res.status(500).json({ erro: "Configure SUPABASE_URL e SUPABASE_ANON_KEY nas variáveis de ambiente da Vercel." });
    return;
  }
  res.status(200).json({ url, anonKey, loginDomain: process.env.LOGIN_DOMAIN || "usuarios.efetivo.internal" });
};
