# Asabunko brand assets

This folder holds the logo and the app icon.

## Design

A girl reads a manga. The open book hides her face up to the eyes. A red
morning sun is behind her, and a red tag on the book says 漫画 (manga). "Asa"
is the morning and "bunko" is a small paperback library in Japanese.

## Colours

| Name | Hex | Use |
| --- | --- | --- |
| Red | `#FF5866` | The sun and the tag of the mark. |
| Light red | `#EE6271` | The accent of the app in the dark form. It has a contrast of 4.5 or more on each dark surface. |
| Deep red | `#B8303F` | The accent of the app on paper, for contrast. |
| Cream | `#FBF4ED` | The lines of the girl, the book, and the word. |
| Black | `#000000` | The background of the icon. |

## Files

| File | Use |
| --- | --- |
| `logo-full.png` | The full logo with the word "asabunko", on a transparent background. The banner of the README. |
| `logo-square.png` | The square logo with no word. It is not in use. |
| `icon-512.png` | The icon of the SideStore source. |
| `render.swift` | Makes the icons from the mark of `logo-full.png`. |

`App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` is the app
icon. It is the mark of the banner. The mark is taller than it is wide, so
it fills the width of the square, and the few rows that go out at the top
and the bottom are cut. So no bar shows at the sides. iOS rounds the corners
itself.

Make the files again in this folder:

```
swift render.swift logo-full.png
```

The script writes `icon-1024.png` and `icon-512.png`. Copy `icon-1024.png` to
the app icon, and a copy at 600 pixels to
`App/Resources/Assets.xcassets/Mark.imageset/mark.png`.
