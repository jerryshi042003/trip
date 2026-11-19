# Trip

Trip planner for Jerry and Tom: https://jerryshi042003.github.io/trip/

Send Tom https://jerryshi042003.github.io/trip/tom/ or tap **Share Trip** in the app. On his iPhone, open the link in Safari, choose **Share → Add to Home Screen**, keep **Open as Web App** on, and tap **Add**. Open the new icon once online. Trip refreshes when it opens, returns to the foreground or reconnects.

## iPhone app

`ios/` is a native SwiftUI app (Plan, Places with map, People, Where, Media). It reads the same `docs/trip.json`, keeps the last copy on the phone, and refreshes whenever it has signal (open the app or pull down). Photos and videos listed under `media` download once and play offline.

For Tom, the native build is distributed through TestFlight. Share the single-slot invitation privately once Apple approves the first build. After installing, Tom can turn on automatic updates in TestFlight. It is only necessary to upload a new build for app changes. Plan and notes edits refresh from GitHub Pages inside the installed app.

For a direct development install on Jerry’s iPhone, connect it to Xcode (USB or paired Wi-Fi) and run `ios/install-on-iphone.sh`.

## How to edit (anyone with access to this repo)

In Tom’s Plan, tap **Edit updates** for quick notes. Sign in to GitHub as `@tomohto`, write one public note per line in `docs/tom-notes.txt`, then tap **Commit changes** and confirm. For itinerary, tasks or People, tap **Edit full plan**. It opens `docs/trip.json` in GitHub’s editor. Once Pages publishes the commit, return to Trip online to see the change.

- `travelers.jerry` / `travelers.tom`: each person's `plan` (date, title, sub, place) and `bucket` list. Optional `todos` holds ordered sections with a `title` and `items`. Each item has a `title`, `detail`, and optional `link` and `draft`. Drafts are shown for copying.
- `places`: id, city, name, addr, optional `ja` (Japanese address for taxis). A plan item's `place` must match a place `id`.
- `people`: name, role, optional group, and any of phone, whatsapp, email, ig, fb, web. Use the same group text for contacts that belong together. Tom can add apparel contacts under `Clothing` when ready. Use public contact links for new entries because the feed is public.
- `emergency`: name and phone.
- `media` (optional): list of {title, url, kind: "video" or "image", who}. Put files in `docs/media/` (each under 100 MB) and use the URL https://jerryshi042003.github.io/trip/media/<file>. The iPhone app downloads them for offline.

Keep it valid JSON (commas between items, double quotes). If the site goes blank after an edit, the JSON is broken; undo the last commit.

## Live location (Where tab)

[Open the family map](https://jerryshi042003.github.io/trip/?view=where) in any phone browser. It opens without an account. In the native iPhone app, tap **Where**. Both views show the latest point for each person, its age, and battery when reported. They check for new points every minute while open. Locations older than 15 minutes say “Last seen”; after 24 hours they leave the map.

### Enable sharing on each phone

1. Follow the **Turn on your live pin** task in Plan. Install OwnTracks and enable external configuration in its settings.
2. Open your private setup link and tap **Open your setup in OwnTracks**. Confirm the configuration. Turn external configuration off again after importing if desired.
3. In iPhone Settings → Apps → OwnTracks → Location, set **Always** and enable **Precise Location**. Open OwnTracks and publish one point to check your pin. Keep OwnTracks running. Significant mode reports when the OS detects movement, including with the screen locked. It has no fixed reporting interval.
4. To stop, set OwnTracks to Manual. Trip hides the last point after 24 hours. The operator can clear it immediately with the phone credential as described below.

### Google Maps fallback

From Google Maps, use profile picture → **Location sharing** → **New share** and copy a public link. Add the real link to the matching traveler’s `where` field. Where shows a **Google Maps share** button beside that traveler. Public Google Maps share links expire after at most 24 hours.

### Hosting and credentials

`api/location.mjs` runs on the existing `trip` Vercel Hobby project at `https://jerry-trip.vercel.app/api/location`. The same read endpoint is used by GitHub Pages and MapKit. Public GET returns only the current point per traveler and never requires a login. OwnTracks uses HTTPS Basic Auth to POST updates, with a distinct token and SHA-256 secret per phone (`TRIP_JERRY_SHA256`, `TRIP_TOM_SHA256`). The app uses a private Vercel Blob store with one object per phone and no trail. Authenticated DELETE clears the caller’s point. Never place setup links or write credentials in trip.json, documentation, or GitHub.

Release web changes from this repo to GitHub Pages (`main:docs/`) and Vercel (`jerryshi042003s-projects/trip`). Vercel must have the connected private Blob store and the two digest variables before releasing the API. Build the native target from `ios/project.yml` and publish through Apple TestFlight or the direct install script.

## For AI agents (Claude, Muse, Codex)

Read the current trip at https://jerryshi042003.github.io/trip/trip.json (public, no login).
To change it, edit `docs/trip.json` in this repo through the person's own GitHub access, keep the schema above, commit with a short message, and never delete other people's entries.
