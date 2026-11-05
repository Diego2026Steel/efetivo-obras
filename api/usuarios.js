// Gestão de contas de acesso (somente RH e Engenharia).
// Roda no servidor da Vercel com a chave de serviço do Supabase.
//
// POST /api/usuarios  { acao, ... }
//   configurar  { nome, usuario, senha }            primeiro administrador (só quando não há nenhum usuário)
//   criar       { nome, usuario, senha, papel, obras }
//   senha       { id, senha }                        redefine a senha de alguém
//   ativo       { id, ativo }                        bloqueia ou libera o login
//   excluir     { id }                               remove a conta

const URL_SB = (process.env.SUPABASE_URL || "").replace(/\/+$/, "");
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY || "";
const DOMAIN = process.env.LOGIN_DOMAIN || "usuarios.efetivo.internal";
const PAPEIS = ["RH", "ENG", "ENC"];

// Chaves antigas (JWT "service_role") vão também no Authorization; as novas (sb_secret_...) só no apikey.
const adminHeaders = SERVICE.startsWith("sb_secret_")
  ? { apikey: SERVICE, "Content-Type": "application/json" }
  : { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" };

class Falha extends Error { constructor(status, msg) { super(msg); this.status = status; } }

async function sb(path, opts = {}) {
  const r = await fetch(URL_SB + path, { ...opts, headers: { ...adminHeaders, ...(opts.headers || {}) } });
  const txt = await r.text();
  let body = null; try { body = txt ? JSON.parse(txt) : null; } catch { body = txt; }
  if (!r.ok) {
    const msg = (body && (body.msg || body.message || body.error_description || body.error)) || `Erro ${r.status}`;
    throw new Falha(r.status >= 500 ? 502 : 400, traduz(String(msg)));
  }
  return body;
}

function traduz(m) {
  if (/already (been )?registered|already exists|duplicate/i.test(m)) return "Já existe um usuário com esse nome de acesso.";
  if (/password.*(at least|short|weak)/i.test(m)) return "A senha é fraca ou curta demais. Use pelo menos 6 caracteres.";
  if (/invalid.*email|email.*invalid/i.test(m)) return "O nome de usuário não foi aceito. Use letras, números, ponto ou hífen.";
  return m;
}

const normUser = (u) => String(u || "").trim().toLowerCase();
const userOk = (u) => /^[a-z0-9][a-z0-9._-]{2,39}$/.test(u);
const senhaOk = (s) => typeof s === "string" && s.length >= 6 && s.length <= 72;
const obrasOk = (o) => Array.isArray(o) && o.every((x) => typeof x === "string" && x.length < 100) ? o : [];

async function chamador(req) {
  const tok = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (!tok) throw new Falha(401, "Entre no app novamente.");
  const r = await fetch(URL_SB + "/auth/v1/user", { headers: { apikey: SERVICE, Authorization: `Bearer ${tok}` } });
  if (!r.ok) throw new Falha(401, "Sua sessão expirou. Entre no app novamente.");
  const u = await r.json();
  const rows = await sb(`/rest/v1/perfis?id=eq.${encodeURIComponent(u.id)}&select=id,papel,ativo`);
  const p = rows && rows[0];
  if (!p || !p.ativo || !["RH", "ENG"].includes(p.papel)) throw new Falha(403, "Somente RH e Engenharia podem gerenciar acessos.");
  return u.id;
}

async function criarConta({ nome, usuario, senha, papel, obras }) {
  const u = normUser(usuario);
  nome = String(nome || "").trim().slice(0, 120);
  if (!nome) throw new Falha(400, "Informe o nome da pessoa.");
  if (!userOk(u)) throw new Falha(400, "Usuário inválido. Use de 3 a 40 caracteres: letras minúsculas, números, ponto, hífen ou sublinhado.");
  if (!senhaOk(senha)) throw new Falha(400, "A senha precisa ter de 6 a 72 caracteres.");
  if (!PAPEIS.includes(papel)) throw new Falha(400, "Perfil inválido.");
  const conta = await sb("/auth/v1/admin/users", {
    method: "POST",
    body: JSON.stringify({ email: `${u}@${DOMAIN}`, password: senha, email_confirm: true, user_metadata: { nome, usuario: u } }),
  });
  const id = conta.id || (conta.user && conta.user.id);
  const doc = { nome, usuario: u, papel, obras: papel === "ENC" ? obrasOk(obras) : [], ativo: true, criadoEm: new Date().toISOString() };
  try {
    await sb("/rest/v1/perfis", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ id, doc }) });
  } catch (e) {
    await sb(`/auth/v1/admin/users/${id}`, { method: "DELETE" }).catch(() => {});
    throw e;
  }
  return { id, usuario: u };
}

module.exports = async (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  try {
    if (req.method !== "POST") throw new Falha(405, "Use POST.");
    if (!URL_SB || !SERVICE) throw new Falha(500, "Configure SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY nas variáveis de ambiente da Vercel.");
    const b = typeof req.body === "string" ? JSON.parse(req.body || "{}") : (req.body || {});

    if (b.acao === "configurar") {
      const existe = await sb("/rest/v1/perfis?select=id&limit=1");
      if (existe && existe.length) throw new Falha(409, "O app já foi configurado. Entre com seu usuário e senha.");
      const r = await criarConta({ ...b, papel: "RH" });
      return res.status(200).json(r);
    }

    const eu = await chamador(req);
    const id = String(b.id || "");
    const idOk = /^[0-9a-f-]{36}$/i.test(id);

    switch (b.acao) {
      case "criar":
        return res.status(200).json(await criarConta(b));
      case "senha":
        if (!idOk) throw new Falha(400, "Usuário não informado.");
        if (!senhaOk(b.senha)) throw new Falha(400, "A senha precisa ter de 6 a 72 caracteres.");
        await sb(`/auth/v1/admin/users/${id}`, { method: "PUT", body: JSON.stringify({ password: b.senha }) });
        return res.status(200).json({ ok: true });
      case "ativo": {
        if (!idOk) throw new Falha(400, "Usuário não informado.");
        if (id === eu && !b.ativo) throw new Falha(400, "Você não pode desativar o seu próprio acesso.");
        await sb(`/auth/v1/admin/users/${id}`, { method: "PUT", body: JSON.stringify({ ban_duration: b.ativo ? "none" : "876000h" }) });
        const rows = await sb(`/rest/v1/perfis?id=eq.${id}&select=doc`);
        if (rows && rows[0]) {
          await sb(`/rest/v1/perfis?id=eq.${id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ doc: { ...rows[0].doc, ativo: !!b.ativo } }) });
        }
        return res.status(200).json({ ok: true });
      }
      case "excluir":
        if (!idOk) throw new Falha(400, "Usuário não informado.");
        if (id === eu) throw new Falha(400, "Você não pode excluir o seu próprio acesso.");
        await sb(`/auth/v1/admin/users/${id}`, { method: "DELETE" });
        return res.status(200).json({ ok: true });
      default:
        throw new Falha(400, "Ação desconhecida.");
    }
  } catch (e) {
    const status = e instanceof Falha ? e.status : 500;
    res.status(status).json({ erro: e instanceof Falha ? e.message : "Erro inesperado no servidor." });
  }
};
