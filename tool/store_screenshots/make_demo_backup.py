#!/usr/bin/env python3
"""Generate a Ticket Box backup file (schemaVersion 5) holding a curated demo library, for
store-screenshot shoots on an emulator.

The library is deterministic (fixed seed) and spans the last ~12 months so Up Next, Show Progress,
History and Stats all have something to show. Per-season episode counts are fetched from TMDB
(v3 key read from secrets.json or $TMDB_V3_KEY) so every seeded episode really exists; a few shows are
left mid-season on purpose so Up Next has a next episode.

Usage (from the app root):
    python3 tool/store_screenshots/make_demo_backup.py [out.json]   # default: tool/store_screenshots/demo_backup.json

Restore it through Settings → "Restore from backup" (see README.md). Stdlib only.
"""
import json
import os
import random
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
KEY_FILE = os.path.join(ROOT, 'secrets.json')
DEFAULT_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'demo_backup.json')

# (tmdbId, name, target) — target is how far the demo user got:
#   ('season', n)       → every aired episode of seasons 1..n
#   ('episode', s, e)   → seasons 1..s-1 complete, season s up to episode e (so Up Next = s x e+1)
SHOWS = [
    (2004, 'Malcolm in the Middle', ('episode', 4, 9)),
    (74387, 'Final Space', ('episode', 2, 6)),
    (1396, 'Breaking Bad', ('episode', 4, 5)),
    (2316, 'The Office', ('episode', 3, 12)),
    (66732, 'Stranger Things', ('episode', 4, 3)),
    (95396, 'Severance', ('episode', 2, 4)),
    (136315, 'The Bear', ('episode', 3, 2)),
    (76331, 'Succession', ('season', 4)),
    (97546, 'Ted Lasso', ('episode', 3, 7)),
    (100088, 'The Last of Us', ('episode', 2, 2)),
    (106379, 'Fallout', ('season', 1)),
    (126308, 'Shōgun', ('episode', 1, 6)),
    (76479, 'The Boys', ('episode', 3, 4)),
    (95480, 'Slow Horses', ('episode', 2, 3)),
    (107113, 'Only Murders in the Building', ('episode', 2, 5)),
    (1408, 'House', ('episode', 2, 11)),
]

# (tmdbId, title)
MOVIES = [
    (280, 'Terminator 2: Judgment Day'),
    (693134, 'Dune: Part Two'),
    (872585, 'Oppenheimer'),
    (27205, 'Inception'),
    (157336, 'Interstellar'),
    (603, 'The Matrix'),
    (496243, 'Parasite'),
    (545611, 'Everything Everywhere All at Once'),
    (569094, 'Spider-Man: Across the Spider-Verse'),
    (361743, 'Top Gun: Maverick'),
    (792307, 'Poor Things'),
    (238, 'The Godfather'),
    (680, 'Pulp Fiction'),
    (244786, 'Whiplash'),
    (218, 'The Terminator'),
    (155, 'The Dark Knight'),
]

# Unwatched titles on the watchlist: (type, tmdbId, title)
WATCHLIST = [
    ('movie', 1184918, 'The Wild Robot'),
    ('movie', 823219, 'Flow'),
    ('movie', 974576, 'Conclave'),
    ('movie', 558449, 'Gladiator II'),
    ('show', 94997, 'House of the Dragon'),
    ('show', 84958, 'Loki'),
    ('show', 125988, 'Silo'),
    ('show', 71912, 'The Witcher'),
]

# Favorites (type, tmdbId)
FAVORITES = [
    ('show', 2004),
    ('show', 1396),
    ('show', 74387),
    ('movie', 280),
    ('movie', 27205),
    ('show', 95396),
]

# Ratings 1..10 for watched titles
RATINGS = {
    ('show', 2004): 10, ('show', 74387): 9, ('show', 1396): 10, ('show', 2316): 9, ('show', 66732): 8,
    ('show', 95396): 9, ('show', 136315): 8, ('show', 76331): 9, ('show', 97546): 8, ('show', 100088): 9,
    ('show', 106379): 8, ('show', 126308): 9, ('show', 76479): 8, ('show', 95480): 8, ('show', 107113): 7,
    ('show', 1408): 9,
    ('movie', 280): 10, ('movie', 693134): 9, ('movie', 872585): 9, ('movie', 27205): 10, ('movie', 157336): 9,
    ('movie', 603): 10, ('movie', 496243): 9, ('movie', 545611): 8, ('movie', 569094): 9, ('movie', 361743): 8,
    ('movie', 792307): 7, ('movie', 238): 10, ('movie', 680): 9, ('movie', 244786): 9, ('movie', 218): 8,
    ('movie', 155): 10,
}


def tmdb_key():
    key = os.environ.get('TMDB_V3_KEY')
    if not key and os.path.exists(KEY_FILE):
        with open(KEY_FILE, encoding='utf-8') as f:
            key = json.load(f).get('TMDB_V3_KEY')
    if not key:
        sys.exit('TMDB v3 key not found: set TMDB_V3_KEY or create ' + KEY_FILE + ' (see secrets.example.json)')
    return key


