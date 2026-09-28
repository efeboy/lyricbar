# Lyrics

## Lyrics are never truncated

macOS has no menu bar marquee, so long lines go through a cascade with no
truncating step:

1. **Split at word boundaries** (`LyricReflow.split` → `wordPlan`) so every chunk
   fits the box at the base font, and give each chunk its own timestamp.
2. **Prefer shrinking in a tight window.** If the line's time window cannot give
   each chunk `minChunkDuration` (1.5s), and the whole line fits at the minimum
   font size, keep it whole and let `LyricText` shrink it.
3. **Otherwise split anyway.** Chunks that pass quickly beat words never seen.
4. **Break a word wider than the box at grapheme boundaries** (`graphemePlan`).
   At the 80pt floor an 18-character word already qualifies.
5. **`LyricText.fittedFontSize` is the backstop**, shrinking from the base size
   toward `MenuBarMetrics.minimumFontSize` (9pt).

Step 5 stops at 9pt whether or not the text fits; the guarantee comes from steps
1–4 having already produced chunks that fit at the base font. A raw, unreflowed
line can still overflow, and `LyricLabel` clips it. So end-to-end fit is asserted
on reflowed chunks (`NoTruncationTests`), never on raw lines.

Step 2 is a real measurement: `expand` takes a `measureShrunk` closure measuring
at the minimum font size. Both closures are injectable for tests.

**Split plans rank by chunk count first**, then break quality, then even widths.
Ranking by balance first keeps preferring more, narrower chunks, and every extra
chunk shortens its time on screen.

**Where to break** was measured on 2585 synced lines at a 280pt budget: 9.5% of
lines overflow, 92.3% of those split cleanly, and 95.6% of breaks fall on
punctuation or a conjunction/preposition. (Measured with an older semibold font,
so indicative.)

**When to swap chunks** is audio alignment, and LRCLIB publishes no word timing.
Syllable share is the best free proxy: a median of 0.14s from character share,
against 0.60s (p90 1.69s) for a naive midpoint. An on-device model would not
help — it cannot hear the vocal.

## LRCLIB

Verified against the server source (github.com/tranxuanthang/lrclib, MIT):

- `GET /api/get` needs `track_name` and `artist_name`; `album_name` and
  `duration` are optional. It matches an exact signature and often misses across
  remasters and editions.
- `GET /api/search` is the fallback. The client picks the candidate with the
  closest duration and rejects matches more than 5s off
  (`LRCLibClient.durationTolerance`).
- Responses are camelCase (`syncedLyrics`, `plainLyrics`, `instrumental`).
- Send `Lrclib-Client`; the server prefers it over `User-Agent`. The identifier
  is `LyricBar/1.0 (https://github.com/efeboy/lyricbar)`. LRCLIB asks for a
  reachable contact, so update it if the repository moves.
- No API key, but there is backpressure: **503 + `Retry-After`**. The per-track
  fetch sleeps and retries the same track, so a track that starts during a
  backoff still gets lyrics.

Tracks with no synced match, and instrumentals, show a dimmed `♪`.

## Privacy

Never print lyric text to logs, stdout, test failure messages, or the menu
header. The header shows track and artist only. Diagnostics report timing,
counts and geometry. Test fixtures use invented lines, not real lyrics.
