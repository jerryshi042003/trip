import { createHash, timingSafeEqual } from 'node:crypto';
import { get, put, BlobPreconditionFailedError } from '@vercel/blob';

const travelers = ['jerry', 'tom'];
const day = 86_400;
const pathFor = who => 'latest/' + who + '.json';
const nowSeconds = () => Math.floor(Date.now() / 1000);

function authenticate(header) {
  const match = /^Basic ([A-Za-z0-9+/]+=*)$/i.exec(header ?? '');
  if (!match) return null;
  const [user, token, extra] = Buffer.from(match[1], 'base64').toString().split(':');
  if (!travelers.includes(user) || !/^[A-Za-z0-9_-]{43}$/.test(token ?? '') || extra !== undefined) return null;
  const digest = process.env['TRIP_' + user.toUpperCase() + '_SHA256'];
  if (!/^[a-f0-9]{64}$/.test(digest ?? '')) return null;
  return timingSafeEqual(createHash('sha256').update(token).digest(), Buffer.from(digest, 'hex')) ? user : null;
}

async function readPoint(who) {
  const blob = await get(pathFor(who), { access: 'private', useCache: false });
  if (!blob) return null;
  return { point: await new Response(blob.stream).json(), etag: blob.blob.etag };
}

async function writePoint(who, point, onlyClear = false) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const previous = await readPoint(who);
    if (onlyClear && (!previous || previous.point.cleared)) return;
    if (!onlyClear && previous?.point.tst >= point.tst) return;
    const next = onlyClear ? { cleared: true, tst: Math.max(point.tst, previous.point.tst) } : point;
    try {
      await put(pathFor(who), JSON.stringify(next), {
        access: 'private',
        contentType: 'application/json',
        allowOverwrite: Boolean(previous),
        ifMatch: previous?.etag,
      });
      return;
    } catch (error) {
      // A concurrent overwrite can return either a precondition error or a generic storage error.
      const latest = await readPoint(who);
      if (!onlyClear && latest?.point.tst >= point.tst) return;
      if (!(error instanceof BlobPreconditionFailedError) && latest?.etag === previous?.etag) throw error;
    }
  }
  throw new Error('Write contention');
}

function decodePoint(body, now) {
  const { lat, lon, tst, batt, test } = body;
  if (!Number.isFinite(lat) || Math.abs(lat) > 90 ||
      !Number.isFinite(lon) || Math.abs(lon) > 180 ||
      !Number.isSafeInteger(tst) || tst < now - day || tst > now + 180) return null;
  return {
    lat, lon, tst, received: now,
    ...(Number.isInteger(batt) && batt >= 0 && batt <= 100 ? { batt } : {}),
    ...(test === true ? { test: true } : {}),
  };
}

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  const now = nowSeconds();
  try {
    if (req.method === 'GET') {
      const points = await Promise.all(travelers.map(readPoint));
      return res.status(200).json({
        locations: Object.fromEntries(travelers.map((who, index) => {
          const point = points[index]?.point;
          const lifetime = point?.test ? 600 : day;
          return [who, point && !point.cleared && now - point.tst < lifetime ? point : null];
        })),
      });
    }
    if (req.method !== 'POST' && req.method !== 'DELETE') {
      res.setHeader('Allow', 'GET, POST, DELETE');
      return res.status(405).json({ error: 'Method not allowed' });
    }
    const who = authenticate(req.headers.authorization);
    if (!who) {
      res.setHeader('WWW-Authenticate', 'Basic realm="Trip Location"');
      return res.status(401).json({ error: 'Invalid location credentials' });
    }
    if (req.method === 'DELETE') {
      await writePoint(who, { tst: now }, true);
      return res.status(204).end();
    }
    if (Number(req.headers['content-length']) > 24_000) {
      return res.status(413).json({ error: 'Payload too large' });
    }
    const raw = req.body;
    let body;
    try { body = typeof raw === 'string' || Buffer.isBuffer(raw) ? JSON.parse(raw) : raw; }
    catch { return res.status(400).json({ error: 'Invalid JSON' }); }
    if (!body || body._type !== 'location') return res.status(200).json([]);
    const point = decodePoint(body, now);
    if (!point) return res.status(400).json({ error: 'Invalid location fix' });
    await writePoint(who, point);
    return res.status(200).json([]);
  } catch (error) {
    console.error('Trip location storage error', error.name);
    return res.status(503).json({ error: 'Trip location temporarily unavailable' });
  }
}
