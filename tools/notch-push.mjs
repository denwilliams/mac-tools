#!/usr/bin/env node
// Usage: notch-push --title "Build" --status running --progress 0.4 [--id x] [--subtitle ..] [--source ..] [--icon ..] [--url ..] [--ttl 30] [--quiet] [--sound]
//        notch-push --clear [--id x]
// Importable: import { push } from './notch-push.mjs'
const BASE = process.env.NOTCH_URL || 'http://127.0.0.1:7878';

export async function push(event) {
  const body = event.op === 'clear' && event.id ? null : event;
  const res = event.op === 'clear' && event.id
    ? await fetch(`${BASE}/v1/events/${encodeURIComponent(event.id)}`, { method: 'DELETE' })
    : await fetch(`${BASE}/v1/events`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return res.json();
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const a = process.argv.slice(2), ev = {};
  for (let i = 0; i < a.length; i++) {
    if (!a[i].startsWith('--')) continue;
    const k = a[i].slice(2), next = a[i + 1];
    if (k === 'clear') ev.op = 'clear';
    else if (k === 'quiet' || k === 'sound') ev[k] = true;
    else { ev[k] = ['progress', 'ttl'].includes(k) ? Number(next) : next; i++; }
  }
  push(ev).then(r => console.log(JSON.stringify(r))).catch(e => { console.error('notch-push failed:', e.message); process.exit(1); });
}
