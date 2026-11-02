# Reclaim brand

<p align="center">
  <img src="brand/brand-sheet.png" width="800" alt="Reclaim's brand sheet: the boomerang app icon, the wordmark and tagline, the six-colour palette, the menu bar glyph and the mark">
</p>

## The idea

**Get your disk space back.**

When you delete a file on a Mac it isn't gone: it sits in a Trash folder on the same drive, still taking up room. Reclaim is how that space comes back to you. So the mark is a **boomerang**, the one thing you throw away that's meant to return.

The app icon shows it mid-flight on a night sky, with a dotted trail swinging round from its trailing tip and back to its leading one. The dots grow and brighten on the way home, so the eye reads the direction of travel.

## Mark

- One shape everywhere: the app icon, the menu bar, the badge at the top of the panel, the progress spinner and the "Reclaimed" message all draw [`BrandGeometry.boomerang`](../Sources/ReclaimUI/Brand/BrandGeometry.swift). `make icon` compiles that same file into the icon script, so the icon can't drift from the app.
- The silhouette is a union of discs along one smooth cubic curve, widest at the elbow and tapering to round tips. It reads at 16 px.
- In the menu bar it's a template image, so macOS tints it for light, dark and highlighted menu bars like a system glyph.
- Don't outline it, rotate it, stretch it or put it on a busy background. Give it clear space of at least a quarter of its width.

## Colour

| Name | Hex | Use |
| --- | --- | --- |
| Night | `#0A1030` | Bottom of the icon background |
| Dusk | `#2D4290` | Top of the icon background |
| Ember | `#FF8F24` | The boomerang. The same family as the In Trash segment: orange always means space you can get back |
| Glow | `#FFC46B` | Highlight end of the Ember gradient, and the icon's rim light |
| Deep Ember | `#EC530A` | Shadow end of the Ember gradient |
| Trail | `#A9C4FF` | The flight-path dots |

**Text in Ember.** Plain orange on a light popover fails contrast. The reclaimable amount in the panel header uses `Brand.emberText`: `#C2410C` in light mode (about 5:1 on white) and `#FFA94D` in dark mode.

**Storage segments stay system colours.** Used, Purgeable, In Trash and Free keep `systemBlue`, `systemGray` and `systemOrange` so they follow Increase Contrast and Differentiate Without Colour. The brand doesn't override the user's accent colour either: buttons, toggles and links stay native.

## Type

- **Wordmark:** "Reclaim" in SF Pro Rounded Bold. The rounded terminals echo the boomerang's tips.
- **Everything else:** the system font, at the sizes macOS uses for popovers and settings. Numbers use monospaced digits so they don't jiggle as drives are measured.

## Voice

Plain, direct and calm. Say what happened and how much: "Reclaimed 186.4 GB on “Footage SSD”." Not "Woohoo! Your drive is sparkling clean!". Deleting is permanent, so confirmations stay exact and never playful.

## In the app

| Where | What |
| --- | --- |
| Menu bar | The boomerang glyph, with the reclaimable amount beside it |
| Panel header | The badge (the icon in miniature), the rounded wordmark, and the reclaimable amount in Ember |
| While measuring or emptying | A spinning boomerang. Under Reduce Motion it's the standard system spinner |
| After emptying | "Reclaimed …" with an Ember boomerang instead of a checkmark: the space came back |
| Settings › General | The badge beside the version number |
| About | The icon and the tagline |

<p align="center">
  <img src="screenshots/panel-light.png" width="300" alt="The panel header with the boomerang badge, the Reclaim wordmark and 190.6 GB in Ember">
  &nbsp;
  <img src="screenshots/panel-reclaimed-light.png" width="300" alt="The panel after emptying a Trash, with an Ember boomerang beside the message Reclaimed 186.4 GB on Footage SSD">
</p>

## Files

- `Resources/AppIcon.icns`, `Resources/AppIcon.png`: built by `make icon` from [`Scripts/make-icon.swift`](../Scripts/make-icon.swift)
- [`Sources/ReclaimUI/Brand/Brand.swift`](../Sources/ReclaimUI/Brand/Brand.swift): colours, the badge, the spinner and the menu bar image
- `docs/brand/brand-sheet.png`: the sheet at the top of this page
