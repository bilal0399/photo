// Admin-only account management for the Diwan dashboard and app.
//
// Creating, editing and deleting accounts needs the service role key, which
// must never ship inside the app or the website. This function holds it on
// the server and only acts after checking that the caller's own account has
// role = 'admin' in `profiles`.
//
// Deploy:  supabase functions deploy admin-users
// Body:    { action: 'list' | 'create' | 'update' | 'delete', ... }

import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

const fail = (message: string, status = 400) => json({ error: message }, status);

const ROLES = ['admin', 'user'];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return fail('Method not allowed', 405);

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // --- who is calling? ---
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: auth } = await admin.auth.getUser(token);
  const caller = auth?.user;
  if (!caller) return fail('يجب تسجيل الدخول', 401);
  const { data: me } = await admin.from('profiles').select('role').eq('id', caller.id).maybeSingle();
  if (me?.role !== 'admin') return fail('هذه العملية متاحة للمدير فقط', 403);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail('طلب غير صالح');
  }
  const str = (key: string) => (typeof body[key] === 'string' ? (body[key] as string).trim() : '');

  try {
    switch (body.action) {
      case 'list': {
        const { data, error } = await admin.auth.admin.listUsers({ perPage: 1000 });
        if (error) throw error;
        const { data: profiles } = await admin.from('profiles').select('id, username, role');
        const byId = new Map((profiles ?? []).map((p) => [p.id, p]));
        const users = data.users.map((u) => ({
          id: u.id,
          email: u.email ?? '',
          username: byId.get(u.id)?.username ?? (u.user_metadata?.username as string) ?? '',
          role: byId.get(u.id)?.role ?? 'user',
          created_at: u.created_at,
          last_sign_in_at: u.last_sign_in_at ?? null,
          is_self: u.id === caller.id,
        }));
        return json({ users });
      }

      case 'create': {
        const email = str('email');
        const password = typeof body.password === 'string' ? body.password : '';
        const username = str('username');
        const role = str('role') || 'user';
        if (!email || !username) return fail('الاسم والبريد مطلوبان');
        if (password.length < 6) return fail('كلمة المرور ضعيفة (٦ أحرف على الأقل)');
        if (!ROLES.includes(role)) return fail('دور غير معروف');

        const { data, error } = await admin.auth.admin.createUser({
          email,
          password,
          email_confirm: true,
          user_metadata: { username },
        });
        if (error) {
          if (/already|registered|exists/i.test(error.message)) return fail('هذا البريد مسجّل مسبقًا');
          throw error;
        }
        // A signup trigger may already have created the profile; upsert either way.
        const { error: profileError } = await admin
          .from('profiles')
          .upsert({ id: data.user.id, username, role }, { onConflict: 'id' });
        if (profileError) throw profileError;
        return json({ id: data.user.id });
      }

      case 'update': {
        const id = str('id');
        if (!id) return fail('المستخدم غير محدد');
        const role = str('role');
        if (role && !ROLES.includes(role)) return fail('دور غير معروف');
        if (id === caller.id && role && role !== 'admin') {
          return fail('لا يمكنك إزالة صلاحية المدير عن حسابك');
        }

        const attributes: Record<string, unknown> = {};
        const email = str('email');
        const username = str('username');
        const password = typeof body.password === 'string' ? body.password : '';
        if (email) attributes.email = email;
        if (password) {
          if (password.length < 6) return fail('كلمة المرور ضعيفة (٦ أحرف على الأقل)');
          attributes.password = password;
        }
        if (username) attributes.user_metadata = { username };
        if (Object.keys(attributes).length > 0) {
          const { error } = await admin.auth.admin.updateUserById(id, attributes);
          if (error) {
            if (/already|registered|exists/i.test(error.message)) return fail('هذا البريد مسجّل مسبقًا');
            throw error;
          }
        }

        const profile: Record<string, unknown> = {};
        if (username) profile.username = username;
        if (role) profile.role = role;
        if (Object.keys(profile).length > 0) {
          const { error } = await admin.from('profiles').update(profile).eq('id', id);
          if (error) throw error;
        }
        return json({ ok: true });
      }

      case 'delete': {
        const id = str('id');
        if (!id) return fail('المستخدم غير محدد');
        if (id === caller.id) return fail('لا يمكنك حذف حسابك الحالي');
        // Profile first, so a foreign key without cascade cannot block the delete.
        await admin.from('profiles').delete().eq('id', id);
        const { error } = await admin.auth.admin.deleteUser(id);
        if (error) throw error;
        return json({ ok: true });
      }

      default:
        return fail('إجراء غير معروف');
    }
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return fail(`خطأ في الخادم: ${message}`, 500);
  }
});
