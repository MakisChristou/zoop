---
name: zoop-interface
description: Design and review Zoop web screens, charts, cards, loading states, and responsive layouts using its approved Marc Lou health-dashboard reference. Use for any visual or interaction change in zoop-web; preserve existing health features and account privacy.
---

# Zoop interface

Use https://marclou.com/health as the visual reference. Reproduce its restrained hierarchy and chart language with Zoop's own components, branding, and recorded data. Do not copy personal content or photographs.

## Visual contract

- Geist. Compact 14px medium card headings, 14px body, 11px chart axes. Use tabular numerals. Values lead; supporting labels recede.
- Near-black page `#0a0a0a`, charcoal panels `#171717`, text `#fafafa`, muted `#a1a1a1`. Sleep `#8194dc`, activity `#479eea`, weight neutral. Reuse existing CSS tokens.
- Cards: 18px radius, subtle border, 20px padding. No glow, gradients, oversized headings or ornamental badges.
- Bound the page to 1100px and center it. Wide monitors add outside space, not oversized cards. Two columns when they fit; one on narrow screens.
- Paired chart cards share heading, plot and bottom edges. Put headline values in a consistent header slot. Never add filler copy to equalize heights.
- Keep the selected date centered above the summary rings, including when navigation controls change.

## Charts and training

- Quiet dashed horizontal grid, roughly three Y ticks, 2px lines, restrained labels. No dots on every point. Show isolated observations and a selected point clearly.
- Tooltips show date then labeled value. No empty labels, leading colon, repeated units or duplicate dates elsewhere in the card.
- No visible “Readings” disclosures. Preserve keyboard selection and screen-reader data tables. Hover must not be the only way to inspect data.
- Missing data is not zero. Do not bridge gaps or invent recovery percentages. Target lines represent actual configured goals.
- Activity: group dates once, a fine vertical timeline, white outlined sport icons, muted duration/heart rate, compact blue load bars with values.
- Sport bars use actual durations and counts. Heatmaps distinguish missing data from recorded low load, support keyboard/touch inspection, and initially reveal recent history on narrow screens.

## Waiting and errors

- Every user-visible async operation needs feedback: a small inline spinner for an action; a thin bar for page/data loading; a skeleton only before any data exists.
- Use measured progress only when numerator and denominator are real. Completed dataset counts are not time estimates. Otherwise use an indeterminate bar.
- Keep successful data visible during same-source refresh and on refresh failure. Clear it immediately when changing accounts/devices. Cancelled or superseded requests must not update the new view or hide its indicator.
- Never flash empty states or zeros while still loading. Errors offer a concise retry. Reduced motion keeps a static loading cue.

## Copy and verification

One fact, one place. No welcome essays, explanation walls, redundant subtitles or instructions for obvious gestures. Put essential methodology behind a short, optional detail view.

Before shipping:

1. Capture rendered screens using representative data and compare against the reference, not memory.
2. Check 320px, tablet, desktop and 2560px widths; 200% zoom; keyboard; touch; reduced motion; RTL overflow. Check paired plot/card edges with actual bounds.
3. Exercise first load, cached refresh, partial failure, total failure, empty data and source changes. Verify no accidental health writes.
4. Run the repository's unit, build, browser and Nix checks. Keep screenshots and private data out of Git. Report what was verified and what was not.

This skill does not authorize production deployment; follow the user's current authorization.
