const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
(async () => { const b = await chromium.launch(); const p = await b.newPage();
  await p.goto('file://' + __dirname + '/film60.html'); await p.evaluate(() => window.ready);
  const r = await p.evaluate(() => ({ dur: window.DURATION, poster: window.OUT(10.6), map: window.MAPTABLE() }));
  require('fs').writeFileSync(__dirname + '/timemap.json', JSON.stringify({ step: 0.01, out: r.map }));
  console.log(r.dur.toFixed(2), r.poster.toFixed(2)); await b.close(); })();
