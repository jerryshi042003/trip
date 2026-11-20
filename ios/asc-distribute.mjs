// After an upload: wait for Apple to process build N, add it to every TestFlight group
// (Trip internal + Tom's external groups) and submit it for beta review when an external
// group needs that. Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
//   node ios/asc-distribute.mjs 9
import { createSign, createPrivateKey } from 'node:crypto';
import { readFileSync } from 'node:fs';

const APP = '6836940040';
const build = process.argv[2];
if (!/^\d+$/.test(build ?? '')) { console.error('usage: node ios/asc-distribute.mjs <build number>'); process.exit(2); }

function jwt() {
  const enc = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const head = enc({ alg: 'ES256', kid: process.env.ASC_KEY_ID, typ: 'JWT' });
  const body = enc({ iss: process.env.ASC_ISSUER_ID, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' });
  const sig = createSign('SHA256').update(`${head}.${body}`)
    .sign({ key: createPrivateKey(readFileSync(process.env.ASC_KEY_PATH)), dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${head}.${body}.${sig}`;
}
async function asc(path, init = {}) {
  const r = await fetch('https://api.appstoreconnect.apple.com' + path, {
    ...init, headers: { Authorization: 'Bearer ' + jwt(), 'Content-Type': 'application/json' } });
  if (r.status === 204) return {};
  const j = await r.json().catch(() => ({}));
  if (!r.ok) { const e = new Error(`${r.status} ${j.errors?.[0]?.detail ?? ''}`); e.status = r.status; throw e; }
  return j;
}
const sleep = s => new Promise(r => setTimeout(r, s * 1000));

// 1. Wait for processing (up to 40 min)
let b;
for (let i = 0; i < 80; i++) {
  const j = await asc(`/v1/builds?filter[app]=${APP}&filter[version]=${build}&limit=1`);
  b = j.data[0];
  const state = b?.attributes.processingState;
  if (state === 'VALID') break;
  if (state === 'FAILED' || state === 'INVALID') throw new Error('Apple marked build ' + build + ' ' + state);
  if (i === 0) console.log(`Waiting for Apple to process build ${build}…`);
  await sleep(30);
}
if (b?.attributes.processingState !== 'VALID') throw new Error('Build ' + build + ' still processing after 40 min');
console.log(`Build ${build} processed.`);

// 2. Add it to every group
const groups = (await asc(`/v1/apps/${APP}/betaGroups?limit=50`)).data;
let external = false;
for (const g of groups) {
  try {
    await asc(`/v1/betaGroups/${g.id}/relationships/builds`, { method: 'POST', body: JSON.stringify({ data: [{ type: 'builds', id: b.id }] }) });
    console.log(`Added to ${g.attributes.name}.`);
  } catch (e) { console.log(`${g.attributes.name}: ${e.message}`); }
  if (!g.attributes.isInternalGroup) external = true;
}

// 3. External testers need a beta review submission (often approved automatically after the first)
if (external) {
  try {
    await asc('/v1/betaAppReviewSubmissions', { method: 'POST', body: JSON.stringify({ data: { type: 'betaAppReviewSubmissions',
      relationships: { build: { data: { type: 'builds', id: b.id } } } } }) });
    console.log('Submitted for beta review.');
  } catch (e) { console.log('Beta review submission: ' + e.message); }
  const d = await asc(`/v1/builds/${b.id}/buildBetaDetail`);
  console.log('External status: ' + d.data.attributes.externalBuildState + ' · internal: ' + d.data.attributes.internalBuildState);
}
