# Mac Tools

One menu-bar app, many tools. First tool: **Island**, a notch overlay that anything can push to.

Run: `swift build && .build/out/Products/Debug/MacTools` (or `swift run`).

## Pushing
Event fields: `id` (upsert key), `title` (required), `subtitle`, `source`, `status`
(info|running|waiting|success|warning|error), `icon` (SF Symbol), `progress` 0-1, `url` (opened on click),
`ttl` seconds, `quiet` (don't auto-expand), `sound`.

- **HTTP** (127.0.0.1:7878, loopback only): `POST /v1/events` (object or array), `DELETE /v1/events/:id`, `POST /v1/clear`
- **CLI/Node**: `node tools/notch-push.mjs --id x --title "Deploy" --status running --progress 0.5`
- **File**: drop a `.json` in `~/.mactools/inbox/` (consumed within 0.5s)
- **Cloud**: deploy the Cloudflare Worker in `cloudflare/` (see its README), or run `relay/server.mjs` somewhere (PUSH_TOKEN, STREAM_TOKEN), POST to `/push`, and set
  `~/.mactools/config.json`: `{"relay":{"url":"https://your-host/stream","token":"STREAM_TOKEN"}}`

## Claude Code hooks (~/.claude/settings.json)
Point UserPromptSubmit, PreToolUse, Notification, Stop and SessionEnd at
`node /path/to/mac-tools/tools/claude-hook.mjs`.
