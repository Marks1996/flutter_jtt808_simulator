# Simulator reference update

## Direction contract

**THESIS:** Match the supplied desktop screenshots: an inset navigation surface beside an unframed workspace, with compact, clearly separated settings cards. Preserve the simulator's real content and workflows; do not reproduce the reference application's analytics or red annotation boxes.

**OWN-WORLD:** Neutral charcoal window and workspace, slightly lighter sidebar/cards, quiet one-pixel dividers, neutral selected navigation, blue principal actions. Keep bundled Plex typography, original Fluent Color navigation artwork, and semantic status colors. Light mode keeps the same geometry.

**STORY:** Operators select a simulator area, inspect actual terminal/task/message totals, then configure or run a terminal. Settings remain immediately usable without introducing new edit/save modes.

**FIRST VIEWPORT:** A 248px desktop navigation region contains a rounded inset panel with left-aligned rows. Navigation groups remain near the top; local workspace information sits at the bottom. The right-hand page begins with a compact heading and actions. Settings cards span the page, with an independent header/divider/body; forms use available width. Console totals share a divided summary strip, showing only real counts.

**FORM:** User-pinned desktop reference, code-led. Native window controls and mobile navigation remain intact. Selection feedback uses the existing component hover/focus behavior; no ornamental entrance motion. seed: none (user-provided reference).

**FINISH:** unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## Completion

### Theme correction after native screenshot feedback

- The light workspace now shares the window's `surface` canvas (`#F3F4F5`), with white sidebar/cards; the standalone white workspace slab is removed.
- `ShadSwitch` explicitly uses white `onPrimary` thumbs on blue checked / neutral unchecked tracks in both themes. This fixes the library default that inherited the near-black dark-theme background as its thumb.
- Two regression tests inspect actual rendered switch decorations in both on/off states and assert consistent Material/shadcn canvas roles. All 209 randomized tests passed; static analysis passed.
- Four inspected 1100×720 widget renders, `.impeccable/review/theme-fix-{light,dark}-{on,off}.png`, supersede the earlier palette evidence for this correction. Temporary capture code was removed. These are widget renders, not system-window screenshots.

### Route editor width and scroll-gutter correction

- Widened create/edit route dialogs from 640px to 1040px, bounded by the viewport. At an 800px content width, visual planning uses left-side controls and a right-side map. Valid CSV previews use the same split; phone layouts remain stacked.
- Reserved a 16px end gutter through the library dialog's `scrollPadding`; kept the default outer padding, pinned header/footer, and existing draft/save guard.
- All 221 randomized tests passed (seed `20261030`), including 12 new light/dark desktop/phone layout cases and an extended 18-waypoint regression that drags the free scroll gutter while checking pinned title/actions.
- Four inspected widget renders at `.impeccable/review/route-editor-{1100,390}-{light,dark}.png` show the revised modal with offline maps (no tile/network requests). These are widget renders rather than native window screenshots. Temporary capture code was removed.

### Original reference update

- Finish review: ship. The targeted follow-up scored the dark-link hover contrast fix resolved by source review; no hovered-state screenshot was captured.
- Documentation: updated `DESIGN.md` and `.impeccable/design.json` from the built theme/layout, retaining existing project conventions. No new shipping image assets were introduced.
- Verification: 207 randomized tests passed with seed `20261030`; static analysis and the macOS Debug build passed. Native hot reload succeeded with no reported runtime errors. Temporary capture code was removed.
- Visual evidence: eight valid widget-rendering captures in `.impeccable/review/` (console/settings, light/dark, 1100×720/390×844). The test workspace is illustrative; production still starts empty. Captures are not native system-window screenshots and do not establish physical-device or screen-reader coverage.
