# Asset and licence ledger

Every bundled sound and image, with what the repository itself can show
about where it came from. Kept because the release gates
(`APP-STORE-RELEASE-GATES.md`) require the provenance and licence of every
bundled asset, and nothing in this repository recorded them.

**What this ledger can and cannot say.** Each row was built from the file's
git history and its embedded metadata. None of the 27 sound files carries
an ID3 title, artist, copyright or licence tag, and neither the commit that
added them (`01d1ba3`, "Bundle recorded sleep soundscapes on device") nor
the one that added the moon photograph (`a519626`) names a source. So the
source and licence columns say **not recorded**. They are not guesses, and
nothing here should be read as clearance. Each **needs review** row needs the
person who supplied the file to fill in its origin and licence before an
App Store upload.

Generated, not bundled: brown, pink and white noise are synthesised at
runtime (`SoundscapeEngine`) and have no file to license.

## Sounds

| File | Role | Added in | Source | Licence | Status |
|---|---|---|---|---|---|
| `Zoon/Sounds/blizzard.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/brook.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/crickets.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/drizzle.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/embers.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/evening.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/fan.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/fire.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/forest.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/garden.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/harbor.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/insects.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/jungle.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/mountain.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/ocean.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/pond.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/purr.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/rain.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/rainfall.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/storm.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/stream.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/street.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/tent.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/thunder.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/waterfall.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/wind.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |
| `Zoon/Sounds/window.mp3` | looping bed | `01d1ba3` (2026-09-09, #297) | not recorded | not recorded | **needs review** |

## Images

| File | Role | Added in | Source | Licence | Status |
|---|---|---|---|---|---|
| `Zoon/Assets.xcassets/MoonTexture.imageset/moon.png` (and the widget catalog copy) | full-moon photograph, phase applied in code | `a519626` (2026-09-11, #317) | not recorded | not recorded | **needs review**. If it's a NASA/LRO image it's generally public domain but still needs attribution checked; that has to be confirmed, not assumed |
| `Zoon/Assets.xcassets/AppIcon.appiconset` (light, dark, tinted 1024 px) | app icon | see `docs/APP-ICON-2026.md` | not recorded. `Tools/generate-app-icon.py` draws a plain vector crescent, but the design doc describes the shipped icon as carrying "lunar texture", so the committed PNGs may not come from that script | not recorded | **needs review**: confirm whether the texture comes from the moon photograph above or another image |

## Code

| Component | Licence |
|---|---|
| Zoon source | MIT, see `LICENSE` |
| Third-party packages | none. The project has no Swift Package or CocoaPods dependencies |
