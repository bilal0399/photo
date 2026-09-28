/*
 * Data layer. Mirrors the app's services (the service classes under lib/features) so both
 * write the same rows and storage paths:
 *   documents        -> bucket "attachments", scans under documents/scanned/
 *   tasks            -> bucket "tasks"
 *   options          -> lookup lists (category, value, sort_order)
 *   admin-users      -> Edge Function for account management
 */
(function () {
  'use strict';

  const cfg = window.DIWAN_CONFIG;
  const client = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseKey, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: 'diwan-dashboard-auth' },
  });

  const DOC_BUCKET = 'attachments';
  const TASK_BUCKET = 'tasks';
  const SCANNED_PREFIX = 'documents/scanned/';
  const APPROVED = 'تمت الموافقة';
  const DEFAULT_STATUS = 'قيد المراجعة';
  const OUTGOING = 'صادر';
  const INCOMING = 'وارد';
  const DEFAULT_RECIPIENTS = ['الوزارة', 'قيادة الفيلق'];

  /** Lookup list categories, with the document column each one fills. */
  const CATEGORIES = [
    { key: 'book_type', label: 'أنواع الكتب', column: 'book_type' },
    { key: 'requester', label: 'الجهات المقدمة (وارد)', column: 'requester', direction: INCOMING },
    { key: 'recipient', label: 'الجهات المستقبلة (صادر)', column: 'requester', direction: OUTGOING },
    { key: 'status', label: 'حالات الكتاب', column: 'status' },
  ];

  const IMAGE_EXT = ['.jpg', '.jpeg', '.png'];
  const extOf = (path) => {
    const m = /\.[^./\\]+$/.exec(path || '');
    return m ? m[0].toLowerCase() : '';
  };
  const isImagePath = (path) => IMAGE_EXT.includes(extOf(path));

  const pad = (n) => String(n).padStart(2, '0');
  const rand = () => Math.floor(Math.random() * 0xffffff).toString(16);

  function fail(error) {
    if (!error) return;
    const message = error.message || String(error);
    throw new Error(message);
  }

  const state = { documents: null, tasks: null, options: null, profile: null };

  // ------------------------------------------------------------------ auth

  async function signIn(email, password) {
    const { error } = await client.auth.signInWithPassword({ email: email.trim(), password });
    fail(error);
  }

  async function signOut() {
    await client.auth.signOut();
    state.documents = state.tasks = state.options = state.profile = null;
  }

  async function currentSession() {
    const { data } = await client.auth.getSession();
    return data.session;
  }

  /** The signed-in user's profile: { id, email, username, role }. */
  async function profile() {
    const session = await currentSession();
    if (!session) return null;
    const user = session.user;
    const { data } = await client.from('profiles').select('*').eq('id', user.id).maybeSingle();
    const email = user.email || '';
    state.profile = {
      id: user.id,
      email,
      username: (data && data.username) || email.split('@')[0],
      role: (data && data.role) || 'user',
    };
    return state.profile;
  }

  // ------------------------------------------------------------- documents

  async function documents(force) {
    if (state.documents && !force) return state.documents;
    const { data, error } = await client.from('documents').select('*').order('doc_date', { ascending: false });
    fail(error);
    state.documents = data || [];
    return state.documents;
  }

  function nextBookNumber() {
    let max = 0;
    for (const d of state.documents || []) {
      const n = parseInt(d.book_number, 10);
      if (!Number.isNaN(n) && n > max) max = n;
    }
    return String(max + 1);
  }

  function generateCode() {
    const d = new Date();
    return `D42-${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  }

  const todayIso = () => {
    const d = new Date();
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  };

  /** Uploads a Blob and returns its storage path. Scans go under the scanned prefix. */
  async function uploadAttachment(blob, ext, scanned) {
    const folder = scanned ? SCANNED_PREFIX : 'documents/';
    const path = `${folder}${Date.now()}${rand()}${ext}`;
    const { error } = await client.storage.from(DOC_BUCKET).upload(path, blob, {
      contentType: blob.type || undefined,
      upsert: false,
    });
    fail(error);
    return path;
  }

  async function removeObject(path, bucket) {
    if (!path) return;
    const { error } = await client.storage.from(bucket || DOC_BUCKET).remove([path]);
    if (error) console.warn('Could not remove', path, error.message);
  }

  function payload(draft, attachment, approval) {
    return {
      book_number: draft.book_number,
      doc_date: draft.doc_date || null,
      book_type: draft.book_type,
      requester: draft.requester,
      status: draft.status,
      direction: draft.direction,
      summary: draft.summary,
      attachment_path: attachment,
      approval_date: approval,
    };
  }

  /** attachment: { blob, ext, scanned } or null. Returns the new row. */
  async function createDocument(draft, attachment) {
    const path = attachment ? await uploadAttachment(attachment.blob, attachment.ext, attachment.scanned) : '';
    const approval = draft.status === APPROVED ? todayIso() : null;
    const { data, error } = await client
      .from('documents')
      .insert({ document_code: generateCode(), ...payload(draft, path, approval) })
      .select()
      .single();
    if (error) {
      await removeObject(path);
      fail(error);
    }
    if (state.documents) state.documents.unshift(data);
    return data;
  }

  async function updateDocument(doc, draft, attachment) {
    const previous = doc.attachment_path || '';
    const path = attachment ? await uploadAttachment(attachment.blob, attachment.ext, attachment.scanned) : previous;
    const approval = draft.status === APPROVED ? (doc.approval_date || todayIso()) : null;
    const { data, error } = await client
      .from('documents')
      .update(payload(draft, path, approval))
      .eq('id', doc.id)
      .select()
      .single();
    if (error) {
      if (path !== previous) await removeObject(path);
      fail(error);
    }
    if (path !== previous) await removeObject(previous);
    replaceCached(data);
    return data;
  }

  /** Points a document at a new (already processed) file, dropping the old one. */
  async function setAttachment(doc, blob, ext, { scanned = true, deleteOld = true } = {}) {
    const previous = doc.attachment_path || '';
    const path = await uploadAttachment(blob, ext, scanned);
    const { data, error } = await client
      .from('documents')
      .update({ attachment_path: path })
      .eq('id', doc.id)
      .select()
      .single();
    if (error) {
      await removeObject(path);
      fail(error);
    }
    if (deleteOld && previous && previous !== path) await removeObject(previous);
    replaceCached(data);
    return data;
  }

  async function deleteDocument(doc, deleteFile = true) {
    const { error } = await client.from('documents').delete().eq('id', doc.id);
    fail(error);
    if (deleteFile) await removeObject(doc.attachment_path);
    if (state.documents) state.documents = state.documents.filter((d) => d.id !== doc.id);
  }

  function replaceCached(row) {
    if (!state.documents || !row) return;
    const i = state.documents.findIndex((d) => d.id === row.id);
    if (i >= 0) state.documents[i] = row;
  }

  // ---------------------------------------------------------------- files

  const urlCache = new Map();

  /** Signed URL (1h), cached for 50 minutes. */
  async function signedUrl(path, bucket) {
    if (!path) return null;
    const key = `${bucket || DOC_BUCKET}/${path}`;
    const hit = urlCache.get(key);
    if (hit && hit.until > Date.now()) return hit.url;
    const { data, error } = await client.storage.from(bucket || DOC_BUCKET).createSignedUrl(path, 3600);
    if (error) return null;
    urlCache.set(key, { url: data.signedUrl, until: Date.now() + 50 * 60 * 1000 });
    return data.signedUrl;
  }

  async function download(path, bucket) {
    if (!path) return null;
    const { data, error } = await client.storage.from(bucket || DOC_BUCKET).download(path);
    return error ? null : data;
  }

  // ---------------------------------------------------------------- tasks

  async function tasks(force) {
    if (state.tasks && !force) return state.tasks;
    const { data, error } = await client.from('tasks').select('*').order('created_at', { ascending: false });
    fail(error);
    state.tasks = data || [];
    return state.tasks;
  }

  // -------------------------------------------------------------- options

  async function allOptions(force) {
    if (state.options && !force) return state.options;
    const { data, error } = await client
      .from('options')
      .select('category, value, sort_order')
      .order('sort_order')
      .order('value');
    fail(error);
    const grouped = {};
    for (const c of CATEGORIES) grouped[c.key] = [];
    for (const row of data || []) (grouped[row.category] = grouped[row.category] || []).push(row.value);
    state.options = grouped;
    return grouped;
  }

  /** The list the form should offer (recipients fall back to the app's defaults). */
  function optionValues(category) {
    const list = (state.options && state.options[category]) || [];
    if (category === 'recipient' && list.length === 0) return DEFAULT_RECIPIENTS.slice();
    return list;
  }

  async function addOption(category, value) {
    const v = value.trim();
    const current = (state.options && state.options[category]) || [];
    const { error } = await client.from('options').insert({ category, value: v, sort_order: current.length });
    fail(error);
    await allOptions(true);
    return v;
  }

  /** Renames a value; with updateDocuments, documents using it follow along. */
  async function renameOption(category, from, to, updateDocuments) {
    const { error } = await client.from('options').update({ value: to.trim() }).eq('category', category).eq('value', from);
    fail(error);
    if (updateDocuments) {
      const c = CATEGORIES.find((x) => x.key === category);
      let q = client.from('documents').update({ [c.column]: to.trim() }).eq(c.column, from);
      if (c.direction) q = q.eq('direction', c.direction);
      const { error: docError } = await q;
      fail(docError);
      await documents(true);
    }
    await allOptions(true);
  }

  async function deleteOption(category, value) {
    const { error } = await client.from('options').delete().eq('category', category).eq('value', value);
    fail(error);
    await allOptions(true);
  }

  /** Saves a new order for a category (sort_order = position). */
  async function reorderOptions(category, values) {
    for (let i = 0; i < values.length; i++) {
      const { error } = await client.from('options').update({ sort_order: i }).eq('category', category).eq('value', values[i]);
      fail(error);
    }
    await allOptions(true);
  }

  /** How many documents use a lookup value. */
  function usageCount(category, value) {
    const c = CATEGORIES.find((x) => x.key === category);
    return (state.documents || []).filter(
      (d) => d[c.column] === value && (!c.direction || d.direction === c.direction),
    ).length;
  }

  // ---------------------------------------------------------------- users

  async function adminUsers(body) {
    const { data, error } = await client.functions.invoke('admin-users', { body });
    if (error) {
      let message = error.message;
      try {
        const ctx = error.context;
        if (ctx && typeof ctx.json === 'function') {
          const parsed = await ctx.json();
          if (parsed && parsed.error) message = parsed.error;
        }
        if (ctx && ctx.status === 404) message = 'FUNCTION_MISSING';
      } catch (e) {
        /* keep the generic message */
      }
      if (/Failed to send a request|FunctionsFetchError/i.test(message)) message = 'FUNCTION_MISSING';
      throw new Error(message);
    }
    return data;
  }

  window.Api = {
    client, state, CATEGORIES, APPROVED, DEFAULT_STATUS, OUTGOING, INCOMING, DOC_BUCKET, TASK_BUCKET,
    SCANNED_PREFIX, extOf, isImagePath,
    signIn, signOut, currentSession, profile,
    documents, nextBookNumber, createDocument, updateDocument, setAttachment, deleteDocument,
    uploadAttachment, removeObject, signedUrl, download,
    tasks,
    allOptions, optionValues, addOption, renameOption, deleteOption, reorderOptions, usageCount,
    listUsers: () => adminUsers({ action: 'list' }).then((d) => d.users),
    createUser: (u) => adminUsers({ action: 'create', ...u }),
    updateUser: (u) => adminUsers({ action: 'update', ...u }),
    deleteUser: (id) => adminUsers({ action: 'delete', id }),
  };
})();
