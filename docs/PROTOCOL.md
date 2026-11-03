# WHOOP 5.0 / MG protocol notes

What `snoop-proto` implements and why. Everything here was learned from public
interoperability research and is re-verified against our own hardware as captures
become available. Offsets are absolute frame offsets.

## GATT

Service `fd4b0001-cce1-4033-93ce-002d5875f58a`:

| Characteristic | Role |
|---|---|
| `fd4b0002` | command write |
| `fd4b0003` | notify: command responses |
| `fd4b0004` | notify: events |
| `fd4b0005` | notify: data records |
| `fd4b0007` | notify: diagnostics |

The notify characteristics require an authenticated bond. The standard Heart Rate
Measurement characteristic (`0x2A37`) streams without one. The strap holds a single
bond; on iOS an app inherits the bond the official app created, so only one app can be
connected at a time. macOS cannot initiate the required pairing.

Device Information Service: model string `MG` or serial prefix `5AM` indicates an MG;
serial prefix `5AG` a 5.0. Absence of a prefix proves nothing.

## Format-1 envelope

```
[0]  AA        start
[1]  01        format
[2]  u16 LE    declared length = frame length - 8
[4]  u8        destination (requests 00, strap replies 01)
[5]  u8        source      (requests 01, strap replies 00)
[6]  u16 LE    CRC-16/MODBUS over [0, 6)
[8]  …         inner packet, zero-padded to a multiple of 4
[-4] u32 LE    CRC-32 (zlib) over the inner packet
```

Inner packet: `[type][seq][…]`. Packet types: 35 command, 36 command response, 40
realtime HR, 43 realtime raw record, 47 historical record, 48 event, 49 metadata, 50
console log, 51/52 IMU streams.

## Commands

`[35][seq][command][args…]`. The first argument byte is part of the contract and
differs per command; a wrong value is ignored without any error.

| Command | Code | First arg |
|---|---|---|
| GET_HELLO | 145 | 0x01 |
| GET_ADVERTISING_NAME | 141 | 0x01 |
| GET_DATA_RANGE | 34 | 0x00 |
| SEND_HISTORICAL_DATA | 22 | 0x00 |
| HISTORICAL_DATA_RESULT | 23 | 0x01 followed by the 8-byte HISTORY_END token |
| ABORT_HISTORICAL_TRANSMITS | 20 | — |
| GET_BATTERY_LEVEL | 26 | — |
| TOGGLE_REALTIME_HR | 3 | — |

Connection sequence: subscribe to the four notify characteristics, write GET_HELLO
(`CLIENT_HELLO`, byte-exact), then GET_ADVERTISING_NAME.

## History offload

Observed official-app cadence: every ~10 minutes, SEND_HISTORICAL_DATA →
GET_DATA_RANGE → SEND_HISTORICAL_DATA → one HISTORICAL_DATA_RESULT per chunk →
ABORT_HISTORICAL_TRANSMITS.

Chunks are delimited by metadata frames (type 49): `[10]` kind (1 start, 2 end, 3
complete), `[11]` u32 unix, `[15]` u16 subsec. A HISTORY_END carries an 8-byte token at
`[21, 29)`; the phone must echo it verbatim as the HISTORICAL_DATA_RESULT argument or the
strap stops after the first chunk.

GET_DATA_RANGE reply body (65 bytes from frame offset 13) gives ring-buffer pages:
write, trim and total pages; `pages_behind = write >= trim ? write - trim : total - trim
+ write`. Clock fields use 0 and 0xFFFFFFFF as sentinels.

## Records

Header (types 43/47): `[9]` layout, `[10]` marker, `[11]` u32 record index, `[15]` u32
unix seconds, `[19]` u16 subsec. Layouts have fixed frame lengths; a mismatch means the
bytes are not that layout.

### R18 biometric summary, 124 bytes, 1 Hz

