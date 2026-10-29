# Navigation artwork

These are the original full-color SVG exports from Microsoft's Fluent UI System Icons, not tinted Material glyphs or locally redrawn approximations. Their gradient fills and multi-part artwork are preserved; no `ColorFilter`, `currentColor` replacement or per-theme recoloring is applied.

- Upstream: https://github.com/microsoft/fluentui-system-icons
- Official color catalog: https://github.com/microsoft/fluentui-system-icons/blob/main/icons_color.md
- Downloaded package: `@fluentui/svg-icons@1.1.344`
- Package tarball: https://registry.npmjs.org/@fluentui/svg-icons/-/svg-icons-1.1.344.tgz
- License: MIT; copyright Microsoft Corporation. The complete upstream notice is bundled in `LICENSE`.
- Retrieved: 2026-10-27.

| Destination | Upstream file in `icons/` |
| --- | --- |
| Console | `board_24_color.svg` |
| Terminals | `phone_laptop_24_color.svg` |
| Routes & tasks | `location_ripple_24_color.svg` |
| Protocol logs | `code_block_24_color.svg` |
| Settings & help | `arrow_clockwise_dashes_settings_24_color.svg` |

The files are local app assets, so navigation does not depend on a network connection. `flutter_svg`, already used by this project, renders the source artwork at a fixed 20px sidebar/rail size and 22px bottom-navigation size. Labels remain available for accessibility; the SVGs are decorative.
