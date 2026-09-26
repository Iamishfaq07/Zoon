// 4K master of the 60-second film. VERTICAL=1 for 2160x3840, else 3840x2160.
// Frames are drawn at 2x device pixels (canvas included), piped as near-lossless
// JPEG, converted to BT.709 and encoded for upload (H.264 High, 30 fps CFR,
// short GOP, AAC 320k). Frame 0 is the poster.
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
const { spawn } = require('child_process');
const V = process.env.VERTICAL === '1', POSTER = 10.6, FPS = 30;
const out = process.argv[2], LIMIT = Number(process.env.LIMIT || 0), START = Number(process.env.START || 0);
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: V ? { width: 1080, height: 1920 } : { width: 1920, height: 1080 }, deviceScaleFactor: 2 });
  await p.goto('file://' + __dirname + '/film60.html' + (V ? '?v=1' : '')); await p.evaluate(() => window.ready);
  const DUR = await p.evaluate(() => window.DURATION);
  await p.evaluate(t => window.render(t), POSTER);
  await p.screenshot({ path: out.replace('.mp4', '-poster.jpg'), type: 'jpeg', quality: 95 });
  const ff = spawn(process.env.FFMPEG, ['-y', '-loglevel', 'error',
    '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-', '-i', __dirname + '/score66.wav',
    '-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-profile:v', 'high', '-level:v', '5.2',
    '-g', '15', '-bf', '2', '-r', String(FPS),
    '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
    '-c:a', 'aac', '-b:a', '320k', '-ar', '48000', '-movflags', '+faststart', '-shortest', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const frames = LIMIT || Math.round(DUR * FPS);
  const t0 = Date.now();
  for (let i = 0; i < frames; i++) {
    await p.evaluate(t => window.render(t), i === 0 && !START ? POSTER : START + i / FPS);
    const buf = await p.screenshot({ type: 'jpeg', quality: 97 });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (i % 300 === 0) console.log(`frame ${i}/${frames} ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  }
  ff.stdin.end(); await new Promise(r => ff.on('close', r)); await b.close();
  console.log('done', out, ((Date.now() - t0) / 1000).toFixed(0) + 's');
})();
