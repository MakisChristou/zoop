# Health dashboard visual language

Reference: https://marclou.com/health, measured in a 390-point mobile viewport on
19 November 2026. This is a presentation reference, not a source of health data
or analytics methods.

| Element | Reference and Zoop dark appearance |
| --- | --- |
| Typeface | Geist Regular, Medium and SemiBold; bundled under SIL OFL 1.1 |
| Panel titles / values | 14 points; medium title, regular supporting value |
| Chart axes | 11 points, muted |
| Background / panels | `#0A0A0A` / `#171717` |
| Text / secondary | `#FAFAFA` / `#A1A1A1` |
| Sleep | `#8194DC` |
| Activity / steps | `#479EEA` |
| HR, HRV, weight | `#FAFAFA` |
| Positive / middle / negative | `#47CF79` / `#FCC447` / `#F75C61` |
| Panels | 18-point radius, 20-point horizontal padding |
| Standard chart | Approximately 144-point plot plus axis labels |
| Axes / lines | Left Y axis, sparse date labels, horizontal dashed grid, round 2-point lines |
| Markers | Latest/selected halo; preserve isolated recordings and sparse cut points |
| Sleep stages | One stacked strip, two-column breakdown, purple at 100/60/25% opacity |

Use `ZoopType`, `ZoopStyle` and the shared chart axis helper. Font faces must load
from the application bundle; a simulator unit test detects accidental fallback.
Relative font sizes and accessible navigation remain available at large text sizes.
The dense heatmap uses separate 28-point targets with full VoiceOver date/value
labels; ordinary buttons retain 44-point targets.

Current calendar charts stop at the current time so they do not reserve blank
space for future readings. Completed periods retain their whole calendar window.
The calendar pager, source readings and selected date do not change. Three explicit
axis ticks keep the primary trend charts stable. Missing segments remain gaps, and
an isolated reading remains visible.

The website uses rolling averages for some charts. Zoop keeps its existing optional
comparison controls, and weight continues to show raw weigh-ins by default. Never
invent or smooth data just to reproduce the shape of a reference screenshot.
ECG remains an uncalibrated recorded waveform; styling must not imply a calibrated
voltage/time grid or a diagnostic result.

## Visual verification

Compare actual website and simulator screenshots at the same logical width. Check
font family, label size, panel bounds, plot height, axis side, line thickness, markers,
background and series colors separately from the plotted data. Do not use whole-image
pixel similarity as proof when the datasets and platform text rendering differ.

Capture Today, Activity, Sleep, Trends, Weight, Goals and their chart details; exercise
paging, inspection, return navigation and heatmap drill-down. Also check a small
phone and accessibility text. Simulator previews use generated local fixtures, never
personal health data. Physical installation requires the user's approval.
