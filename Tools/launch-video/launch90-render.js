// Renders the 90-second launch film (launch90.html) on the GPU.
//
//   node launch90-render.js stills <dir> 3.5 12 30      single frames, for review
//   node launch90-render.js cues                        writes launch90-cues.json for the score
//   node launch90-render.js video <out.mp4>             the master: 2160x3840, 60 fps, + score
//
// The whole film, start to finish:
//   node launch90-render.js cues && python launch90-score.py      the score, from the film's cues
//   CLEAN=1 node launch90-render.js video master.mp4              the master
//   sh launch90-export.sh master.mp4 <dir>                        the WhatsApp copies
//
// Environment:
//   PLAYWRIGHT   path to the playwright package (default: require('playwright'))
//   FFMPEG       ffmpeg binary (default: ffmpeg on PATH)
//   FPS          frames per second for video (default 60)
//   DPR          device pixels per CSS pixel; 2 renders 2160x3840 (default 2; stills default 1)
//   START/LIMIT  render a range: start time in seconds, number of frames
//   SCORE        the audio file muxed into the video (default launch90-score.wav)
//   CLEAN=1      no film grain (for copies a messaging app re-compresses)
//
// The page is served over HTTP from the repository root, because ES modules
// do not load from file:// URLs. Rendering uses the real GPU through ANGLE's
// D3D11 backend when there is one; SwiftShader otherwise (slow, but the same
// picture).
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');

const HERE = __dirname;
const ROOT = path.resolve(HERE, '..', '..');
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.woff2': 'font/woff2', '.json': 'application/json', '.svg': 'image/svg+xml' };

function serve() {
  return new Promise(resolve => {
    const server = http.createServer((req, res) => {
      const rel = decodeURIComponent(req.url.split('?')[0]);
      const file = path.join(ROOT, rel);
      if (!file.startsWith(ROOT)) { res.writeHead(403); res.end(); return; }
      fs.readFile(file, (err, data) => {
        if (err) { res.writeHead(404); res.end(); return; }
        res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
        res.end(data);
      });
    });
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

(async () => {
  const mode = process.argv[2];
  const server = await serve();
  const port = server.address().port;
  const DPR = Number(process.env.DPR || (mode === 'video' ? 2 : 1));
  const browser = await chromium.launch({
    args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist', '--enable-gpu-rasterization']
  });
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: DPR });
  page.on('pageerror', e => { console.error('page error:', e.message); process.exitCode = 1; });
  page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') console.error('console:', m.text()); });
  const query = [process.env.CLEAN === '1' && 'clean=1'].filter(Boolean).join('&');
  await page.goto(`http://127.0.0.1:${port}/Tools/launch-video/launch90.html${query ? '?' + query : ''}`);
  await page.waitForFunction(() => window.READY === true, null, { timeout: 120000 });
  const info = await page.evaluate(() => ({ dur: window.DURATION, gpu: window.GPU }));
  console.log('duration', info.dur, 'gpu', info.gpu);

  const frame = t => page.evaluate(t => window.render(t), t);

  if (mode === 'cues') {
    const out = await page.evaluate(() => ({ duration: window.DURATION, bpm: window.BPM, cues: window.CUES, music: window.MUSIC }));
    fs.writeFileSync(path.join(HERE, 'launch90-cues.json'), JSON.stringify(out, null, 1));
    console.log(out.cues.length, 'cues,', out.music.length, 'music markers');
  } else if (mode === 'stills') {
    const dir = process.argv[3]; fs.mkdirSync(dir, { recursive: true });
    for (const s of process.argv.slice(4)) {
      const t0 = Date.now();
      await frame(Number(s));
      await page.screenshot({ path: path.join(dir, `t${Number(s).toFixed(2).padStart(6, '0')}.jpg`), type: 'jpeg', quality: 90 });
      console.log(s, (Date.now() - t0) + 'ms');
    }
  } else if (mode === 'video') {
    const out = process.argv[3];
    const FPS = Number(process.env.FPS || 60);
    const START = Number(process.env.START || 0);
    const total = Math.round(info.dur * FPS);
    const frames = Number(process.env.LIMIT || total - Math.round(START * FPS));
    const score = path.join(HERE, process.env.SCORE || 'launch90-score.wav');
    const hasScore = fs.existsSync(score) && !START && !process.env.LIMIT;
    const args = ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-'];
    if (hasScore) args.push('-i', score);
    args.push('-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p',
      '-c:v', 'libx264', '-preset', 'slow', '-crf', process.env.CRF || '14', '-profile:v', 'high', '-level:v', '5.2',
      '-g', String(FPS), '-bf', '2', '-r', String(FPS), '-x264-params', 'colorprim=bt709:transfer=bt709:colormatrix=bt709',
      '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv');
    if (hasScore) args.push('-c:a', 'aac', '-b:a', '320k', '-ar', '48000', '-shortest');
    args.push('-movflags', '+faststart', out);
    const ff = spawn(process.env.FFMPEG || 'ffmpeg', args, { stdio: ['pipe', 'inherit', 'inherit'] });
    const t0 = Date.now();
    for (let i = 0; i < frames; i++) {
      await frame(START + i / FPS);
      const buf = await page.screenshot({ type: 'jpeg', quality: 96 });
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (i % 300 === 0) console.log(`frame ${i}/${frames} ${((Date.now() - t0) / 1000).toFixed(0)}s`);
    }
    ff.stdin.end();
    await new Promise(r => ff.on('close', r));
    console.log('done', out, ((Date.now() - t0) / 1000).toFixed(0) + 's');
  } else {
    console.error('usage: node launch90-render.js stills <dir> <t...> | cues | video <out.mp4>');
    process.exitCode = 2;
  }
  await browser.close();
  server.close();
})();
