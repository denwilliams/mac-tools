# Mac Tools relay (Cloudflare Worker)

Cloud systems can't reach your Mac, so they push here and your Mac holds a stream open to receive.

```
senders --POST /push--> Worker --> Durable Object --SSE /stream--> your Mac
```

The Durable Object keeps your stream open and buffers the last 20 events for 10 minutes, so a sleeping
Mac catches up when it reconnects.

## Deploy

```bash
cd cloudflare && npm install
npx wrangler login
npx wrangler secret put STREAM_TOKEN      # paste: openssl rand -base64 32
npx wrangler secret put PUSH_TOKENS       # paste JSON, e.g. {"ci":"<token>","slack":"<token>"}
npx wrangler deploy
```

Generate each token with `openssl rand -base64 32`. Use a different one per sender.

Mac side, `~/.mactools/config.json`:
```json
{ "relay": { "url": "https://mactools-relay.<you>.workers.dev/stream", "token": "<STREAM_TOKEN>" } }
```
Restart the app after changing it.

Push from anywhere:
```bash
curl -X POST https://mactools-relay.<you>.workers.dev/push \
  -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"id":"build","title":"Build #42","status":"running","progress":0.3}'
```

Local dev: `cp .dev.vars.example .dev.vars && npm run dev`

## What the Worker enforces
- Two kinds of secret: `STREAM_TOKEN` (read, for your Mac) and `PUSH_TOKENS` (write, one per sender).
  A push token can't read the stream and the stream token can't push.
- Tokens are compared in constant time.
- A named push token **pins `source`** to its name and **namespaces ids** (`ci:build`), so one sender
  can't impersonate or overwrite another. Named senders can't clear everything, only their own rows.
- Events are validated: only known fields, length limits, `status` allowlist, progress 0-1, and `url`
  must be http(s) (no `file:`/`javascript:`/custom schemes). Body limit 64 KB, 20 events per request.

## Authentication options (most to least robust)
1. **Per-sender bearer tokens**: what's built in. Revoke one by editing `PUSH_TOKENS`.
2. **Cloudflare Access service tokens in front** (recommended if exposed publicly). Zero code: create an
   Access application for the hostname with a *Service Auth* policy, then add the headers on the Mac:
   `"relay": { "url": "...", "token": "...", "headers": { "CF-Access-Client-Id": "...", "CF-Access-Client-Secret": "..." } }`
   and have senders send the same two headers. Requests without them never reach the Worker. Keep the bearer
   tokens as a second layer.
3. **HMAC-signed requests** (timestamp + body signature) for senders you control: stops replay of a
   captured request. Not built; add if you push over untrusted networks.
4. **Third-party webhooks** (GitHub, Stripe, etc.): don't hand them a push token. Add a dedicated route that
   verifies the provider's own signature and maps the payload to an event.
5. **Hardening**: add a WAF rate-limiting rule on `/push`, use a custom domain and turn off the workers.dev
   route, and rotate tokens periodically.