| Offset | Type | Field |
|---|---|---|
| 22 | u8 | heart rate, bpm |
| 23 | u8 | R-R count (≤ 4) |
| 24 | u16 × 4 | R-R intervals, **milliseconds**; 0 = placeholder |
| 36 | u8 | HR flags |
| 37 | u8 | alternate HR |
| 41 | f32 | dynamic acceleration, g |
| 45 | f32 × 3 | gravity vector, g |
| 57 | u16 | step counter |
| 59 | u16 | cadence (raw) |
| 61 | u16 | hardware step counter |
| 63 | u8 | activity: 0 still, 1 walk, 2 run |
| 69, 71 | i16 | auxiliary temperatures, 0.1 °C |
| 73 | u16 | skin temperature, 0.01 °C |
| 75 | u16 × 3 | status words |
| 81 | u8 | state bits; `(bits >> 4) & 3`: 0 wake, 1 still, 2 sleep, 3 up |
| 82 | u8 | SpO₂: 70–100 = percent, otherwise a status code |

The band state is the strap's own rest/motion classification, which is why it matters
for sleep: it is WHOOP's on-device judgement, available before any cloud processing.
SpO₂ is measured in 30-second windows every 20 minutes during sleep; byte 82 is 0
outside them.

### R16 / R17 MG ECG

`[21]` quality, `[22]` state bits, `[23]` classifier result, `[24]` classifier state,
`[25]` progress, `[32]` u16 sample count, `[34]` samples. R17 (240 bytes) holds up to 100
i16 samples. R16 (1584 bytes) holds up to 500 18-bit two's-complement samples packed in
3 bytes (`((b0 & 3) << 16) | (b1 << 8) | b2`), with flag bits in `b0`. Physical scale
and sample rate are not yet established.


#### Manual ECG capture contract (experimental)

The iOS manual recorder follows the revision-1 interface described in the
[public ECG protocol research](https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL_ECG.md).
A hardware smoke check confirmed command acknowledgements, nonempty live samples,
local recording storage and successful stop/cleanup. Sample calibration and diagnostic
equivalence remain unvalidated. All payloads below follow the command code and include
the revision byte:

| Code | Purpose | Payload |
|---|---|---|
| 123 | Wrist | `01 01` right, `01 02` left |
| 124 | ECG generation | `01 02` start, `01 01` stop |
| 125 | Save raw history | `01 01` on, `01 00` off |
| 126 | Raw live output | `01 01` on, `01 00` off |
| 127 | Save filtered history | `01 01` on, `01 00` off |
| 139 | Filtered live output | `01 01` on, `01 00` off |

Select and acknowledge the wrist, enable explicit live gates, then request generation.
Match replies by command and origin sequence. Success acknowledges handling; it does
not prove that initialization succeeded or samples exist. Never automatically repeat
start: repeated starts can lose ownership of accompanying optical/IMU collection.
Do not change `enable_raw_data_w_ecg` as an authorization workaround. Stop generation
and disable only gates attempted by the recorder, including after cancellation,
disconnect or app restart. Persist cleanup intent before each mutating request.

Only CRC-valid type-43 R16/R17 records belong to a live session. Type-47 history may
arrive concurrently and must not advance the live recording timer. The ECG timestamp
words are retained without assuming Unix units; use phone receipt time for the capture
window. Deduplicate exact frames, not shared sequence/timestamp pairs across layouts.

R17 samples occupy `[34,234)`; `[234,236)` is alignment. Reject counts above 100.
R16 has 500 fixed waveform slots, then a diagnostic count at 1534, 11 I halfwords at
1535, 11 Q halfwords at 1557, and alignment at 1579. Reject counts above capacity.
Keep both flag bits 6 and 7 and reserved bits 2–5 separately from signed 18-bit samples.
Preserve packed status bytes `[21,34)`, including unknown quality/classifier codes.
Presence is bit 3 of byte 22; it is not a validated contact-quality or diagnostic label.

