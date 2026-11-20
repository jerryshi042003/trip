// Lists iPhones that shared their ID through docs/install/ (private Blob store) and,
// when an App Store Connect API key is set, registers any new ones on Jerry's team.
//   BLOB_READ_WRITE_TOKEN=... node ios/adhoc-devices.mjs
//   + ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH to register new devices automatically.
// Prints one line per device. Never commit this output: device IDs stay private.
import { createSign, createPrivateKey } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { list, get } from '@vercel/blob';

const { blobs } = await list({ prefix: 'udid/devices/' });
const devices = [];
for (const b of blobs) {
  const blob = await get(b.pathname, { access: 'private', useCache: false });
  if (blob) devices.push(await new Response(blob.stream).json());
}

function jwt() {
  const enc = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  const head = enc({ alg: 'ES256', kid: process.env.ASC_KEY_ID, typ: 'JWT' });
  const now = Math.floor(Date.now() / 1000);
  const body = enc({ iss: process.env.ASC_ISSUER_ID, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' });
  const key = createPrivateKey(readFileSync(process.env.ASC_KEY_PATH));
  const sig = createSign('SHA256').update(`${head}.${body}`).sign({ key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${head}.${body}.${sig}`;
}

async function asc(path, init = {}) {
  const r = await fetch('https://api.appstoreconnect.apple.com' + path, {
    ...init, headers: { Authorization: 'Bearer ' + jwt(), 'Content-Type': 'application/json', ...init.headers },
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`${r.status} ${JSON.stringify(j.errors?.[0]?.detail ?? j)}`);
  return j;
}

const canRegister = process.env.ASC_KEY_ID && process.env.ASC_ISSUER_ID && process.env.ASC_KEY_PATH;
for (const d of devices) {
  let status = 'not checked (no API key)';
  if (canRegister) {
    const found = await asc('/v1/devices?filter[udid]=' + encodeURIComponent(d.udid) + '&limit=1');
    if (found.data.length) status = 'registered';
    else {
      await asc('/v1/devices', { method: 'POST', body: JSON.stringify({ data: { type: 'devices',
        attributes: { name: (d.name || 'iPhone').slice(0, 50), udid: d.udid, platform: 'IOS' } } }) });
      status = 'registered now';
    }
  }
  console.log([d.udid, d.name, d.product, d.version, d.received, status].join('\t'));
}
if (!devices.length) console.log('No devices yet.');
