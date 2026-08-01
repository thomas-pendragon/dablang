# Dab public-site design QA

## Evidence

- Source visual truth: `design-evidence/public-site/reference.webp`
- Desktop implementation: `design-evidence/public-site/implementation-desktop.webp`
- Normalized full-view comparison: `design-evidence/public-site/comparison.webp`
- Mobile home implementation: `design-evidence/public-site/implementation-mobile-home.webp`
- Mobile document implementation: `design-evidence/public-site/implementation-mobile-building.webp`
- Desktop viewport: 1440 by 1200 CSS pixels at device scale factor 1.
- Mobile viewport: 390 by 844 CSS pixels at device scale factor 1, forced through Chrome DevTools emulation and verified with `innerWidth`, `innerHeight`, `devicePixelRatio`, and document scroll-width readback.
- Source pixels: 1374 by 1145. The source was uniformly normalized to 1440 by 1200 for the desktop comparison; its aspect ratio was unchanged.
- State: anonymous visitor, light presentation, homepage and representative long-form Building page.

## Full-view comparison

The normalized side-by-side comparison shows the same defining composition as
the selected visual: a narrow project rail, a ruled primary navigation row, an
oversized horizontally extended display title, a high-contrast serif
description, two large underlined calls to action, and a three-part author and
project footer. Owner review refined that footer into a smaller two-part author
module: a compact signature followed by a short biography with GitHub and
Twitter links. The implementation deliberately retains the repository's real
CI badge, public navigation contract, and existing project destinations.

The implementation omits the mock's dotted field and red ornamental marks.
They were non-functional decoration with no source assets, and replacing them
with CSS drawings or improvised glyphs would violate the asset-fidelity rule.
The omission is acceptable P3 drift; the typography and editorial hierarchy
remain the selected direction's primary identity.

The mock's display word `Design` identified the visual direction rather than
the product. The shipped hero therefore uses the language name `Dab` while
preserving the selected scale, weight, crop, and editorial composition.

No focused crop was required: the 2880 by 1200 combined comparison keeps the
display title, body typography, navigation labels, rules, footer signature,
social marks, and CTA treatment legible at the same time.

## Required fidelity surfaces

- Fonts and typography: the implementation preserves the mock's wide heavy
  grotesque display hierarchy, compact blue utility type, and contrasting
  editorial serif copy. System font stacks avoid a new network dependency.
  Heading scale, line height, tracking, wrapping, and desktop crop were checked
  visually at the target viewport and separately on mobile.
- Spacing and layout rhythm: rail width, main-column origin, navigation rule,
  hero-to-copy gap, CTA row, and footer boundary align closely with the source.
  The mobile layout removes the rail, retains all primary links, and uses a
  single readable column without horizontal overflow.
- Colors and visual tokens: warm paper, near-black ink, saturated cobalt links,
  neutral rules, and a red focus/error accent match the selected palette while
  maintaining readable contrast.
- Image quality and asset fidelity: no required imagery was approximated. The
  existing GitHub and Twitter icons and live CI badge remain legitimate source
  assets. Non-essential decorative art without source assets was omitted.
- Copy and content: existing public product copy and destinations were
  preserved. This release does not pre-empt the separately planned 0.0.17
  README and homepage content overhaul.

## Comparison history

1. Initial desktop comparison found a P2 proportion mismatch: the project rail
   was too wide, the display word was too narrow, the body copy wrapped into too
   many lines, and the footer fell below the target viewport. The grid track,
   display scale, copy measure, vertical gaps, and viewport row were corrected.
2. The first representative mobile document capture found a P2 overflow issue:
   long inline code and highlighted blocks widened the Building page. Explicit
   mobile content bounds, inline-code wrapping, and scroll-contained code blocks
   were added. Final DevTools readback reports a 390-pixel viewport and
   390-pixel document width.
3. Owner review identified `Design` as ideation placeholder copy. The hero and
   document title now use `Dab`, and the desktop and mobile evidence was
   recaptured against the LAN-served implementation.
4. Owner review identified the footer signature as oversized and the standalone
   profile list as under-informative. The signature is now subordinate to the
   page, and a concise author biography and both profile links form one compact,
   responsive block.
5. Owner review found that Minima's inherited inline-code background remained on
   code nested inside dark highlighted blocks, rendering each line as a pale,
   low-contrast strip. Nested code now explicitly inherits the block foreground
   and uses a transparent background; the Building page was rechecked at desktop
   and mobile widths.
6. The post-fix desktop comparison and 390 by 844 home/document captures show no
   remaining actionable P0, P1, or P2 mismatch.

## Findings

- P3: the source's dotted and red ornamental marks are omitted because no real
  source assets exist. This does not affect hierarchy, navigation, or product
  comprehension and avoids an inauthentic code-drawn substitute.

## Interaction and accessibility checks

- The disposable public-site validator built all 39 classified pages and
  verified every local link and explicit navigation target.
- Direct browser renders covered the homepage and Building destination at the
  desktop and mobile breakpoints.
- Semantic header, navigation, aside, main, article, and footer landmarks are
  present; the skip link, visible keyboard focus, reduced-motion rule, and
  responsive content bounds are contract-tested.
- The public shell ships no client-side application JavaScript; browser renders
  produced no application console errors.

## Final result

final result: passed
