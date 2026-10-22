# Asabunko brand assets

This folder holds the logo and the app icon.

## Design

A girl reads a manga. The open book hides her face up to the eyes. A red
morning sun is behind her, and a red tag on the book says 漫画 (manga). "Asa"
is the morning and "bunko" is a small paperback library in Japanese.

## Colours

| Name | Hex | Use |
| --- | --- | --- |
| Red | `#FF5866` | The sun and the tag. The accent of the app in the dark form. |
| Deep red | `#C42F45` | The accent of the app on paper, for contrast. |
| Cream | `#FBF4ED` | The lines of the girl, the book, and the word. |
| Ink | `#0E0B0A` | The background of the app icon. |

## Files

| File | Use |
| --- | --- |
| `logo-full.png` | The full logo with the word "asabunko", on a transparent background. The banner of the README. |
| `logo-mark.png` | The mark with no word, on a transparent background. The app shows it on the empty shelf. |
| `icon-512.png` | The icon of the SideStore source. |
| `render.swift` | Makes the icon and the mark from `logo-full.png`. |

`App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` is the app
icon. It is the mark on the ink background, with no clip, because iOS rounds
the corners itself.

Make the files again from the folder of a copy of `logo-full.png`:

```
swift render.swift logo-full.png
```
