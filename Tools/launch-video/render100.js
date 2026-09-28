// The 100-second showreel (showreel.html) at 1080p, supersampled: frames are
// drawn at 2x and scaled down with lanczos, encoded for upload (H.264 High,
// 30 fps CFR, BT.709, AAC 320k). Frame 0 is the poster.
//
//   node render100.js cues                 writes cues100.json for score100.py
//   node render100.js stills out/ 6.6 23.6 writes single frames (1x) for review
//   FFMPEG=... node render100.js zoon-showreel.mp4
//   VERTICAL=1 for the 1080x1920 phone layout (same clock, same sound)
//   CLEAN=1 without grain or star twinkle, for copies WhatsApp re-compresses
//   CUTS=cuts90.json SCORE=score90.wav for the 1:30 cut (story ranges left out)
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const FPS = 30, POSTER = 97.6, V = process.env.VERTICAL === '1';
const mode = process.argv[2];
const CUTS = process.env.CUTS ? JSON.parse(fs.readFileSync(process.env.CUTS)).cuts : [];
// Output time -> story time, skipping the cut ranges.
const story = T => { let t = T; for (const [a, b] of CUTS) if (t >= a) t += b - a; return t; };
(async () => {
  const b = await chromium.launch();
  const dsf = mode === 'stills' || mode === 'cues' ? 1 : 2;
  const p = await b.newPage({ viewport: V ? { width: 1080, height: 1920 } : { width: 1920, height: 1080 }, deviceScaleFactor: dsf });
  p.on('pageerror', e => { console.error('page error:', e.message); process.exitCode = 1; });
  await p.goto('file://' + __dirname + '/showreel.html?' + [V && 'v=1', process.env.CLEAN === '1' && 'clean=1'].filter(Boolean).join('&')); await p.evaluate(() => window.ready);
  if (mode === 'cues') {
    const cues = await p.evaluate(() => window.CUES);
    fs.writeFileSync(__dirname + '/cues100.json', JSON.stringify({ duration: await p.evaluate(() => window.DURATION), cues }, null, 0));
    console.log(cues.length, 'cues'); await b.close(); return;
  }
  if (mode === 'stills') {
    const dir = process.argv[3]; fs.mkdirSync(dir, { recursive: true });
    for (const s of process.argv.slice(4)) {
      await p.evaluate(t => window.render(t), Number(s));
      await p.screenshot({ path: `${dir}/f${String(s).padStart(6, '0')}.jpg`, type: 'jpeg', quality: 85 });
    }
    await b.close(); return;
  }
  const out = mode, LIMIT = Number(process.env.LIMIT || 0), START = Number(process.env.START || 0);
  const DUR = await p.evaluate(() => window.DURATION) - CUTS.reduce((s, [a, b]) => s + b - a, 0);
  await p.evaluate(t => window.render(t), POSTER);
  await p.screenshot({ path: out.replace('.mp4', '-poster.jpg'), type: 'jpeg', quality: 95 });
  const ff = spawn(process.env.FFMPEG, ['-y', '-loglevel', 'error',
    '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-', '-i', __dirname + '/' + (process.env.SCORE || 'score100.wav'),
    '-vf', 'scale=' + (V ? '1080:1920' : '1920:1080') + ':flags=lanczos:out_color_matrix=bt709:out_range=tv,format=yuv420p',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', process.env.CRF || '16', '-profile:v', 'high', '-level:v', '4.2',
    '-g', '15', '-bf', '2', '-r', String(FPS),
    '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
    '-c:a', 'aac', '-b:a', '320k', '-ar', '48000', '-movflags', '+faststart', '-shortest', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const frames = LIMIT || Math.round(DUR * FPS);
  const t0 = Date.now();
  for (let i = 0; i < frames; i++) {
    await p.evaluate(t => window.render(t), i === 0 && !START ? POSTER : story(START + i / FPS));
    const buf = await p.screenshot({ type: 'jpeg', quality: 97 });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (i % 300 === 0) console.log(`frame ${i}/${frames} ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  }
  ff.stdin.end(); await new Promise(r => ff.on('close', r)); await b.close();
  console.log('done', out, ((Date.now() - t0) / 1000).toFixed(0) + 's');
})();
