// Edge Function "admin-users": cria, exclui e redefine senha de usuários. Só o Master pode chamar.
import { createClient } from 'npm:@supabase/supabase-js@2';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });
const key = (multi: string, legacy: string) => { try { return JSON.parse(Deno.env.get(multi)!)['default']; } catch { return Deno.env.get(legacy)!; } };
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const pub = key('SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_ANON_KEY');
    const sec = key('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY');
    const auth = req.headers.get('Authorization') ?? '';
    const caller = createClient(url, pub, { global: { headers: { Authorization: auth } } });
    const { data: u } = await caller.auth.getUser(auth.replace(/^Bearer\s+/i, ''));
    if (!u?.user) return json({ message: 'Não autenticado.' }, 401);
    const { data: me } = await caller.from('profiles').select('role').eq('id', u.user.id).single();
    if (me?.role !== 'master') return json({ message: 'Apenas o usuário Master pode fazer isso.' }, 403);
    const admin = createClient(url, sec, { auth: { persistSession: false } });
    const b = await req.json();
    if (b.action === 'create') {
      if (!b.email || String(b.password ?? '').length < 8) return json({ message: 'Informe e-mail e senha com 8+ caracteres.' }, 400);
      const { data, error } = await admin.auth.admin.createUser({ email: b.email, password: b.password, email_confirm: true, user_metadata: { full_name: b.full_name || null } });
      if (error) return json({ message: error.message }, 400);
      return json({ id: data.user.id });
    }
    if (b.action === 'delete' || b.action === 'reset') {
      if (!b.id) return json({ message: 'Usuário não informado.' }, 400);
      const { data: t } = await admin.from('profiles').select('role').eq('id', b.id).single();
      if (b.action === 'delete') {
        if (b.id === u.user.id || t?.role === 'master') return json({ message: 'A conta Master não pode ser excluída.' }, 400);
        const { error } = await admin.auth.admin.deleteUser(b.id);
        return error ? json({ message: error.message }, 400) : json({ ok: true });
      }
      if (String(b.password ?? '').length < 8) return json({ message: 'A senha precisa ter 8+ caracteres.' }, 400);
      const { error } = await admin.auth.admin.updateUserById(b.id, { password: b.password });
      return error ? json({ message: error.message }, 400) : json({ ok: true });
    }
    return json({ message: 'Ação inválida.' }, 400);
  } catch (e) { return json({ message: String((e as Error)?.message ?? e) }, 500); }
});
