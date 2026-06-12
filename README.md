# korimako

A tiny macOS menubar app that makes your hardware **media keys** (play/pause,
next, previous) control [ncspot](https://github.com/hrkfdn/ncspot).

It registers as a system **Now Playing** source so it wins media-key ownership
over browsers and other apps, shows the current track in the menubar and Control
Center, and forwards key presses to ncspot over its IPC socket.

## How it works

```
 media key  ──▶  MPRemoteCommandCenter  ──▶  korimako  ──▶  ncspot.sock
 (play/pause)                                    │              (playpause/next/previous)
                                                 ▼
 menubar + Control Center  ◀──  MPNowPlayingInfoCenter  ◀──  JSON status stream
```

- **IPC**: ncspot exposes a Unix domain socket (one connection, bidirectional).
  We stream its newline-delimited JSON status frames for metadata and write
  command tokens back. Socket path is discovered dynamically via `ncspot info`
  (`USER_RUNTIME_PATH/ncspot.sock`), falling back to `/tmp/ncspot-$UID/ncspot.sock`.
- **Media keys**: handled entirely via the public `MPNowPlayingInfoCenter` +
  `MPRemoteCommandCenter` — sufficient on macOS 13–26, and it preserves the
  system's natural now-playing handoff (pause ncspot and your browser gets the
  keys, like Spotify/Music). A private `MediaRemote` eligibility nudge is
  available as an escape hatch via `KORIMAKO_USE_PRIVATE=1`, but is off by
  default (it actually *blocks* the handoff, so you likely never want it). The
  Control Center **scrubber** is mapped to ncspot's `seek`, so you can drag to
  any position in the track.
- **Resilience**: auto-reconnects when ncspot starts/stops. When ncspot isn't
  running we relinquish Now Playing so the keys fall back to other apps.

## Requirements

- macOS 13+ (Apple Silicon or Intel)
- Swift toolchain (Command Line Tools is enough — **no Xcode required**)
- `ncspot` with IPC (Homebrew's build has it)

## Build & run

```sh
./scripts/build-app.sh          # builds korimako.app (ad-hoc signed)
open korimako.app             # launch (menubar icon appears, no Dock icon)
```

Install it for everyday use:

```sh
cp -R korimako.app /Applications/
```

Then enable **Launch at Login** from the menubar menu.

## Menu

- Current track (artist – title), also shown next to the menubar icon
- **Artwork Style** — pick a Core Image effect for the album art (Comic, Poster,
  Ink Sketch, Noir, Sepia, Pixel, Thermal, Neon Edges, or Original). Applies live
  and persists across launches.
- **Launch at Login** toggle
- **Quit**

## Development

Built with SwiftPM; `scripts/build-app.sh` produces the signed `.app`.

- **Debug logging** — run with `KORIMAKO_DEBUG=1` to log IPC, remote commands,
  and now-playing updates (via NSLog / stderr).
- **Artwork styles** live in `Sources/korimako/ArtworkTransform.swift`. The
  `Cartoon` style is a small Core Image pipeline; its main knobs are the posterize
  `levels` (4), edge `threshold` (0.22) and `intensity` (4).
- **Preview a style** through the *real* pipeline without touching Control Center
  — renders a side-by-side `[original | styled]` PNG:
  ```sh
  ./korimako.app/Contents/MacOS/korimako --render <style> <coverURL> [out.png]
  # e.g. --render cartoon https://i.scdn.co/image/<id> /tmp/out.png
  ```
- **Watch ncspot live** — `scripts/watch-ncspot.py` prints playback/track changes
  from the IPC socket (read-only).

## Notes

- The app is ad-hoc signed for personal use. macOS Gatekeeper may ask you to
  approve it the first time.
- `Launch at Login` uses `SMAppService` and works best when the app lives in
  `/Applications`.
