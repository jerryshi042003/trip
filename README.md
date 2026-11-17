# Trip

Offline trip app: Plan, Places, People. Install on a phone from Safari (Share, Add to Home Screen) or Chrome (Install app). Works with no service once opened.

Edit `public/trip.json` on GitHub (pencil icon) and commit; Vercel redeploys and phones pick it up the next time they're online.

Private contacts are encrypted in `public/private.enc.json`. To change them, edit `~/.config/jerry-trip/private.json` on Jerry's Mac and run `node encrypt.mjs`.
