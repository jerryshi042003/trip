# Trip

Trip planner for Jerry and Tom: https://jerryshi042003.github.io/trip/

Tom can open his Plan directly at https://jerryshi042003.github.io/trip/?who=tom. On iPhone, open it in Safari, choose Share → Add to Home Screen, keep Open as Web App on, and tap Add. Open Trip online once to cache it.

## iPhone app

`ios/` is a native SwiftUI app (Plan, Places with map, People, Where, Media). It reads the same `docs/trip.json`, keeps the last copy on the phone, and refreshes whenever it has signal (open the app or pull down). Photos and videos listed under `media` download once and play offline.

Install or update on Jerry's iPhone (plugged in or on the same Wi-Fi): `ios/install-on-iphone.sh`. Signed until Nov 2027.

## How to edit (anyone with access to this repo)

Tom’s Plan has **Edit updates** for one plain-text public note per line in `docs/tom-notes.txt`. Lines starting with `#` are editor instructions. **Edit full plan** opens `docs/trip.json` for itinerary, tasks, places and contacts. Both links use GitHub’s editor and require an account with write access. Open Trip online after Pages publishes the commit.

- `travelers.jerry` / `travelers.tom`: each person's `plan` (date, title, sub, place) and `bucket` list. Optional `todos` holds ordered sections with a `title` and `items`. Each item has a `title`, `detail`, and optional `link` and `draft`. Drafts are shown for copying.
- `places`: id, city, name, addr, optional `ja` (Japanese address for taxis). A plan item's `place` must match a place `id`.
- `people`: name, role, optional group, and any of phone, whatsapp, email, ig, fb, web. Use the same group text for contacts that belong together. Tom can add apparel contacts under `Clothing` when ready. Use public contact links for new entries because the feed is public.
- `emergency`: name and phone.
- `media` (optional): list of {title, url, kind: "video" or "image", who}. Put files in `docs/media/` (each under 100 MB) and use the URL https://jerryshi042003.github.io/trip/media/<file>. The iPhone app downloads them for offline.

Keep it valid JSON (commas between items, double quotes). If the site goes blank after an edit, the JSON is broken; undo the last commit.

## Live location (Where tab)

Open Google Maps → profile picture → Location sharing → New share. Choose **Until you turn this off** and select the other person’s Gmail account. Each person starts their own share. Live locations are visible to the selected accounts in Google Maps. Trip does not request location permission.

## For AI agents (Claude, Muse, Codex)

Read the current trip at https://jerryshi042003.github.io/trip/trip.json (public, no login).
To change it, edit `docs/trip.json` in this repo through the person's own GitHub access, keep the schema above, commit with a short message, and never delete other people's entries.
