# JT808 workbench redesign

Direction: Taste `framed-sheet`, seed 1584029885. Flutter native application, not a web landing page.

## User constraint
The core defect is too much container and control size for too little content. Compact sizing is a deliberate override to the sheet's medium-density 24px gutters, not a reduced font-size exercise. Empty data is never replaced with sample traffic or inflated counters.

## Product inventory
- JT/T 808-2013 native TCP terminal identities (12-digit phone, manufacturer, model, plate).
- Explicit server address and port, never implicit network sessions.
- Real connection lifecycle: disconnected, connecting, registering, authenticating, online, failed.
- Position reports with WGS84 coordinates, speed, heading, altitude, ACC and alarm bits.
- CSV polylines whose geometry is not road navigation.
- Per-terminal route tasks, paused/running/completed and actual progress.
- Protocol IDs, sequence numbers, byte lengths, raw HEX and correlated platform replies.
- Bounded live logs with filtering, pause-display, copy and clear.
- Local workspace persistence and explicit import/export containing credentials.
- macOS native traffic lights with a title-free drag strip; mobile touch targets.

## Interface questions
- Console: which terminal am I operating, can it connect, and what has it actually sent?
- Terminals: which identity/server/connection needs action?
- Routes and tasks: which polyline belongs to which terminal and is playback ready/running?
- Logs: which exact incoming/outgoing frame explains the observed behavior?
- Settings: how do appearance and local data change, and what protocol is supported?

## Spatial thesis
One quiet navigation column, one inset work surface. The product's face is its connection lifecycle and readable protocol identifiers rather than dashboard tiles. IBM Plex Sans is bundled for Latin/UI text, system CJK fallback for Chinese; IBM Plex Mono only for protocol identifiers and coordinates.

No empty card with a fixed minimum height. No four large zero metrics. Empty states are compact leading-aligned rows; secondary guidance is a text note, not a second card. Content is intrinsic-height and bounded to readable widths. Lists grow with records and only become scroll regions once enough records exist.

Light: neutral grey frame, white sheet, restrained borders. Dark: neutral charcoal frame/sheet, no navy. Near-black/inverted primary buttons; blue only for the route, focus and meaningful data. No resting shadows. Small 6px controls / 8px sections / 12px sheet corners.

## Baseline critique
ROUND 0
Seen in one second: two large empty route/task cards inside a dark navy frame.
Idea: the terminal's connection and packet evidence should define the operating layout.
Live thing: existing real connections, playback and packet inspection; no new decorative interaction.
Layout words: console=stacked cards / terminals=cards or table / routes=two empty cards / logs=filter grid and fixed region / settings=full-width cards.
Top three problems:
1. Empty route/task cards repeat headings and large centered icon/text while no records exist; make each an intrinsic compact section.
2. Width is assigned by available pixels rather than information; use bounded controls, real table columns and aligned setting rows.
3. Nearly every text label is visually loud and surfaces are uniformly boxed; introduce a 12/13/14/20 type hierarchy and one work-surface boundary.

Verification uses Flutter renders at 390/768/1440 widths and both themes; a web DOM inspector cannot measure native Flutter widgets. Do not claim browser inspector success.
