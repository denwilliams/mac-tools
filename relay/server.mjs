// Tiny relay: cloud systems POST /push (Bearer PUSH_TOKEN); the Mac subscribes to GET /stream (Bearer STREAM_TOKEN).
// Zero deps. Deploy anywhere that runs Node (Fly, Railway, a VPS) behind HTTPS.
import http from 'node:http';
const PUSH = process.env.PUSH_TOKEN, STREAM = process.env.STREAM_TOKEN, PORT = process.env.PORT || 8080;
if (!PUSH || !STREAM) { console.error('Set PUSH_TOKEN and STREAM_TOKEN'); process.exit(1); }
const clients = new Set();
let backlog = []; // replay recent events to reconnecting clients
http.createServer((req, res) => {
  const auth = req.headers.authorization || '';
  if (req.method === 'GET' && req.url === '/stream') {
    if (auth !== `Bearer ${STREAM}`) return res.writeHead(401).end();
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
    backlog.forEach(b => res.write(`data: ${b}\n\n`));
    clients.add(res); req.on('close', () => clients.delete(res));
    const ka = setInterval(() => res.write(': ka\n\n'), 25000); req.on('close', () => clearInterval(ka));
    return;
  }
  if (req.method === 'POST' && req.url === '/push') {
    if (auth !== `Bearer ${PUSH}`) return res.writeHead(401).end();
    let body = ''; req.on('data', d => { body += d; if (body.length > 1e6) req.destroy(); });
    req.on('end', () => {
      try { JSON.parse(body); } catch { return res.writeHead(400).end('bad json'); }
      clients.forEach(c => c.write(`data: ${body}\n\n`));
      backlog = [...backlog, body].slice(-20);
      res.writeHead(200, { 'content-type': 'application/json' }).end('{"ok":true}');
    });
    return;
  }
  res.writeHead(404).end();
}).listen(PORT, () => console.log(`relay on :${PORT}`));
