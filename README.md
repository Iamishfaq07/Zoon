# Zoon launch film

1:37, slower pacing, with sound scored to the picture (no musical instruments). Rendered from `Tools/launch-video/` on the app branch.

| File | Size | For |
|---|---|---|
| `Zoon-Launch-1080p-16x9.mp4` | 1920×1080, about 7.7 Mbps, AAC 320k | YouTube, X, LinkedIn, website |
| `Zoon-Launch-1080p-9x16.mp4` | 1080×1920, about 7.7 Mbps, AAC 320k | Instagram Reels, TikTok, Shorts |
| `Poster-16x9.jpg`, `Poster-9x16.jpg` | thumbnails | cover image |

H.264 High, BT.709, 30 fps constant, fast start. The poster is baked in as frame 0.

## Showreel (1:40)

- `Zoon-Showreel-1080p-16x9.mp4`: the 100-second motion-graphics showreel, 1920x1080, 30 fps, H.264 + AAC. Designed sound only: no instruments, no music.
- `Poster-Showreel-16x9.jpg`: the poster frame, which is also frame 0 of the film.

Built from `Tools/launch-video/showreel.html`, `score100.py` and `render100.js` on the main branch.

## Showreel for mobile (1:30, 9:16)

- `Zoon-Showreel-90s-1080p-9x16.mp4`: 1080x1920, about 7.4 Mbps. Every scene is laid out for a phone screen, not cropped. For Reels, TikTok and Shorts.
- `Zoon-Showreel-90s-WhatsApp-720p.mp4`: 720x1280, 15.7 MB, fits WhatsApp's 90-second Status and sends in a chat.

The 1:30 cut drops the holds after each beat and the recap montage (`Tools/launch-video/cuts90.json`). The sound was rebuilt on that cut, so every hit still lands.
