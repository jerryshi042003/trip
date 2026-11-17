// Encrypts ~/.config/jerry-trip/private.json with the passcode into public/private.enc.json (AES-GCM, PBKDF2-SHA256).
import { readFileSync, writeFileSync } from 'fs';
import { webcrypto as c } from 'crypto';
import os from 'os';
const dir = os.homedir() + '/.config/jerry-trip/';
const pass = readFileSync(dir + 'passcode', 'utf8').trim();
const data = new TextEncoder().encode(readFileSync(dir + 'private.json', 'utf8'));
const salt = c.getRandomValues(new Uint8Array(16)), iv = c.getRandomValues(new Uint8Array(12));
const base = await c.subtle.importKey('raw', new TextEncoder().encode(pass), 'PBKDF2', false, ['deriveKey']);
const key = await c.subtle.deriveKey({ name: 'PBKDF2', salt, iterations: 200000, hash: 'SHA-256' }, base, { name: 'AES-GCM', length: 256 }, false, ['encrypt']);
const ct = new Uint8Array(await c.subtle.encrypt({ name: 'AES-GCM', iv }, key, data));
const b = u => Buffer.from(u).toString('base64');
writeFileSync('public/private.enc.json', JSON.stringify({ salt: b(salt), iv: b(iv), ct: b(ct) }));
console.log('encrypted', ct.length, 'bytes');
