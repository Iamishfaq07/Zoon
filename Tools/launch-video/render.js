// Renders film.html frame by frame at a fixed clock and pipes the frames to ffmpeg.
//
//   python3 score.py                                   # writes score.wav
//   FFMPEG=/path/to/ffmpeg node render.js Zoon-Launch-16x9.mp4
//   FFMPEG=/path/to/ffmpeg VERTICAL=1 node render.js Zoon-Launch-9x16.mp4
//
// Needs Playwright with Chromium, and an ffmpeg built with libx264
// (`pip install imageio-ffmpeg` provides one).
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
const { spawn } = require('child_process');
const FFMPEG = process.env.FFMPEG || 'ffmpeg';
const V = process.env.VERTICAL === '1';
const FPS = 30, DUR = 49.0;
const out = process.argv[2] || (V ? 'Zoon-Launch-9x16.mp4' : 'Zoon-Launch-16x9.mp4');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: V ? { width: 1080, height: 1920 } : { width: 1920, height: 1080 } });
  await page.goto('file://' + __dirname + '/film.html' + (V ? '?v=1' : ''));
  await page.evaluate(() => window.ready);
  const ff = spawn(FFMPEG, [
    '-y', '-loglevel', 'error',
    '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-i', __dirname + '/score.wav',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p',
    '-profile:v', 'high', '-level', '4.2', '-movflags', '+faststart',
    '-c:a', 'aac', '-b:a', '256k', '-shortest', out
  ], { stdio: ['pipe', 'inherit', 'inherit'] });
  const frames = Math.round(DUR * FPS);
  for (let i = 0; i < frames; i++) {
    await page.evaluate(t => window.render(t), i / FPS);
    const buf = await page.screenshot({ type: 'jpeg', quality: 95 });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (i % 150 === 0) console.log(`frame ${i}/${frames}`);
  }
  ff.stdin.end();
  await new Promise(r => ff.on('close', r));
  await browser.close();
  console.log('done', out);
})();
