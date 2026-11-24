# Updating the Trip app

Jerry and Tom can both update the app. There are two kinds of change.

## 1. Plan, people, to-dos, drafts, Listen & read

Most updates are this kind. No new app build is needed.

All of this lives in `docs/trip.json` (and `docs/listen/*.md` for the transcripts). A push to `main` goes live like this:

1. GitHub Pages republishes in about 40 seconds.
2. The iPhone app downloads the new file when it opens, when it comes back from the background, or when you pull down on a list. The website does the same.

Tested Nov 19, 2026: pushed 16:34:41, live on Pages 16:35:19, in the iPhone app (Simulator) on reopen 16:35:24.

**With Claude Code** (on Jerry's or Tom's Mac, in a clone of this repo):

> Update the Trip app: <what to change>. Edit docs/trip.json, run `python3 scripts/check_trip.py`, then commit and push to main.

The check matters. If `trip.json` is broken, the iPhone app quietly keeps the old copy. The repo also runs the same check on every push ("Check trip.json" in the Actions tab), and GitHub emails whoever pushed if it fails.

**From a phone or with Muse:**
1. Open https://github.com/jerryshi042003/trip/edit/main/docs/trip.json (also linked in the app). You must be signed in as `jerryshi042003` or `tomohto`; both have write access.
2. Edit the file and commit to `main`.
3. Check the Actions tab for a green "Check trip.json".

Any agent that can drive the GitHub editor or push to the repo can do the same.

Field rules the app needs:
- Every to-do item needs `title` and `detail` as text.
- `link` must be a full `https://` URL. (Since build 8 the app skips one bad item instead of keeping the old copy, but the check still matters.)
- `draft` is optional.
- On Jerry’s Plan, a to-do section with `region` appears in the destination picker. Give it a `category` to put it under a topic. Older iPhone builds display those same sections in their original list layout.
- Dashboard items can include `meta` (date or travel estimate), `place` and `from` (place IDs for Maps), `linkLabel`, an app `icon`, and a `photos` array with `url` and `caption`. Paths such as `media/places/pca.jpg` resolve against the Trip site.
- Every person needs a `name`.
- No private phone numbers or emails: the site is public.

## 2. App code (anything in `ios/`)

This needs a new TestFlight build. Once Apple processes it, it reaches the "Trip internal" testers on its own, and TestFlight's Automatic Updates installs it.

- **From Jerry's Mac:** run `ios/release-testflight.sh`. It bumps the build number, archives and uploads.
- **From GitHub, no Mac:** Actions tab → "Release TestFlight build" → Run workflow. This needs three repository secrets from an App Store Connect Team API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`), which Jerry creates once in App Store Connect → Users and Access → Integrations.
- **Tom building it himself:** `ios/build-for-my-iphone.sh`. See the README.
- **One-tap install link, no TestFlight:** https://jerryshi042003.github.io/trip/install/. Tom taps "Get my iPhone ID" once. Jerry registers that iPhone, then runs `ios/release-adhoc.sh`. After that, "Install" puts the app on Tom's iPhone, and re-tapping it after each `ios/release-adhoc.sh` run brings new app code. Registering new iPhones happens automatically when the `ASC_KEY_*` variables are set; without them, add the iPhone at https://developer.apple.com/account/resources/devices/add.