The first app slice retains complete frames in its normal upload queue and stores a
local recording manifest with exact frames and receipt times. A 30-second capture
window is a product duration, not an inferred firmware completion or sampling rate.
Show native sample counts and uncalibrated waveform amplitude; do not invent mV,
sample frequency, average ECG heart rate, AFib or normal-rhythm results. Missing data,
rejected commands and cleanup failures remain distinct from a saved recording.

### Not yet decoded

R20 optical blocks (2140 bytes), R21 six-axis IMU (1244 bytes), R22 high-rate channels,
R26 compact optical (88 bytes). They are stored raw and will be decoded when the sleep
work needs them (R21 motion is the likely first).

## Other packets

- **Realtime HR (40)**: `[10]` u32 unix, `[14]` u16 aux time, `[16]` u8 HR, `[17]` u8
  R-R count, `[18]` u16 R-R ms ….
- **Event (48)**: `[10]` u8 code, `[12]` u32 unix, `[16]` u16 subsec, `[18]` u16
  payload length, `[20]` payload. Code 3 BATTERY_LEVEL: `[0]` revision, `[1]` u16 state
  of charge in tenths of a percent, `[5]` u16 millivolts.
  Codes 7 / 8 are CHARGING_ON / CHARGING_OFF, with no payload required;
  observed in MG captures. These describe strap charging, not battery pack level.
  Apply timestamps monotonically: history can replay old transitions.
  The seven-byte WHOOP 5 battery payload has no verified charging flag.
- **Command response (36)**: `[9]` seq, `[10]` command, `[11]` origin seq, `[12]`
  result (0 failure, 1 success, 2 pending, 3 unsupported), `[13]` body.
  GET_BATTERY_LEVEL (26), WHOOP 5/MG: request has no arguments; a successful
  reply body begins with a little-endian u32 whole percent (0–100). Reject
  non-success results and out-of-range values. The reply does not identify
  whether a charger is attached; use charging events for that state.

### WHOOP 5/MG battery pack

The pack and strap are separate gauges. Live channel-4 event **109** carries
28 payload bytes: presence (0/1) at payload 0, six identifier bytes at 1,
16 identity-text bytes at 7, little-endian u16 charge at 23, and three opaque
bytes at 25. Own MG captures on 2026-10-30 contain 20 live records, with
raw charge declining 557 to 5, then 918 to 543 after a later attachment.
The display uses tenths of a percent (55.7 to 0.5, 91.8 to 54.3), consistent
with the independently documented capture interpretation; calibration against
an external meter has not been performed. Reject values above 1000 and
unknown presence flags. Do not print identity bytes in diagnostics.

Events **21/22** report attachment/removal separately from charging **7/8**.
Presence never establishes current flow. History channel 5 replays these
records: it may update last-known display data, never live state or alerts.
A new live record expires after 15 minutes; disconnect/removal clears live
eligibility. Equal/older timestamps cannot revive removed or stale state.

Command **151**, GET_BATTERY_PACK_INFO, takes revision byte 1. A successful
28-byte response body has revision at 0 and the same record beginning at 1
(charge at 24, with two opaque trailing bytes). It returns cached information;
success and request receipt time do not establish measurement freshness. Use
it only as a last-known display fallback, correlated by origin sequence and
connection, and stop querying for the session on failure/unsupported. The
live event remains authoritative. References (protocol only, no code copied):
https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL_TRANSPORT.md#battery-pack--command-151
https://github.com/ryanbr/noop/blob/main/Packages/WhoopProtocol/Sources/WhoopProtocol/BatteryPackInfo.swift

Event timestamps retain their u16 fractional ticks at frame 16, scaled by
1/32768 second. Own MG live pack events included raw charge 999 and 1000
within the same whole second, with distinct fractions. Ordering by whole
seconds alone loses valid changes; reject older full timestamps, not every
update in the same second. Pack charging inference requires two rising updates
and at least two percentage points of increase; one rebound is not charging.
