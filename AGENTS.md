# Trip

Offline trip app for Jerry and Tom: https://jerry-trip.vercel.app

Install: open the link in Safari, Share, Add to Home Screen (Android Chrome: Install app). It works with no service once opened.

## iPhone app

`ios/` is a native SwiftUI app (Plan, Places with map, People, Where, Media). It reads the same `docs/trip.json`, keeps the last copy on the phone, and refreshes whenever it has signal (open the app or pull down). Photos and videos listed under `media` download once and play offline.

Install or update on Jerry's iPhone (plugged in or on the same Wi-Fi): `ios/install-on-iphone.sh`. Signed until Nov 2027.

## How to edit (anyone with access to this repo)

Everything on the site comes from one file: `docs/trip.json`. Change it and commit; the site updates in about a minute, and phones pick it up the next time they have signal.

On a phone: open github.com/jerryshi042003/trip, tap `docs`, then `trip.json`, then the pencil icon, edit, then Commit changes.

- `travelers.jerry` / `travelers.tom`: each person's `plan` (date, title, sub, place), `bucket` list, and `where` (live location link).
- `places`: id, city, name, addr, optional `ja` (Japanese address for taxis). A plan item's `place` must match a place `id`.
- `people`: name, role, optional group, and any of phone, whatsapp, email, ig, fb, web. Use the same group text for contacts that belong together. Tom can add apparel contacts under `Clothing` when ready. Use public contact links for new entries because the feed is public.
- `emergency`: name and phone.
- `media` (optional): list of {title, url, kind: "video" or "image", who}. Put files in `docs/media/` (each under 100 MB) and use the URL https://jerryshi042003.github.io/trip/media/<file>. The iPhone app downloads them for offline.

Keep it valid JSON (commas between items, double quotes). If the site goes blank after an edit, the JSON is broken; undo the last commit.

## Live location (Where tab)

Each person shares a Google Maps live-location link and pastes it into their `where` field:
Google Maps app, profile picture, Location sharing, New share, "Until you turn this off", Copy link.
Anyone with the site can then open it, family included, on iPhone or Android.

## For AI agents (Claude, Muse, Codex)

Read the current trip at https://jerry-trip.vercel.app/trip.json (public, no login).
To change it, edit `docs/trip.json` in this repo through the person's own GitHub access, keep the schema above, commit with a short message, and never delete other people's entries.
