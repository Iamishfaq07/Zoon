#!/bin/sh
# The WhatsApp export of the launch film, made from the master.
#
#   sh launch90-export.sh <master.mp4> <out-dir>
#
# The master is 2160 x 3840 at 60 fps (launch90-render.js video, DPR=2).
# WhatsApp re-encodes whatever it is sent, so this gives it the best start
# it can have: 1080 x 1920, H.264 High at 30 fps, two-pass VBR, AAC. Frames
# are downscaled from the 4K master (a free 2x supersample), and x264's
# aq-mode 3 spends bits on the dark, flat gradients a night film is made of,
# which is where banding would otherwise show.
#
# Also writes a small variant (under 16 MB) for chats that still cap files
# at that size.
set -e
MASTER="$1"; OUT="${2:-.}"
FFMPEG="${FFMPEG:-ffmpeg}"
mkdir -p "$OUT"
VF="scale=1080:1920:flags=lanczos,fps=30,format=yuv420p"
X264="-c:v libx264 -preset slower -profile:v high -level:v 4.1 -x264-params aq-mode=3:aq-strength=1.0"
COLOR="-colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv"
enc() { # enc <kbps video> <maxrate kbps> <audio kbps> <out>
  PASS="$OUT/.x264-$$"
  "$FFMPEG" -y -loglevel error -i "$MASTER" -vf "$VF" $X264 -b:v "${1}k" -maxrate "${2}k" -bufsize "$(( $2 * 2 ))k" \
    -pass 1 -passlogfile "$PASS" -an -f null -
  "$FFMPEG" -y -loglevel error -i "$MASTER" -vf "$VF" $X264 -b:v "${1}k" -maxrate "${2}k" -bufsize "$(( $2 * 2 ))k" \
    -pass 2 -passlogfile "$PASS" $COLOR -c:a aac -b:a "${3}k" -ar 48000 -ac 2 -movflags +faststart "$4"
  rm -f "$PASS"*
}
enc 6000 9000 192 "$OUT/zoon-launch-whatsapp.mp4"
# 90 s in 16 MB: about 1.3 Mbit/s all in
enc 1250 1900 96 "$OUT/zoon-launch-whatsapp-16mb.mp4"
ls -l "$OUT"/zoon-launch-whatsapp*.mp4
