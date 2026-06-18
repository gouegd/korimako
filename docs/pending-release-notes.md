## What's new

### Light/dark mode support
All colors now follow the system appearance setting:
- Artist name, track title, time display, and previous track labels adapt automatically between light and dark mode
- Album art border uses the system separator color — subtle in both modes

### Album art border
A thin, appearance-adaptive border is drawn around both the current and previous track album art, matching whatever shade of gray fits the active system theme.

### Back/forward hover reveal
Hovering the ⏮ or ⏭ buttons now triggers two layered effects:
- The button itself shows the thermal album art through the button's icon shape
- The main album art simultaneously reveals the same thermal art through a large backward/forward icon mask — the same technique used for the pause/play reveal on art hover

### Extra right margin fix
The menu widget no longer shows an asymmetric right margin when a long track title or artist name triggers the marquee scroll. Root cause: AppKit's `fittingSize` walks raw CALayer frame geometry and ignores `masksToBounds`, so the oversized `textLayer` (set to natural text width for scrolling) was leaking out and making NSMenu size its window much wider than 280 px. Fixed by overriding `fittingSize` in both `NowPlayingMenuView` and `MarqueeLabel`.

### Entertainment category
korimako is now registered with macOS as an Entertainment app (`LSApplicationCategoryType`), which affects how it appears in Spotlight, Finder's Get Info, and App Store categorization.