def fetch_season_counts(key, tmdb_id):
    """Return {season_number: aired_episode_count} for seasons >= 1."""
    url = 'https://api.themoviedb.org/3/tv/%d?%s' % (tmdb_id, urllib.parse.urlencode({'api_key': key}))
    with urllib.request.urlopen(url, timeout=30) as r:
        data = json.load(r)
    today = datetime.now(timezone.utc).date().isoformat()
    counts = {}
    for s in data.get('seasons', []):
        n = s.get('season_number', 0)
        if n < 1:
            continue
        air = s.get('air_date') or ''
        if air and air > today:
            continue
        counts[n] = s.get('episode_count', 0)
    return data.get('name', ''), counts


def iso(dt):
    return dt.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    rng = random.Random(20261023)
    key = tmdb_key()
    # Local time of the machine running this (set the emulator to the same zone) so evenings stay evenings.
    now = datetime.now().astimezone().replace(minute=0, second=0, microsecond=0)
    start = now - timedelta(days=365)

    history = []
    ratings = []
    watchlist = []
    favorites = []

    # Shows: each gets a start day in the past year; episodes are watched in sittings of 1-3,
    # every 1-3 days, finishing before "now". Longer backlogs start earlier.
    for tmdb_id, name, target in SHOWS:
        api_name, counts = fetch_season_counts(key, tmdb_id)
        print('%-32s %s' % (name, ' '.join('S%d=%d' % kv for kv in sorted(counts.items()))))
        episodes = []  # (season, episode)
        if target[0] == 'season':
            last_s = target[1]
            for s in range(1, last_s + 1):
                episodes += [(s, e) for e in range(1, counts.get(s, 0) + 1)]
        else:
            _, s_t, e_t = target
            for s in range(1, s_t):
                episodes += [(s, e) for e in range(1, counts.get(s, 0) + 1)]
            episodes += [(s_t, e) for e in range(1, min(e_t, counts.get(s_t, 0)) + 1)]
        if not episodes:
            sys.exit('no episodes for %s — check the target against the season counts' % name)
        # Spread the run so the last sitting lands within the past ~60 days.
        sittings = []
        i = 0
        while i < len(episodes):
            k = rng.randint(1, 3)
            sittings.append(episodes[i:i + k])
            i += k
        end = now - timedelta(days=rng.randint(1, 60))
        t = end
        days_between = [rng.randint(1, 3) for _ in sittings]
        total = sum(days_between)
        if end - timedelta(days=total) < start:
            # compress to fit the year
            scale = max(1, total) / max(1, (end - start).days - 1)
            days_between = [max(1, int(d / scale)) for d in days_between]
        t = end
        stamps = []
        for d in reversed(days_between):
            stamps.append(t)
            t -= timedelta(days=d)
        stamps.reverse()
        for sitting, day in zip(sittings, stamps):
            base = day.replace(hour=rng.choice([19, 20, 21, 22]), minute=rng.choice([0, 15, 30, 45]))
            for j, (s, e) in enumerate(sitting):
                history.append({
                    'type': 'episode', 'tmdbId': None, 'imdbId': None,
                    'showTmdbId': tmdb_id, 'season': s, 'episode': e,
                    'addedAt': iso(base + timedelta(minutes=45 * j)), 'historyType': 'watch',
                })
        r = RATINGS.get(('show', tmdb_id))
        if r:
            ratings.append({'type': 'show', 'tmdbId': tmdb_id, 'imdbId': None, 'rating': r, 'ratedAt': iso(stamps[-1])})

    # Movies: scattered evenings over the year.
    for tmdb_id, title in MOVIES:
        day = start + timedelta(days=rng.randint(3, 362))
        when = day.replace(hour=rng.choice([18, 20, 21, 22]), minute=rng.choice([0, 30]))
        history.append({'type': 'movie', 'tmdbId': tmdb_id, 'imdbId': None, 'addedAt': iso(when), 'historyType': 'watch'})
        r = RATINGS.get(('movie', tmdb_id))
        if r:
            ratings.append({'type': 'movie', 'tmdbId': tmdb_id, 'imdbId': None, 'rating': r, 'ratedAt': iso(when + timedelta(hours=2))})

    for kind, tmdb_id, _title in WATCHLIST:
        when = now - timedelta(days=rng.randint(1, 90))
        watchlist.append({'type': kind, 'tmdbId': tmdb_id, 'imdbId': None, 'listedAt': iso(when)})

    for kind, tmdb_id in FAVORITES:
        when = now - timedelta(days=rng.randint(1, 200))
        favorites.append({'type': kind, 'tmdbId': tmdb_id, 'imdbId': None, 'favoritedAt': iso(when)})

    history.sort(key=lambda h: h['addedAt'])
    payload = {
        'schemaVersion': 5,
        'exportedAt': iso(now),
        'history': history,
        'ratings': ratings,
        'watchlist': watchlist,
        'favorites': favorites,
    }
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(payload, f, indent=1, ensure_ascii=False)
    print('wrote %s: %d history, %d ratings, %d watchlist, %d favorites' % (out, len(history), len(ratings), len(watchlist), len(favorites)))


if __name__ == '__main__':
    main()
