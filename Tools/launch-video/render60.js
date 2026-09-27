// The 60-second launch film, 16:9 or 9:16 (VERTICAL=1). Frame 0 is the poster
// (POSTER seconds in), replacing the first frame so the duration and audio
// sync stay the same.
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
const { spawn } = require('child_process');
const V = process.env.VERTICAL === '1', POSTER = 10.6, FPS = 30;
const out = process.argv[2];
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: V ? { width: 1080, height: 1920 } : { width: 1920, height: 1080 } });
  await p.goto('file://' + __dirname + '/film60.html' + (V ? '?v=1' : '')); await p.evaluate(() => window.ready);
  const DUR = await p.evaluate(() => window.DURATION);
  await p.evaluate(t => window.render(t), POSTER);
  await p.screenshot({ path: out.replace('.mp4', '-poster.jpg'), type: 'jpeg', quality: 92 });
  const ff = spawn(process.env.FFMPEG, ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-i', __dirname + '/score60.wav', '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-profile:v', 'high',
    '-movflags', '+faststart', '-c:a', 'aac', '-b:a', '256k', '-shortest', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const frames = Math.round(DUR * FPS);
  for (let i = 0; i < frames; i++) {
    await p.evaluate(t => window.render(t), i === 0 ? POSTER : i / FPS);
    const buf = await p.screenshot({ type: 'jpeg', quality: 95 });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (i % 300 === 0) console.log(`frame ${i}/${frames}`);
  }
  ff.stdin.end(); await new Promise(r => ff.on('close', r)); await b.close(); console.log('done', out);
})();
