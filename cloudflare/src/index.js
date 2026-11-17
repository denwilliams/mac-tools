// Mac Tools relay: senders POST /push, the Mac holds GET /stream (Server-Sent Events).
//
// Secrets (wrangler secret put ...):
//   STREAM_TOKEN  bearer token the Mac uses for /stream
//   PUSH_TOKENS   JSON map of sender name -> token, e.g. {"ci":"...","slack":"..."}
//                 (or PUSH_TOKEN: a single token with no per-sender identity)
import { DurableObject } from 'cloudflare:workers';

const MAX_BODY = 64 * 1024;
const MAX_BATCH = 20;
const BACKLOG_MAX = 20;
const REPLAY_MS = 10 * 60 * 1000; // events newer than this are replayed to a reconnecting Mac
const STATUSES = new Set(['info', 'running', 'waiting', 'success', 'warning', 'error']);
const enc = new TextEncoder();

/* ---------- auth ---------- */

async function sha256(s) {
  return crypto.subtle.digest('SHA-256', enc.encode(s));
}
// Constant-time compare (hash first so lengths always match).
async function tokenEquals(a, b) {
  const [x, y] = await Promise.all([sha256(a), sha256(b)]);
  return crypto.subtle.timingSafeEqual(x, y);
}
function bearer(request) {
  const m = (request.headers.get('authorization') || '').match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : '';
}
/** Returns the sender name ('' for an anonymous single PUSH_TOKEN), or null if not authorised. */
async function authPush(request, env) {
  const given = bearer(request);
  if (!given) return null;
  let found = null;
  if (env.PUSH_TOKENS) {
    let map = {};
    try { map = JSON.parse(env.PUSH_TOKENS); } catch { /* misconfigured: nothing matches */ }
    for (const [name, tok] of Object.entries(map)) {          // check all, no early exit
      if (await tokenEquals(given, String(tok))) found = name;
    }
  }
  if (found === null && env.PUSH_TOKEN && await tokenEquals(given, env.PUSH_TOKEN)) found = '';
  return found;
}
async function authStream(request, env) {
  const given = bearer(request);
  return !!given && !!env.STREAM_TOKEN && tokenEquals(given, env.STREAM_TOKEN);
}

/* ---------- validation: everything from a sender is untrusted ---------- */

const str = (v, max) => (typeof v === 'string' && v.length ? v.slice(0, max) : undefined);

function sanitize(raw, sender) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const ns = sender ? `${sender}:` : '';

  if (raw.op === 'clear') {
    const id = str(raw.id, 100);
    // A named sender may only clear its own rows, never everything.
    if (!id && sender) return null;
    return id ? { op: 'clear', id: ns + id } : { op: 'clear' };
  }

  const title = str(raw.title, 200);
  if (!title) return null;
  const ev = { title };
  const id = str(raw.id, 100);
  if (id) ev.id = ns + id;
  const subtitle = str(raw.subtitle, 300); if (subtitle) ev.subtitle = subtitle;
  // A named token pins `source`, so a sender can't impersonate another.
  const source = sender || str(raw.source, 40); if (source) ev.source = source;
  if (STATUSES.has(raw.status)) ev.status = raw.status;
  if (typeof raw.icon === 'string' && /^[A-Za-z0-9.\-]{1,60}$/.test(raw.icon)) ev.icon = raw.icon;
  if (typeof raw.progress === 'number' && Number.isFinite(raw.progress)) ev.progress = Math.min(1, Math.max(0, raw.progress));
  if (typeof raw.ttl === 'number' && Number.isFinite(raw.ttl)) ev.ttl = Math.min(86400, Math.max(1, raw.ttl));
  if (typeof raw.url === 'string' && raw.url.length <= 2000) {
    try { const u = new URL(raw.url); if (u.protocol === 'https:' || u.protocol === 'http:') ev.url = u.href; } catch { /* drop */ }
  }
  if (raw.quiet === true) ev.quiet = true;
  if (raw.sound === true) ev.sound = true;
  return ev;
}

/* ---------- worker ---------- */

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json' } });

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    const hub = env.HUB.get(env.HUB.idFromName('main'));

    if (pathname === '/health') return new Response('ok');

    if (pathname === '/stream' && request.method === 'GET') {
      if (!(await authStream(request, env))) return new Response('unauthorized', { status: 401 });
      return hub.fetch(request);
    }

    if (pathname === '/push' && request.method === 'POST') {
      const sender = await authPush(request, env);
      if (sender === null) return new Response('unauthorized', { status: 401 });
      if (!(request.headers.get('content-type') || '').includes('application/json')) return json({ error: 'send application/json' }, 415);
      const body = await request.text();
      if (body.length > MAX_BODY) return json({ error: 'too large' }, 413);
      let parsed;
      try { parsed = JSON.parse(body); } catch { return json({ error: 'bad json' }, 400); }
      const list = (Array.isArray(parsed) ? parsed : [parsed]).slice(0, MAX_BATCH);
      const events = list.map(e => sanitize(e, sender)).filter(Boolean);
      if (!events.length) return json({ error: 'no valid events (need a title)' }, 400);
      await hub.broadcast(events);
      return json({ ok: true, accepted: events.length });
    }

    return new Response('not found', { status: 404 });
  },
};

/* ---------- durable object: holds the Mac's stream open, buffers recent events ---------- */

export class Hub extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.clients = new Set();
    this.backlog = null;
    this.keepalive = null;
  }

  async #loadBacklog() {
    if (!this.backlog) this.backlog = (await this.ctx.storage.get('backlog')) || [];
    return this.backlog;
  }

  #send(chunk) {
    const bytes = enc.encode(chunk);
    for (const c of this.clients) c.write(bytes).catch(() => this.clients.delete(c));
  }

  // GET /stream
  async fetch(request) {
    const backlog = await this.#loadBacklog();
    const { readable, writable } = new TransformStream();
    const writer = writable.getWriter();
    this.clients.add(writer);

    const drop = () => {
      this.clients.delete(writer);
      writer.close().catch(() => {});
      if (!this.clients.size && this.keepalive) { clearInterval(this.keepalive); this.keepalive = null; }
    };
    request.signal.addEventListener('abort', drop);

    // Don't await these: nothing reads the stream until the Response is returned, so awaiting would deadlock.
    const queue = chunk => writer.write(enc.encode(chunk)).catch(drop);
    queue(': connected\n\n');
    const cutoff = Date.now() - REPLAY_MS;
    for (const b of backlog) if (b.ts >= cutoff) queue(`data: ${JSON.stringify(b.ev)}\n\n`);
    if (!this.keepalive) this.keepalive = setInterval(() => this.#send(': ka\n\n'), 25000);

    return new Response(readable, {
      headers: { 'content-type': 'text/event-stream', 'cache-control': 'no-cache, no-transform', 'x-accel-buffering': 'no' },
    });
  }

  // RPC from the worker
  async broadcast(events) {
    const backlog = await this.#loadBacklog();
    const now = Date.now();
    for (const ev of events) {
      this.#send(`data: ${JSON.stringify(ev)}\n\n`);
      backlog.push({ ts: now, ev });
    }
    this.backlog = backlog.filter(b => b.ts >= now - REPLAY_MS).slice(-BACKLOG_MAX);
    await this.ctx.storage.put('backlog', this.backlog);
  }
}
