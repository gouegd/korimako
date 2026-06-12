# korimako

> *Korimako* is the Māori name for the New Zealand bellbird — known for its
> clear, musical call.

A tiny macOS menubar app that makes your hardware **media keys** (play/pause,
next, previous) control [ncspot](https://github.com/hrkfdn/ncspot).

It registers as a system **Now Playing** source so it wins media-key ownership
over browsers and other apps, shows the current track in the menubar and Control
Center, and forwards key presses to ncspot over its IPC socket.

## How it works

```
 media key  ──▶  MPRemoteCommandCenter  ──▶  korimako  ──▶  ncspot.sock
 (play/pause)                                    │           (playpause/next/previous)
                                                 ▼
 menubar + Control Center  ◀──  MPNowPlayingInfoCenter  ◀──  JSON status stream
```

- **IPC**: ncspot exposes a Unix domain socket (one connection, bidirectional).
  Status frames are newline-delimited JSON; commands are plain text tokens.
  Socket path is discovered via `ncspot info` (`USER_RUNTIME_PATH/ncspot.sock`),
  falling back to `/tmp/ncspot-$UID/ncspot.sock`.
- **Media keys**: handled entirely via the public `MPNowPlayingInfoCenter` +
  `MPRemoteCommandCenter` — sufficient on macOS 13–26, and it preserves the
  system's natural now-playing handoff (pause ncspot and your browser gets the
  keys back, just like Spotify or Music). A private `MediaRemote` eligibility
  nudge is available as an escape hatch via `KORIMAKO_USE_PRIVATE=1`, but is
  off by default (it blocks handoff).
- **Scrubber**: the Control Center position scrubber maps to ncspot's `seek`
  command, so you can drag to any position in the current track.
- **Resilience**: auto-reconnects when ncspot starts/stops. Relinquishes Now
  Playing ownership when ncspot isn't running so keys fall back to other apps.

## Requirements

- macOS 13+ (Apple Silicon or Intel)
- Swift toolchain (Command Line Tools — **no Xcode required**)
- `ncspot` with IPC enabled (Homebrew's build includes it)

## Build & run

```sh
./scripts/build-app.sh          # builds korimako.app (ad-hoc signed)
open korimako.app               # launch — menubar icon appears, no Dock icon
```

Install for everyday use:

```sh
cp -R korimako.app /Applications/
```

Then enable **Launch at Login** from the menubar menu.

## Menu

- **Current track** — album art thumbnail (styled per your Artwork Style
  selection), ▶ artist – title. Click to play/pause.
- **Recently played** — last two tracks (artist – title); informational.
- **Artwork Style** — apply a Core Image effect to album art: Original,
  Cartoon, Comic, Poster, Ink Sketch, Noir, Sepia, Pixel, Thermal, Neon
  Edges. Applies immediately and persists across launches.
- **Launch at Login** toggle
- **Quit**

## Development

Built with SwiftPM; `scripts/build-app.sh` assembles and ad-hoc-signs the
`.app` bundle.

**Debug logging** — set `KORIMAKO_DEBUG=1` to log IPC frames, remote
commands, and now-playing state to stderr.

**Artwork styles** live in `Sources/korimako/ArtworkTransform.swift`. The
`Cartoon` style is a cel-shading pipeline (flat posterised fills + thresholded
inked outlines). Key knobs: posterize `levels` (4), edge `threshold` (0.22),
edge `intensity` (4).

**Preview a style** offline — renders a `[original | styled]` side-by-side PNG
through the real pipeline without touching Control Center:

```sh
./korimako.app/Contents/MacOS/korimako --render <style> <coverURL> [out.png]
# e.g. --render cartoon https://i.scdn.co/image/<id> /tmp/preview.png
```

**Watch ncspot live** — `scripts/watch-ncspot.py` tails the IPC socket and
prints track/playback changes (read-only).

## Notes

- Ad-hoc signed for personal use. macOS Gatekeeper may prompt you to approve
  it on first launch.
- Launch at Login uses `SMAppService` and works best when the app lives in
  `/Applications`.

## License

MIT — see [LICENSE](LICENSE).
