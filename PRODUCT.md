# JT808 Simulator

## Product truth

A local Flutter developer tool for simulating JT/T 808-2013 vehicle terminals against a server explicitly configured by the operator. It is not a fleet-tracking service and does not require an application account.

- Audience: vehicle-platform developers and protocol integration testers.
- Core workflow: configure terminal → connect/register/authenticate → inspect locations and messages → run a saved coordinate route → reproduce an alarm or platform command.
- Platforms generated for this workspace: macOS, Android and iOS. Native TCP sockets are required. Browser TCP is outside this implementation.
- Source of functional evidence: the sibling `jtt808-simulator` Java application. Its implemented workflows are references; its unfinished authentication, decoder defects and planned features are not compatibility requirements.
- Protocol evidence: SmallChi/JT808 code and independently published hexadecimal fixtures; EMQX's JT808 documentation. See `docs/REFERENCES.md`.
- First run has no terminals, routes, tasks, connections or fictitious traffic. Defaults inside an unsaved form are illustrative configuration, not discovered devices.
- The operator explicitly initiates connections. Restart never resumes network sessions or tasks. Automatic reconnection is opt-in.
- Routes are stored as explicit WGS84 coordinates. CSV imports must declare WGS84. The visual editor converts selected display coordinates and Amap GCJ-02 responses to WGS84 at the map/API boundary; playback, exports and protocol reports always use WGS84. OSRM and Amap driving directions are available only on explicit request. Imported example polylines are never claimed to be road-planned routes. See `docs/ROUTE_PLANNING.md`.
- Online basemaps remain enabled by default, with Tianditu's official HTTPS base/Chinese-label layers selected for mainland China. A user-supplied Key is required; without it no tiles are requested and setup guidance is shown. Amap is the default routing provider, also requiring a user Key and explicit authorization confirmation. No overseas public endpoint is populated by default. Existing explicit source selections and URLs are retained, not overwritten. Map failures retain offline WGS84 coordinates. Amap/Baidu tile adapters still require authorized operator-provided endpoints; no unofficial internal URLs are bundled. See `docs/CHINA_ACCESS.md` and `docs/BASEMAPS.md`.
- Terminal traffic and credentials remain local unless the operator connects or explicitly exports data. Workspace exports include authentication codes, Tianditu and routing Keys, and tokens in saved basemap URLs; local storage is not additionally encrypted. Explicit route planning sends selected stops to the chosen service, never terminal phone numbers or plates. Amap planning stays unavailable until the operator confirms permission for third-party display, conversion, storage/export and simulated playback.
- Map sources retain separate optional Tianditu/Amap/Baidu credentials; Amap basemap and driving Keys are distinct. OSM and OSRM use explicit custom connection URLs without Key fields. Missing addresses or credentials required by a template are saved as setup states, not silently replaced with public services. Legacy explicit OSM selections without an address field retain their former endpoint. See `docs/CHINA_ACCESS.md`.
- Explicit keyless presets are available for Esri World Imagery, the public OSRM demo and FOSSGIS OSRM driving. The unreachable standard OSM tile shortcut was replaced by imagery verified as real Beijing tiles at zooms 12/14/16/19; manual OSM URLs remain supported. Imagery uses WGS84/Web Mercator, vendor source credit, no Chinese road labels, and Esri service terms (no bulk offline export). Presets populate editable drafts; applying is required, with no automatic fallback or overwriting Keys. Public routing has a shared one-second interval and one in-flight request. OSRM output includes visible OSM data/license and map-error links. See `docs/KEYLESS_SERVICES.md`.
- Voice: concise technical Chinese, with a complete English translation; show units and hexadecimal values accurately.
- Visual purpose: a restrained operations interface for extended debugging sessions. Device state and actual protocol messages matter more than decorative charts.

## Scope boundaries

JT/T 808-2019, JT/T 1078 audio/video, encrypted/segmented messages, live turn-by-turn navigation, probabilistic route perturbation and a certified high-concurrency load test are not implemented. Positive acknowledgements are issued only for supported commands and valid bodies. See the supported-message table in the README.
