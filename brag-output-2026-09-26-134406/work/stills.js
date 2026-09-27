const { chromium } = require('/opt/node22/lib/node_modules/playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message)); p.on('requestfailed', r => errs.push(r.url()));
  await p.goto('file://' + __dirname + '/brag.html'); await p.evaluate(() => window.ready);
  for (const t of process.argv.slice(2).map(Number)) { await p.evaluate(t => window.render(t), t); await p.screenshot({ path: `still-${t}.jpg`, type: 'jpeg', quality: 80 }); }
  console.log('errors', errs); await b.close();
})();
