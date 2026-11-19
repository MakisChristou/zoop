# Motion data on the WHOOP 5.0 / MG

What the strap offers for movement, what the official app uses, and what zoop uses.

## Three sources

| Source | Rate | Content | Sent by default |
|---|---|---|---|
| R18 biometric summary | 1 Hz | dynamic acceleration magnitude (g), gravity vector (g), activity class, the strap's own wake/still/sleep/up flag | yes |
| R21 six-axis IMU | 100 Hz, one record per second | raw accelerometer and gyroscope samples | **no** |
| IMU stream types 51/52 | configurable | dedicated streaming variant | no |

R21 layout (1,244 bytes): accelerometer x/y/z as `i16` columns at offsets 28, 228 and
428 with the valid count at 24; gyroscope columns at 640, 840 and 1040 with the count at
630; each column reserves 100 samples. Conventional scales are 1/4096 g and
2000/32768 °/s. The layout is well established across the public projects; recording it
requires a separate collection switch on the strap, whose persistence and battery cost are
not characterised.

## What the official app uses

Captures of the official app syncing show it uploading R18, R20 and R26 record bodies and
computing nothing on the phone. It never enables R21. WHOOP's cloud therefore scores sleep
from the one-second summary plus optical bursts, not from raw inertial data.

## What zoop uses

R18 only, which is what the official pipeline sees. On a first full night the per-second
dynamic acceleration separates the strap's states cleanly (asleep median 0.006 g, 95th
percentile 0.010 g; awake median 0.027 g, 95th percentile 0.32 g; 3 % of asleep seconds
above 0.02 g versus 57 % of awake seconds). That is an actigraphy signal at one hertz,
which the Cole-Kripke and Sadeh scorers consume, and the gravity vector supports the van
Hees posture-angle method.

Decision: sleep staging is built on R18 motion, gravity, heart rate, HRV and breathing.
R21 stays undecoded and unrequested unless a specific experiment needs raw inertial data,
and then only as an opt-in with the strap's collection state restored afterwards.
