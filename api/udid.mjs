import { randomBytes } from 'node:crypto';
import { get, put } from '@vercel/blob';

// iPhone device ID capture for the ad hoc install (docs/install/).
//   GET  /api/udid?profile=1  -> unsigned Profile Service .mobileconfig with a one-time token
//   POST /api/udid            -> iOS posts the signed device attributes; stored privately, then 301 back
//   GET  /api/udid?t=<token>  -> small page showing that device's ID (token is random, not the ID)
// Device IDs live only in the private Blob store (udid/devices/<UDID>.json); Jerry's Mac reads them
// with ios/adhoc-devices.mjs.

const BASE = 'https://jerry-trip.vercel.app';
const TOKEN = /^[A-Za-z0-9_-]{22}$/;
const esc = s => String(s).replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);

function profile(token) {
  const uuid = () => {
    const b = randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    const h = b.toString('hex');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`.toUpperCase();
  };
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <dict>
    <key>URL</key><string>${BASE}/api/udid</string>
    <key>DeviceAttributes</key>
    <array><string>UDID</string><string>PRODUCT</string><string>VERSION</string><string>DEVICE_NAME</string></array>
    <key>Challenge</key><string>${token}</string>
  </dict>
  <key>PayloadOrganization</key><string>Trip</string>
  <key>PayloadDisplayName</key><string>Trip: share iPhone ID</string>
  <key>PayloadDescription</key><string>Sends this iPhone's device ID to Jerry so Trip can be installed on it. Nothing is installed.</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>PayloadUUID</key><string>${uuid()}</string>
  <key>PayloadIdentifier</key><string>com.shishi88.trip.udid</string>
  <key>PayloadType</key><string>Profile Service</string>
</dict>
</plist>
`;
}

async function readBody(req) {
  if (Buffer.isBuffer(req.body)) return req.body;
  if (typeof req.body === 'string') return Buffer.from(req.body, 'latin1');
  const chunks = [];
  for await (const c of req) chunks.push(c);
  return Buffer.concat(chunks);
}

// The POST body is a PKCS#7 envelope; the XML plist inside is stored in clear.
function attributes(buf) {
  const text = buf.toString('latin1');
  const field = k => (new RegExp(`<key>${k}</key>\\s*<string>([^<]{1,100})</string>`).exec(text) ?? [])[1];
  const udid = field('UDID');
  if (!udid || !/^[0-9A-Fa-f-]{24,40}$/.test(udid)) return null;
  return {
    udid: udid.toUpperCase(),
    product: field('PRODUCT') ?? '',
    version: field('VERSION') ?? '',
    name: Buffer.from(field('DEVICE_NAME') ?? '', 'latin1').toString('utf8'),
    challenge: field('CHALLENGE') ?? '',
  };
}

function page(title, body) {
  return `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title><meta name="robots" content="noindex">
<style>body{font:17px/1.5 -apple-system,system-ui,sans-serif;margin:0;padding:32px 20px;background:#f2f2f7;color:#141419}
main{max-width:420px;margin:0 auto}h1{font-size:24px}code{display:block;font:15px ui-monospace,Menlo,monospace;background:#fff;border:1px solid #ddd;border-radius:10px;padding:12px;word-break:break-all;user-select:all}
a.b{display:block;text-align:center;background:#005fbd;color:#fff;text-decoration:none;border-radius:12px;padding:14px;font-weight:600;margin-top:20px}
@media (prefers-color-scheme:dark){body{background:#000;color:#f5f5f7}code{background:#1c1c1e;border-color:#333}a.b{background:#70b8ff;color:#000}}</style>
<main>${body}</main>`;
}

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  const url = new URL(req.url, BASE);
  try {
    if (req.method === 'GET' && url.searchParams.has('profile')) {
      const token = randomBytes(16).toString('base64url');
      res.setHeader('Content-Type', 'application/x-apple-aspen-config');
      res.setHeader('Content-Disposition', 'attachment; filename="trip-iphone-id.mobileconfig"');
      return res.status(200).send(profile(token));
    }
    if (req.method === 'GET' && TOKEN.test(url.searchParams.get('t') ?? '')) {
      const blob = await get('udid/tokens/' + url.searchParams.get('t') + '.json', { access: 'private', useCache: false });
      if (!blob) return res.status(404).send(page('Not found', '<h1>Not found</h1><p>Try “Get my iPhone ID” again.</p>'));
      const d = await new Response(blob.stream).json();
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      return res.status(200).send(page('iPhone ID received', `<h1>iPhone ID received</h1>
<p>Jerry now has this iPhone's ID. Once he says it's ready, tap Install.</p><code>${esc(d.udid)}</code>
<p>You can remove the “Trip: share iPhone ID” profile in Settings → General → VPN &amp; Device Management.</p>
<a class="b" href="https://jerryshi042003.github.io/trip/install/">Back to install page</a>`));
    }
    if (req.method === 'POST') {
      const a = attributes(await readBody(req));
      if (!a) return res.status(400).send('Missing device ID');
      const record = JSON.stringify({ udid: a.udid, product: a.product, version: a.version, name: a.name, received: new Date().toISOString() });
      await put('udid/devices/' + a.udid + '.json', record, { access: 'private', contentType: 'application/json', allowOverwrite: true });
      const token = TOKEN.test(a.challenge) ? a.challenge : randomBytes(16).toString('base64url');
      await put('udid/tokens/' + token + '.json', record, { access: 'private', contentType: 'application/json', allowOverwrite: true });
      res.setHeader('Location', `${BASE}/api/udid?t=${token}`);
      return res.status(301).end();
    }
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).send('Method not allowed');
  } catch (error) {
    console.error(error);
    return res.status(500).send('Server error');
  }
}
