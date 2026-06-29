# SpatialVerify brand

Official visual identity for the census field verification app.

## Name & voice

| | |
|---|---|
| **Product name** | SpatialVerify |
| **Primary tagline** | Verify every block. Map every household. |
| **Login / field** | HLB mapping & verification in the field |
| **Short descriptor** | Census field verification |

Tone: precise, trustworthy, field-ready — not playful.

## Colors

| Token | Hex | Use |
|-------|-----|-----|
| **Accent (mint)** | `#00E5A0` | Primary actions, verified state, brand glow |
| **Accent dark** | `#00B87A` | Gradients, pressed states |
| **Ink** | `#0A0A0F` | App background |
| **Surface** | `#14141F` | Cards, nav bar |
| **Text primary** | `#F0F0F5` | Headlines, body |
| **Text secondary** | `#9898A8` | Captions, hints |
| **Map blue** | `#4285F4` | Google map layer, navigation route |

## Logo mark

The mark combines:

1. **Census block grid** — enumeration block boundary  
2. **Location pin** — field GPS / on-the-ground placement  
3. **Check mark** — verification

### Assets

| File | Purpose |
|------|---------|
| `assets/images/app_icon.png` | App store / launcher source (1024-ready raster) |
| `assets/icons/spatialverify_mark.svg` | In-app icon mark |
| `assets/icons/spatialverify_wordmark.svg` | Horizontal lockup with name |

### Flutter widgets

```dart
BrandLogo(size: 96, showTagline: true, useRasterIcon: true)
BrandMark(size: 48, withGlow: true)
```

Constants: `lib/core/brand/app_brand.dart`

## Typography

- **UI font:** Inter (Material theme default)
- **Wordmark:** Inter Bold, tight letter-spacing (−0.5 to −1)

## Do / don't

- Do use mint accent on dark backgrounds.  
- Do keep the mark inside a rounded square (~22% corner radius).  
- Don't stretch or recolor the pin without the check.  
- Don't use light backgrounds for the full login hero (dark-first product).

## Android launcher icons

Regenerate after changing `app_icon.png`:

```powershell
cd mobile
dart run flutter_launcher_icons
```
