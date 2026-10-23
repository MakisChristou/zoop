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
- **Command response (36)**: `[9]` seq, `[10]` command, `[11]` origin seq, `[12]`
  result (0 failure, 1 success, 2 pending, 3 unsupported), `[13]` body.
