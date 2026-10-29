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
- Routes contain explicit WGS84 coordinates. The application never silently converts BD09/GCJ02 or claims illustrative points are a road-planned route.
- All traffic and credentials remain local unless the operator connects, enables online map tiles or explicitly exports data. Workspace exports include authentication codes.
- Voice: concise technical Chinese, with a complete English translation; show units and hexadecimal values accurately.
- Visual purpose: a restrained operations interface for extended debugging sessions. Device state and actual protocol messages matter more than decorative charts.

## Scope boundaries

JT/T 808-2019, JT/T 1078 audio/video, encrypted/segmented messages, automatic road planning, probabilistic route perturbation and a certified high-concurrency load test are not implemented. Positive acknowledgements are issued only for supported commands and valid bodies. See the supported-message table in the README.
