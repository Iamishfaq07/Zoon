// Frame 0 is the poster (window.POSTER), so every platform's thumbnail shows
// it; it replaces the first frame rather than adding one, keeping audio sync.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const { spawn } = require('child_process');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  await p.goto('file://' + __dirname + '/brag.html'); await p.evaluate(() => window.ready);
  const DUR = await p.evaluate(() => window.DURATION), POSTER = await p.evaluate(() => window.POSTER), FPS = 30;
  await p.evaluate(t => window.render(t), POSTER);
  await p.screenshot({ path: __dirname + '/../brag.jpg', type: 'jpeg', quality: 92 });
  const ff = spawn(process.env.FFMPEG, ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-i', __dirname + '/score.wav', '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-profile:v', 'high',
    '-movflags', '+faststart', '-c:a', 'aac', '-b:a', '256k', '-shortest', __dirname + '/../brag.mp4'], { stdio: ['pipe', 'inherit', 'inherit'] });
  const frames = Math.round(DUR * FPS);
  for (let i = 0; i < frames; i++) {
    await p.evaluate(t => window.render(t), i === 0 ? POSTER : i / FPS);
    const buf = await p.screenshot({ type: 'jpeg', quality: 95 });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
  }
  ff.stdin.end(); await new Promise(r => ff.on('close', r)); await b.close(); console.log('done', frames, 'frames');
})();
