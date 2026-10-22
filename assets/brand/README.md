# Asabunko brand assets

This folder holds the app icon.

## Design

"Asa" is the morning and "bunko" is a small paperback library in Japanese. The
mark is a morning sun that comes up behind an open book. The two pages have
two lines of text each. The background is the warm charcoal of the app, with
a soft glow.

## Colours

| Name | Hex | Use |
| --- | --- | --- |
| Background | `#17130F` | Icon background. Same as the dark app background. |
| Glow | `#3B2A1D` | Centre of the radial glow behind the mark. |
| Sun top | `#F7C995` | Start of the sun gradient. |
| Sun bottom | `#E08E5C` | End of the sun gradient. |
| Paper | `#FBF7EE` to `#E6D9C3` | The gradient of the pages. |
| Line | `#D6C6AC` | The lines of text on the pages. |

## SVG sources

| File | Use |
| --- | --- |
| `icon-ios.svg` | The iOS app icon. It is square, with no clip, because iOS rounds the corners itself. `App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` is its render at 1024x1024. |
| `icon-full.svg` | The complete square icon with rounded corners. Use it for previews and the README. |
| `icon-monochrome.svg` | The mark alone, in one colour, on a transparent background. |

## PNG renders

| File | Size | Use |
| --- | --- | --- |
| `icon-512.png` | 512x512 | The icon of the SideStore source. |

Render them again with `rsvg-convert`:

```
rsvg-convert -w 1024 -h 1024 icon-ios.svg -o ../../App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
rsvg-convert -w 512 -h 512 icon-full.svg -o icon-512.png
```
