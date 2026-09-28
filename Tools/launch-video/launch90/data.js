// The demo nights, exactly as the app builds them (Shared/MockData.swift and
// Zoon/Models/AppMockData.swift), so every number and shape in the film is
// the one the app draws in its demo mode. The screens are captured from that
// same mode, and the app badges them "Sample data"; so does the film.

// SplitMix64 (Shared/SeededGenerator.swift).
function seeded(seed) {
  let state = BigInt(seed);
  const M = (1n << 64n) - 1n;
  const next = () => {
    state = (state + 0x9E3779B97F4A7C15n) & M;
    let z = state;
    z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & M;
    z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & M;
    return z ^ (z >> 31n);
  };
  return (lo, hi) => lo + Number(next() >> 11n) * (1 / 9007199254740992) * (hi - lo);
}

// The day the screens were captured; the history's weekends follow it.
export const CAPTURE = new Date(2026, 8, 28, 12, 0, 0);

function makeNight(daysAgo, v) {
  const wake = new Date(CAPTURE); wake.setDate(wake.getDate() - daysAgo); wake.setHours(7, 10, 0, 0);
  const bed = new Date(wake.getTime() - v.inBed * 60000);
  return { daysAgo, date: new Date(wake.getFullYear(), wake.getMonth(), wake.getDate()), bedtime: bed, wakeTime: wake,
    efficiency: Math.min(100, v.asleep / v.inBed * 100), ...v };
}

export const goodNight = makeNight(0, {
  asleep: 452, inBed: 488, core: 244, deep: 82, rem: 126, awake: 36, wakes: 2, latency: 12,
  hr: 58, minHR: 51, hrv: 64, resp: 14.2, spo2: 96.8, tempDelta: -0.08, hrv7: 61, debt: 95, workoutHours: 6.5, exercise: 42
});

export const history = (() => {
  const r = seeded(20260807);
  const out = [];
  for (let daysAgo = 29; daysAgo >= 0; daysAgo--) {
    const d = new Date(CAPTURE); d.setDate(d.getDate() - daysAgo);
    const weekend = d.getDay() === 0 || d.getDay() === 6;
    const baseAsleep = weekend ? 455 : 405;
    const asleep = baseAsleep + r(-55, 55);
    const inBed = asleep + r(20, 70);
    const deep = asleep * r(0.11, 0.21);
    const rem = asleep * r(0.17, 0.26);
    const core = asleep - deep - rem;
    const awake = inBed - asleep;
    const wakes = Math.round(r(0, 6));
    out.push(makeNight(daysAgo, {
      asleep, inBed, core, deep, rem, awake, wakes,
      latency: r(6, 34), hr: r(54, 66), minHR: r(48, 58), hrv: r(42, 78), resp: r(13, 16), spo2: r(94, 98),
      tempDelta: r(-0.4, 0.5), hrv7: r(52, 66), debt: Math.max(0, r(-50, 420)), workoutHours: r(0.8, 9), exercise: r(0, 95)
    }));
  }
  out[out.length - 1] = goodNight;   // the newest night is the one Today shows
  return out;
})();

// The night's stages (AppMockData.stageSegments): a fixed pattern stretched
// from sleep onset to the wake.
export const hypnogram = (() => {
  const pattern = [['core', 22], ['deep', 48], ['core', 26], ['rem', 18], ['core', 34], ['deep', 30], ['awake', 6], ['core', 28],
    ['rem', 32], ['core', 24], ['deep', 14], ['rem', 26], ['core', 20], ['awake', 4], ['rem', 34], ['core', 18]];
  let cursor = goodNight.bedtime.getTime() + goodNight.latency * 60000;
  const total = pattern.reduce((s, p) => s + p[1], 0);
  const span = (goodNight.wakeTime.getTime() - cursor) / 60000;
  const scale = span / total;
  return pattern.map(([stage, m]) => { const start = cursor; cursor += m * scale * 60000; return { stage, start, end: cursor }; });
})();

export const fmtHM = m => `${Math.floor(m / 60)}h ${String(Math.round(m % 60)).padStart(2, '0')}m`;
export const clock = d => {
  const h = d.getHours(), m = d.getMinutes(), ap = h < 12 ? 'AM' : 'PM', h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(m).padStart(2, '0')} ${ap}`;
};
// Minutes after 18:00, so a night's bedtimes line up on one axis.
export const eveningMinutes = d => { let m = d.getHours() * 60 + d.getMinutes() - 18 * 60; if (m < 0) m += 1440; return m; };
