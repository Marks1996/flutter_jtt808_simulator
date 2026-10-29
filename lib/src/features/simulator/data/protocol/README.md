# JT/T 808-2013 protocol and TCP client

This directory is pure Dart (`dart:io` plus `gbk_codec`); it has no Flutter,
provider, persistence or UI dependency. It deliberately implements only the
unencrypted, unsegmented JT/T 808-2013 header/body formats.

## Public API

- `Jt808Codec().encode(Jt808Frame(...))` returns escaped wire bytes, including
  both `0x7E` delimiters and the header-plus-body XOR checksum.
- `Jt808Codec().decode(bytes)` validates one complete frame and returns immutable
  `Jt808Frame(messageId, phone, sequence, body)` fields. `phone` is 12 decimal
  digits, and the sequence is an unsigned 16-bit integer.
- `Jt808Codec.parseHex` accepts hexadecimal pairs with optional whitespace;
  `Jt808Codec.toHex` produces uppercase, space-separated bytes.
- `Jt808PacketFramer.add` handles arbitrary TCP splits/coalescing and shared
  delimiters. Its retained frame buffer is bounded to 2074 bytes by default.
- `Jt808MessageBodies` exposes strict GBK, registration, authentication, location
  and general-response body helpers. Location encoding can omit mileage.
- `Jt808Client({required TerminalConfig config, LocationFix initialLocation =
  const LocationFix()})` exposes `config`, `phase`, `events`, `connect`,
  `disconnect`, `sendLocation`, `heartbeat`, `sendRaw`, `updateLocation` and
  `dispose`. Optional `connectTimeout`, `responseTimeout`, `reconnectDelay` and
  `initialSequence` arguments make local integration testing deterministic.

`connect` waits for the TCP connection and first write, **not** successful
registration/authentication. A saved authentication code sends `0x0102`
directly. Otherwise a matching successful `0x8100` saves/emits the code and
starts authentication. Only a matching successful `0x8001` for the `0x0102`
request makes the terminal online. The client never acknowledges `0x8001`.

Online clients own both the heartbeat timer (30 seconds by default) and periodic
location timer, including parameter `0x0029` and temporary tracking `0x8202`.
Consumers can provide the optional synchronous `LocationFix Function()?
locationProvider` constructor argument to advance a route using real elapsed
time. The client calls it immediately before each normal/temporary automatic
report and `0x8201` query reply, then validates/stores the result through
`updateLocation`. A throwing callback or invalid fix is logged; reporting uses
the last valid fix and the connection remains online. The callback is not called
during connection or explicit `sendLocation(fix)` calls.

Without a callback, consumers should update route/current-position state with
`updateLocation` rather than create another automatic sending timer.
`sendLocation` also updates that state and immediately reports while online.
`updateLocation` works while disconnected so later `0x8201` queries use the
latest position. Calls to `heartbeat` coalesce while awaiting an outstanding
heartbeat acknowledgement.

All socket failures, refusals, handshake/heartbeat timeouts, platform rejections
and remote closes become `ConnectionChanged` / `LogEmitted` events; the events
stream does not deliver socket errors. Invalid caller input throws
`FormatException`, and invalid lifecycle operations throw `StateError`.
`sendRaw` requires one fully validated, same-terminal 2013 packet while online;
it retains the packet's provided sequence. Sent logs are emitted after a
successful socket flush, not when a send is merely requested. Wire logs contain
`config.id`, direction, message ID, sequence and complete hexadecimal bytes.
Unsupported/malformed received frames are logged as errors and discarded.

Manual disconnect cancels pending connection tasks, timers, tracking, TCP
subscriptions and reconnects. Reconnection is attempted only for
`autoReconnect: true`; disposal permanently closes the events stream.

## Implemented downlink messages

| Message | Behavior |
| --- | --- |
| `0x8201` | `0x0201` containing platform request sequence and current location |
| `0x8103` | Atomic parse/validate/store, then `0x0001`; only DWORD parameters `0x0001` (heartbeat seconds) and `0x0029` (default location seconds), both in `1..3600` |
| `0x8104` / `0x8106` | `0x0104` with only supported stored parameters; unsupported queried IDs are omitted and logged |
| `0x8300` | GBK text logged/displayable through events, then `0x0001` |
| `0x8202` | Temporary interval overrides normal reporting until duration expiry; interval zero stops temporary tracking (two-byte or six-byte stop forms) |
| Other downlink IDs | `0x0001` result `3` (unsupported) |

A parameter-setting packet containing an unknown ID is rejected **as a whole**
with result `3`; malformed or out-of-range data returns result `2`. No partial
changes are applied. Temporary tracking requires a positive duration at least
as long as its positive interval and always restores the configured interval
on expiry. Commands received before authentication return failure.

Location reports include the 28-byte base plus optional `0x01` mileage. They use
absolute millionths of degrees, south/west status bits 2/3, 0.1 km/h speed,
0.1 km mileage and BCD time calculated in UTC+8 independent of the machine's
local time zone. The two-digit time format is limited to years 2000..2099.
GBK encoding rejects characters that cannot round-trip losslessly; invalid GBK
bytes are not silently replaced. `0x8300` is logged, not spoken by a TTS engine.

2019, encryption, segmentation/reassembly, other terminal parameters, firmware,
multimedia, geofences and proprietary extensions are intentionally unsupported.
The protocol cannot distinguish 2011 from 2013 from an unversioned header
alone; all emitted bodies use the documented 2013 layouts.

## Verified references

- Local Java simulator: `jtt808-simulator` `JTT808Encoder` and
  `SimpleDriveTask` (registration widths, framing, text handling and location).
  Its decoder and heartbeat implementation are incomplete; they are not used
  as evidence of support.
- [SmallChi `0x0100`](https://github.com/SmallChi/JT808/blob/master/src/JT808.Protocol/MessageBody/JT808_0x0100.cs)
  explicitly uses 5 / 20 / 7-byte identity fields in its 2013 serializer.
- [SmallChi README](https://github.com/SmallChi/JT808#举个栗子-1) provides the
  independent byte-exact `0x0200` fixture, including escaped sequence and oil.
- SmallChi `0x8103_0x0001`, `0x8103_0x0029`, `0x8202`, `0x8106` and `0x8300`
  confirm parameter units and command body layouts.
- [`gbk_codec` documentation](https://pub.dev/packages/gbk_codec) and installed
  `src/converter_gbk_byte.dart` confirm `gbk_bytes.encode` / `.decode` are the
  byte-stream API. The similarly named `gbk` codec uses 16-bit code values.

`test/protocol` contains independent hex fixtures, strict malformed-frame tests,
every-offset TCP split tests and real `ServerSocket` loopback integration tests.
The tests never connect to a real external terminal/platform. GBK fixtures are
kept in the same test suite as TCP cases: this Flutter VM exhibited a
`Map._fromLiteral` type error when separate test isolates initialized
`gbk_codec`'s large generated maps concurrently under randomized order. Normal
and randomized tests still run every assertion; no test is skipped. The client
itself uses the codec synchronously within its owning isolate.
