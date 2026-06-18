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

### Entertainment category
korimako is now registered with macOS as an Entertainment app (`LSApplicationCategoryType`), which affects how it appears in Spotlight, Finder's Get Info, and App Store categorization.
