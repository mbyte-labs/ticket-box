# Play Store phone screenshots

Everything needed to re-shoot the Play listing's phone screenshots on the Android emulator. Output goes to
`store_screenshots/` at the app root (gitignored): `raw/` holds the plain emulator captures, `phone/` the
finished 1080×2134 store images (brand-red canvas, white Urbanist caption, dark phone bezel).

## 1. Seed a demo library

The emulator's own library is usually too thin for good screenshots. `make_demo_backup.py` writes a
Ticket Box backup file (schemaVersion 5) with ~16 part-watched shows, ~16 movies, ratings, a watchlist
and favorites, spread over the last 12 months. It fetches per-season episode counts from TMDB (v3 key
read from `secrets.json` or `$TMDB_V3_KEY`) so every seeded episode exists; timestamps are evenings in the
host's local time zone, so keep the emulator in the same zone.

```bash
python3 tool/store_screenshots/make_demo_backup.py            # → tool/store_screenshots/demo_backup.json
adb push tool/store_screenshots/demo_backup.json /sdcard/Download/ticketbox_demo_backup.json
```

Before restoring, **snapshot the emulator's current DB** so it can be put back afterwards:

```bash
adb exec-out run-as ro.madcodestudios.ticket.box cat files/ticketbox_database.sqlite > store_screenshots/original_db_snapshot.sqlite
```

Then in the app (debug build via `flutter run`): if a TMDB account is logged in, turn the three *Sync*
toggles off first (belt and braces — restore bypasses the sync hooks and empties the outbox anyway, so
nothing from the demo library is ever pushed to TMDB). Set *Country* to United States of America (densest
"Watch now" providers), then *Settings → Restore from backup*, pick the pushed file, *Replace*. The
progress refresh job downloads each show's catalogue and fills Up Next / Show Progress within seconds
(`grep ShowProgressRefreshService` in the run log).

## 2. Capture

Use the website frame's geometry so the capture fits the screen area without distortion, and SystemUI
demo mode for a clean status bar:

```bash
adb shell wm size 1080x2313 && adb shell wm density 405
adb shell settings put global sysui_demo_allowed 1
D="adb shell am broadcast -a com.android.systemui.demo"
$D -e command enter; $D -e command clock -e hhmm 1000
$D -e command battery -e level 100 -e plugged false
$D -e command network -e mobile hide -e wifi show -e level 4 -e fully true
$D -e command notifications -e visible false
adb exec-out screencap -p > store_screenshots/raw/01_up_next.png     # one per page
```

Navigate with `adb shell input tap X Y` and screencaps (take a fresh capture before tapping — the
override size changes every coordinate). Pages and captions used for the current set:

| # | Page (how to get there) | Caption |
|---|---|---|
| 01 | Up next to watch (dismiss the country banner first) | See what to watch next across all your shows |
| 02 | Show details — Malcolm in the Middle (Search) | Every show at a glance: seasons, ratings and progress |
| 03 | Movie details — Terminator 2 (Search), scrolled to Ratings / Watch now / Cast | Find where to stream, rent or buy |
| 04 | Show Progress, first "View more details" expanded | Detailed progress of all your shows |
| 05 | Lists → Watchlist | Watchlist, favorites and dropped shows in one place |
| 06 | Discover, Filters expanded | Discover popular, top rated and trending titles |
| 07 | Stats | Your watching habits, by year and all time |
| 08 | History, filtered to Movies | Your full watch history, filtered your way |

Afterwards:

```bash
adb shell am broadcast -a com.android.systemui.demo -e command exit
adb shell settings put global sysui_demo_allowed 0
adb shell wm size reset && adb shell wm density reset
```

## 3. Compose

Needs Pillow; the Homebrew interpreter has it:

```bash
/opt/homebrew/bin/python3.14 tool/store_screenshots/compose.py store_screenshots/raw/01_up_next.png store_screenshots/phone/01_up_next.png "See what to watch next across all your shows"
```

Output is a 1080×2134 24-bit PNG (Play rejects alpha). Canvas colour, font size, bezel geometry and the
phone's top offset are constants at the top of `compose.py`. Captions are balanced over two lines
automatically.

## 3b. Feature graphic

`compose_feature.py` builds the 1024×500 listing banner from three raw captures: white mark + wordmark,
tagline and feature pills on the left, three phones fanned on the right (middle one forward). Text,
phone size and positions are constants at the top of the script.

```bash
/opt/homebrew/bin/python3.14 tool/store_screenshots/compose_feature.py store_screenshots/feature_graphic.png \
  store_screenshots/raw/02_show_details.png store_screenshots/raw/01_up_next.png store_screenshots/raw/04_show_progress.png
```

## 3c. README images

The root `README.md` shows a hero (tablet with the phone in front) and a small phone / tablet gallery
from `docs/screenshots/` (tracked, unlike `store_screenshots/`). `compose_readme.py` puts a raw capture
in the same dark bezel on a transparent background, so it reads on GitHub's light and dark themes, and
scales it down (phone 560 px wide, tablet 1400 px).

Phone captures are the `raw/` ones from step 2. For the tablet, launch the `Pixel_Tablet` emulator, seed
it the same way (step 1), turn demo mode on and capture at its native 2560×1600 into
`store_screenshots/raw_tablet/` — no `wm size` override. Give Discover a few seconds for its posters.

```bash
P=python3   # any interpreter with Pillow, e.g. one from `python3 -m venv` + `pip install pillow`
$P tool/store_screenshots/compose_readme.py phone  store_screenshots/raw/01_up_next.png docs/screenshots/phone_up_next.png
$P tool/store_screenshots/compose_readme.py tablet store_screenshots/raw_tablet/06_discover.png docs/screenshots/tablet_discover.png
$P tool/store_screenshots/compose_readme.py hero   store_screenshots/raw_tablet/01_up_next.png store_screenshots/raw/02_show_details.png docs/screenshots/hero.png
```

Current set: phone `up_next`, `show_details`, `show_progress`, `stats`; tablet `discover`,
`movie_details`, `show_progress`; hero = tablet Up next + phone show details.

## 4. Put the emulator back

Quit `flutter run` (never the emulator), then restore the snapshot and re-enable the sync toggles:

```bash
adb shell am force-stop ro.madcodestudios.ticket.box
adb push store_screenshots/original_db_snapshot.sqlite /data/local/tmp/ticketbox_database.sqlite
adb shell run-as ro.madcodestudios.ticket.box cp /data/local/tmp/ticketbox_database.sqlite files/ticketbox_database.sqlite
adb shell rm /data/local/tmp/ticketbox_database.sqlite /sdcard/Download/ticketbox_demo_backup.json
```

Play requirements, for reference: JPEG or 24-bit PNG, 320–3840 px per side, longer side at most twice
the shorter, up to 8 phone screenshots.
