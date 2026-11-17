#!/usr/bin/env node
// notch: push to the Mac Tools island.   Run `notch help` for usage.
import { spawn } from 'node:child_process';

const BASE = process.env.NOTCH_URL || 'http://127.0.0.1:7878';
const HELP = `notch: push to the island

  notch <title> [subtitle] [flags]        push an event
  notch run [flags] -- <command...>       run a command: running -> success/error (exit code passes through)
  notch clear [id]                        remove one event, or all
  notch json                              read event JSON (object or array) from stdin
  notch ping                              check the app is running

flags:
  -i, --id <id>          upsert key (same id updates the row)
  -s, --status <s>       info|running|waiting|success|warning|error  (default info)
  -p, --progress <0-1>   progress fill (also accepts 0-100)
      --source <name>    small tag on the row
      --icon <symbol>    SF Symbol name
  -u, --url <url>        opened when the row is clicked
      --ttl <seconds>    auto-remove after this long
  -t, --title <t>        title (alternative to the positional)
      --subtitle <t>
      --quiet            don't drop the island down
      --sound            play a sound
  NOTCH_URL env overrides ${BASE}

examples:
  notch "Deploying" "prod" -s running -p 0.4 -i deploy
  notch "Deploy done" -s success -i deploy --sound
  notch run --title "Tests" -- npm test
  long_job | notch json`;

const short = { i: 'id', s: 'status', p: 'progress', u: 'url', t: 'title' };
const bool = new Set(['quiet', 'sound']);
const num = new Set(['progress', 'ttl']);

function parse(args) {
  const ev = {}, pos = [];
  for (let k = 0; k < args.length; k++) {
    const a = args[k];
    if (a === '--') { pos.push(...args.slice(k + 1)); break; }
    const m = a.match(/^--?([A-Za-z]+)(?:=(.*))?$/);
    if (!m || a === '-') { pos.push(a); continue; }
    const key = short[m[1]] || m[1];
    if (bool.has(key)) { ev[key] = true; continue; }
    const val = m[2] ?? args[++k];
    if (val === undefined) die(`missing value for ${a}`);
    ev[key] = num.has(key) ? Number(val) : val;
    if (num.has(key) && Number.isNaN(ev[key])) die(`${a} needs a number`);
  }
  if (ev.progress > 1) ev.progress /= 100;
  return { ev, pos };
}

function die(msg) { console.error(`notch: ${msg}`); process.exit(1); }

async function send(path, init) {
  try {
    const r = await fetch(BASE + path, init);
    return await r.json();
  } catch {
    return null; // app not running
  }
}
const post = ev => send('/v1/events', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(ev) });
const del = id => send(`/v1/events/${encodeURIComponent(id)}`, { method: 'DELETE' });

const [cmd, ...rest] = process.argv.slice(2);

if (!cmd || cmd === 'help' || cmd === '-h' || cmd === '--help') {
  console.log(HELP);
} else if (cmd === 'ping') {
  const r = await send('/health');
  console.log(r?.ok ? 'island is running' : 'island is not running');
  process.exit(r?.ok ? 0 : 1);
} else if (cmd === 'clear') {
  const r = rest[0] ? await del(rest[0]) : await send('/v1/clear', { method: 'POST' });
  if (!r) die('island is not running');
} else if (cmd === 'json') {
  let raw = ''; for await (const c of process.stdin) raw += c;
  let j; try { j = JSON.parse(raw); } catch { die('stdin is not valid JSON'); }
  const r = await post(j);
  if (!r) die('island is not running');
  console.log(JSON.stringify(r));
} else if (cmd === 'run') {
  const { ev, pos } = parse(rest);
  if (!pos.length) die('usage: notch run [flags] -- <command...>');
  const id = ev.id || `run-${process.pid}`;
  const title = ev.title || pos.join(' ');
  const base = { source: 'run', ...ev, id, title };
  const t0 = Date.now();
  await post({ ...base, subtitle: ev.subtitle || 'Running…', status: 'running', quiet: true });
  const child = spawn(pos[0], pos.slice(1), { stdio: 'inherit' });
  for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => child.kill(sig));
  child.on('error', async e => { await post({ ...base, subtitle: e.message, status: 'error' }); console.error(`notch: ${e.message}`); process.exit(127); });
  child.on('exit', async (code, signal) => {
    const secs = Math.round((Date.now() - t0) / 1000);
    const took = secs >= 60 ? `${Math.floor(secs / 60)}m ${secs % 60}s` : `${secs}s`;
    delete base.progress;
    await post(code === 0
      ? { ...base, subtitle: `Done in ${took}`, status: 'success', quiet: false, sound: true }
      : { ...base, subtitle: signal ? `Killed (${signal})` : `Failed (exit ${code}) after ${took}`, status: 'error', quiet: false, sound: true });
    process.exit(code ?? 1);
  });
} else {
  // push (default). `notch push ...` and `notch <title> ...` are equivalent.
  const { ev, pos } = parse(cmd === 'push' ? rest : [cmd, ...rest]);
  if (pos[0] && !ev.title) ev.title = pos.shift();
  if (pos[0] && !ev.subtitle) ev.subtitle = pos.shift();
  if (!ev.title) die('a title is required (try `notch help`)');
  const r = await post(ev);
  if (!r) die('island is not running');
  console.log(r.ids?.[0] ?? '');
}
