# Asabunko brand assets

This folder holds the logo and the app icon.

## Design

A girl reads a manga. The open book hides her face up to the eyes. A red
morning sun is behind her, and a red tag on the book says 漫画 (manga). "Asa"
is the morning and "bunko" is a small paperback library in Japanese.

## Colours

| Name | Hex | Use |
| --- | --- | --- |
| Red | `#E34659` | The sun, the clouds, and the tag, softer than the `#F82838` of the source. |
| Light red | `#EE6271` | The accent of the app in the dark form. It has a contrast of 4.5 or more on each dark surface. |
| Deep red | `#B8303F` | The accent of the app on paper, for contrast. |
| Cream | `#FBF4ED` | The lines of the girl, the book, and the word. |
| Black | `#000000` | The background of the icon. |

## Files

| File | Use |
| --- | --- |
| `logo-full.png` | The full logo with the word "asabunko", on a transparent background. The banner of the README. |
| `logo-square.png` | The square logo with no word, with the red of the source. |
| `icon-512.png` | The icon of the SideStore source. |
| `render.swift` | Makes the icons and the mark of the empty shelf from `logo-square.png`, with the softer red. |

`App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` is the app
icon. It is the square logo with no clip, because iOS rounds the corners
itself.

Make the files again in this folder:

```
swift render.swift logo-square.png
```

The script writes `icon-1024.png`, `icon-512.png`, and `mark.png`. Copy
`icon-1024.png` to the app icon and `mark.png` to
`App/Resources/Assets.xcassets/Mark.imageset/`.
