#!/usr/bin/env node
// Claude Code hook adapter: reads hook JSON on stdin, pushes an activity per session.
// Wire up in ~/.claude/settings.json (see README).
import { push } from './notch-push.mjs';

let raw = '';
for await (const c of process.stdin) raw += c;
let h = {};
try { h = JSON.parse(raw); } catch {}
const id = `claude-${h.session_id || 'unknown'}`;
const project = (h.cwd || '').split('/').pop() || 'claude';
const base = { id, source: 'claude', icon: 'sparkles' };

const ev = h.hook_event_name;
try {
  if (ev === 'UserPromptSubmit') await push({ ...base, title: project, subtitle: (h.prompt || '').slice(0, 80), status: 'running', quiet: true, ttl: 300 });
  else if (ev === 'PreToolUse') await push({ ...base, title: project, subtitle: `Running ${h.tool_name}`, status: 'running', quiet: true, ttl: 300 });
  else if (ev === 'Notification') await push({ ...base, title: project, subtitle: h.message || 'Needs your attention', status: 'waiting', sound: true });
  else if (ev === 'Stop') await push({ ...base, title: project, subtitle: 'Done', status: 'success', ttl: 8, sound: true });
  else if (ev === 'SessionEnd') await push({ op: 'clear', id });
} catch { /* island not running: never block Claude */ }
