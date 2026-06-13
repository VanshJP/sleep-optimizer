// Core analysis logic: parse WHOOP sleeps.csv, filter to recent good nights,
// estimate stage timing across 90-min cycles, and build a ChiliPad schedule.

export interface SleepProfile {
  nRecent: number;
  nGood: number;
  onsetMin: number; // minutes-of-day of typical sleep onset
  wakeMin: number;
  deep: number;
  rem: number;
  light: number;
  awake: number;
  asleep: number;
  perf: number;
  eff: number;
}

export interface Cycle {
  start: number; // minutes after onset
  end: number;
  deep: number;
  rem: number;
  light: number;
}

export interface ScheduleSeg {
  t: number; // minutes-of-day
  temp: number | null; // °F, null = off
  phase: string;
  why: string;
  durMin: number; // how long this setting holds before the next change
  /** True for intermediate steps in a gradual ramp — rendered as a diagonal
   *  line in the chart rather than a discrete step-hold. */
  isRampStep?: boolean;
}

function parseCSV(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], cur = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { cur += '"'; i++; } else q = false; }
      else cur += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(cur); cur = '';
      if (row.some(x => x !== '')) rows.push(row);
      row = [];
    } else cur += c;
  }
  if (cur !== '' || row.length) { row.push(cur); if (row.some(x => x !== '')) rows.push(row); }
  return rows;
}

const parseDT = (s: string): Date | null => {
  const m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/.exec(s);
  return m ? new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]) : null;
};

const median = (a: number[]): number => {
  const s = [...a].sort((x, y) => x - y), m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

export function analyze(text: string): SleepProfile {
  const rows = parseCSV(text);
  if (rows.length < 2) throw new Error('No data rows found — paste the whole file including the header line.');
  const head = rows[0].map(h => h.trim().toLowerCase());
  const col = (frag: string) => head.findIndex(h => h.includes(frag));
  const ci = {
    onset: col('sleep onset'), wake: col('wake onset'), perf: col('performance'),
    eff: col('efficiency'), light: col('light sleep'), deep: col('deep'),
    rem: col('rem'), awake: col('awake duration'), asleep: col('asleep duration'), nap: col('nap'),
  };
  if (ci.onset < 0 || ci.deep < 0 || ci.rem < 0)
    throw new Error("This doesn't look like a WHOOP sleeps.csv — missing expected columns (Sleep onset / Deep / REM).");

  const nights = rows.slice(1).map(r => ({
    onset: parseDT(r[ci.onset]), wake: parseDT(r[ci.wake]),
    perf: +r[ci.perf], eff: +r[ci.eff],
    light: +r[ci.light], deep: +r[ci.deep], rem: +r[ci.rem],
    awake: +r[ci.awake], asleep: +r[ci.asleep],
    nap: ci.nap >= 0 && String(r[ci.nap]).trim() === 'true',
  })).filter(n => n.onset && n.wake && !n.nap && n.asleep > 120 && isFinite(n.deep)) as Array<{
    onset: Date; wake: Date; perf: number; eff: number;
    light: number; deep: number; rem: number; awake: number; asleep: number; nap: boolean;
  }>;

  if (!nights.length) throw new Error('No valid full-night records found.');
  nights.sort((a, b) => a.onset.getTime() - b.onset.getTime());

  // Recent window: last 60 days
  const latest = nights[nights.length - 1].onset;
  const cutoff = new Date(latest.getTime() - 60 * 864e5);
  const recent = nights.filter(n => n.onset >= cutoff);

  // Good nights: perf>=80 & eff>=85; relax to top half if too few
  let good = recent.filter(n => n.perf >= 80 && n.eff >= 85);
  if (good.length < 10) {
    good = [...recent].sort((a, b) => (b.perf + b.eff) - (a.perf + a.eff))
      .slice(0, Math.max(5, recent.length >> 1));
  }
  if (good.length < 3) throw new Error('Not enough recent nights to build a reliable profile (need at least 3).');

  // Onset minutes-of-day, shifted so bedtimes spanning midnight average correctly
  const om = good.map(n => { const m = n.onset.getHours() * 60 + n.onset.getMinutes(); return m > 720 ? m : m + 1440; });
  const wm = good.map(n => n.wake.getHours() * 60 + n.wake.getMinutes());

  return {
    nRecent: recent.length, nGood: good.length,
    onsetMin: median(om) % 1440, wakeMin: median(wm),
    deep: median(good.map(n => n.deep)), rem: median(good.map(n => n.rem)),
    light: median(good.map(n => n.light)), awake: median(good.map(n => n.awake)),
    asleep: median(good.map(n => n.asleep)),
    perf: median(good.map(n => n.perf)), eff: median(good.map(n => n.eff)),
  };
}

// Distribute stage totals across 90-min cycles (canonical architecture weights:
// slow-wave sleep decays cycle over cycle, REM grows toward morning)
export function buildCycles(p: SleepProfile): Cycle[] {
  const n = Math.max(3, Math.min(6, Math.round(p.asleep / 90)));
  const dw: number[] = [], rw: number[] = [];
  for (let i = 0; i < n; i++) { dw.push(Math.pow(0.55, i)); rw.push(Math.pow(1.55, i)); }
  const ds = dw.reduce((a, b) => a + b), rs = rw.reduce((a, b) => a + b);
  const cyc = p.asleep / n, out: Cycle[] = [];
  let t = 0;
  for (let i = 0; i < n; i++) {
    const d = p.deep * dw[i] / ds, r = p.rem * rw[i] / rs;
    out.push({ start: t, end: t + cyc, deep: d, rem: r, light: Math.max(0, cyc - d - r) });
    t += cyc;
  }
  return out;
}

/** Target step magnitude for a gradual ramp (°F). ~2.5 keeps every individual
 *  move in the 2–3 °F band — small enough to dial in by hand on a pad controller,
 *  big enough that the night isn't a long string of 1 °F nudges. */
const RAMP_STEP_F = 2.5;
/** Number of ~2–3 °F steps needed to cover a temperature change of `delta` °F. */
const rampStepCount = (delta: number): number =>
  Math.max(1, Math.round(Math.abs(delta) / RAMP_STEP_F));

/**
 * Build a short series of intermediate setpoints that ramp gradually from one
 * temperature to another in ~2–3 °F steps spaced roughly half an hour apart,
 * rather than a single discrete jump.
 *
 * @param fromTemp   Temperature (°F) currently in effect at the ramp's start.
 * @param toTemp     Target temperature (°F) reached on the final step.
 * @param startMin   Onset-relative minute where the first step lands.
 * @param stepDur    Minutes between steps (the caller sizes this to fit the
 *                   available window, aiming for ~30 min).
 * @param at         Converter from onset-relative minutes to minutes-of-day.
 * @param midPhase   Phase label for intermediate (non-final) steps.
 * @param finalPhase Phase label for the final step (matches the discrete name).
 * @param finalWhy   Full "why" string for the final step (the real setpoint rationale).
 * @param cooling    True when the temperature is falling (used in explanatory text).
 */
function makeRamp(
  fromTemp: number,
  toTemp: number,
  startMin: number,
  stepDur: number,
  at: (m: number) => number,
  midPhase: string,
  finalPhase: string,
  finalWhy: string,
  cooling: boolean,
): ScheduleSeg[] {
  const delta = toTemp - fromTemp;
  const nSteps = rampStepCount(delta);

  // A small (≲2 °F) or zero difference needs no intermediate steps.
  if (nSteps <= 1) {
    return [{ t: at(startMin), temp: toTemp, phase: finalPhase, why: finalWhy, durMin: 0 }];
  }

  const result: ScheduleSeg[] = [];
  let prev = fromTemp;

  for (let i = 1; i <= nSteps; i++) {
    const offsetMin = startMin + (i - 1) * stepDur;
    const temp = Math.round(fromTemp + (i / nSteps) * delta);
    const isLast = i === nSteps;
    const mag = Math.abs(temp - prev); // size of THIS step in °F

    result.push({
      t: at(offsetMin),
      temp,
      phase: isLast ? finalPhase : midPhase,
      why: isLast
        ? finalWhy
        : `Gradual ${cooling ? 'cooling' : 'warming'} — step ${i} of ${nSteps}: ` +
          `${cooling ? 'down' : 'up'} to ${temp}°F (a ${mag}°F move), holding ~${Math.round(stepDur)} min ` +
          `before the next nudge. Shifting the bed in small 2–3°F steps about half an hour apart ` +
          `tracks the natural circadian ${cooling ? 'fall' : 'rise'} of core body temperature — driven ` +
          `by distal ${cooling ? 'vasodilation' : 'vasoconstriction'} (Kräuchi 2000) — instead of forcing ` +
          `it with one large jump, and stays gentle enough to avoid the "thermal shock" that can ` +
          `trigger micro-arousals and fragment ${cooling ? 'the descent into slow-wave sleep' : 'lighter morning sleep'}.`,
      durMin: 0,
      isRampStep: !isLast,
    });
    prev = temp;
  }

  return result;
}

export function buildSchedule(
  p: SleepProfile,
  cycles: Cycle[],
  baseF: number,
  rampF: number,
  deepDropF: number,
  /** When true, every transition — the evening cool-down AND the pre-wake
   *  warm-up — is smoothed into a series of ~2–3 °F steps spaced about 30 min
   *  apart rather than single discrete jumps. */
  gradual = false,
): ScheduleSeg[] {
  const onset = p.onsetMin;
  const at = (m: number) => (onset + m + 1440) % 1440;
  const totalEnd = cycles[cycles.length - 1].end;
  const segs: ScheduleSeg[] = [];

  // Evidence-based offsets (see methodology + References):
  //  - Coolest during the deep-sleep-rich early night. Herberger et al., Sci Rep 2024;14:4669
  //    (72 adults, 3-center randomized blinded crossover): a high-heat-capacity cooling mattress
  //    raised slow-wave sleep +7.5 min/night (p=0.004) and lowered heart rate -2.36 bpm
  //    (p<0.0001). Deep sleep is front-loaded, so the early night is where this lever lands.
  //  - Stay cool through REM — cool it nearly as hard as deep, never warm it. Kim et al.,
  //    Healthcare 2025;13:2521 (25 adults, PSG crossover) cooled the bed to 30°C during REM vs
  //    33°C in non-REM and saw REM% rise 17.7->20.8 (p=0.006) and REM latency fall 141.8->110.4
  //    min (p=0.002). Thermoregulation is suppressed in REM, so external cooling does the work.
  //    The older "warm during REM" folklore is not supported by controlled data — so the REM-cool
  //    floor sits at ~70% of the deep drop, not half.
  //  - Warm only in the final ~30 min before waking. The same 2025 trial warmed to 36°C
  //    pre-wake (~+3°C) as part of the protocol that lifted sleep efficiency 82.8->87.3%
  //    (p=0.030); it rides the natural pre-waking rise in core temperature.
  const remDropF = Math.max(1, Math.round(deepDropF * 0.7));
  const maxDeep = Math.max(...cycles.map(c => c.deep), 1);

  segs.push({ t: at(-30), temp: baseF, phase: 'Pre-bed cool-down', durMin: 0, why: 'Get into an already-cool bed. Cooling the body helps core temperature fall, and that fall is the strongest physiological cue for sleep onset — distal cooling shortens how long it takes to drop off.' });
  segs.push({ t: at(0), temp: baseF, phase: 'Lights out', durMin: 0, why: 'Your comfort baseline as you lie down. Every other setpoint is computed relative to this number.' });

  // Drive the cooling from each of YOUR cycles, not a fixed clock split. A cycle's drop
  // scales with how much deep (slow-wave) sleep it actually holds — deep is the strongest,
  // best-evidenced cooling target — with a floor at the REM-cool setting so the bed only ever
  // eases from coldest (your deep-heavy early cycles) up to cool (light + REM later) and never
  // warms back up mid-night. Setpoints land on your real cycle boundaries, so the curve follows
  // your hypnogram above instead of three arbitrary plateaus.
  //
  // In gradual mode each discrete jump is replaced by a series of ~2–3 °F steps spaced about
  // 30 min apart, so the bed drifts down the way core body temperature actually falls. Step
  // spacing is compressed if the window can't fit them while still leaving a hold at the target.
  let prevTemp = baseF;
  cycles.forEach((c, i) => {
    const drop = Math.max(remDropF, Math.round(deepDropF * (c.deep / maxDeep)));
    const temp = baseF - drop;
    if (temp === prevTemp) return; // setting already in effect — let it ride
    const startM = i === 0 ? 20 : Math.round(c.start);
    const isColdest = drop >= deepDropF;

    // Time until the next event (next cycle boundary or the start of the wake ramp).
    const nextM = i < cycles.length - 1 ? Math.round(cycles[i + 1].start) : totalEnd - 35;
    const available = Math.max(10, nextM - startM);

    let phase: string, why: string;
    if (isColdest) {
      phase = 'Deep-sleep cooling';
      why = `Coldest setting of the night. Cycle ${i + 1} carries the most deep (slow-wave) sleep of your night — about ${Math.round(c.deep)} min — so the bed runs coldest right here. A 72-person randomized trial (Herberger 2024) found enhanced cooling in the deep-sleep window added slow-wave sleep and lowered resting heart rate.`;
    } else {
      const remLeft = Math.round(cycles.slice(i).reduce((a, x) => a + x.rem, 0));
      phase = 'Light / REM hold';
      why = `Your deep sleep is fading and the night shifts toward lighter stages and your REM-heavy final cycles (about ${remLeft} REM min still ahead). The bed eases up by ${deepDropF - drop}°F, then holds cool — your body barely thermoregulates in REM, and a 2025 sleep-lab trial (Kim 2025) that kept the bed cool through REM measured more REM and faster REM onset.`;
    }

    const tempDelta = Math.abs(temp - prevTemp);
    if (gradual && tempDelta >= 2) {
      // Ramp in ~2–3 °F steps. Aim for ~30 min between steps, compressing to fit the
      // available window while still leaving a hold at the target before the next event.
      const stepDur = Math.max(10, Math.min(30, Math.floor(available / (rampStepCount(tempDelta) + 0.5))));
      const midPhase = isColdest ? 'Gradual deep-sleep cooling' : 'Gradual REM transition';
      const rampSegs = makeRamp(prevTemp, temp, startM, stepDur, at, midPhase, phase, why, temp < prevTemp);
      rampSegs.forEach(s => segs.push(s));
    } else {
      segs.push({ t: at(startM), temp, phase, durMin: 0, why });
    }
    prevTemp = temp;
  });

  // Wake-up warm-up. The bed climbs from its overnight cool hold up toward (and past) your
  // comfort baseline so the alarm lands on an already-surfacing body. In gradual mode this whole
  // rise is itself broken into ~2–3 °F steps that finish ~10 min before wake, riding the natural
  // pre-waking climb in core temperature (Kim 2025 warmed ~+3°C before waking) instead of one
  // abrupt jump. Otherwise it stays the simple two-step lift (ease off cooling, then warm).
  if (rampF > 0) {
    const warmTarget = baseF + rampF;
    const rise = warmTarget - prevTemp;
    if (gradual && rise >= 2) {
      const nUp = rampStepCount(rise);
      const lastMin = totalEnd - 10; // target reached ~10 min before wake, then holds
      // Aim for ~30 min between steps, but keep the whole warm-up inside the back half
      // of the night so it never starts before cooling finishes or overshoots wake.
      const maxSpan = Math.max(nUp - 1, lastMin - Math.round(totalEnd * 0.5));
      const stepDur = nUp > 1 ? Math.max(8, Math.min(30, Math.floor(maxSpan / (nUp - 1)))) : 30;
      const warmStart = lastMin - (nUp - 1) * stepDur;
      const finalWhy = `Reaches ${Math.round(warmTarget)}°F about 10 minutes before your usual wake time. Core temperature naturally climbs as you surface; arriving here gradually (the same ~+3°C pre-wake warming used in the 2025 trial) lets the alarm catch a body already on its way up instead of dragging you out of deep sleep.`;
      const rampSegs = makeRamp(prevTemp, warmTarget, warmStart, stepDur, at, 'Gradual wake warm-up', 'Wake warm-up', finalWhy, false);
      rampSegs.forEach(s => segs.push(s));
    } else {
      segs.push({ t: at(totalEnd - 35), temp: baseF, phase: 'Ease off cooling', durMin: 0, why: `About 35 minutes before your usual wake time the cooling lifts back to your ${Math.round(baseF)}°F baseline — a first gentle step so the warm-up isn't one abrupt jump.` });
      segs.push({ t: at(totalEnd - 15), temp: baseF + rampF, phase: 'Wake warm-up', durMin: 0, why: `A short final warm to ${Math.round(baseF + rampF)}°F. Core temperature naturally climbs just before you wake; matching that rise (the same ~+3°C pre-wake move used in the 2025 trial) lets the alarm catch a body already surfacing instead of dragging you out of deep sleep.` });
    }
  }
  segs.push({ t: (p.wakeMin + 15) % 1440, temp: null, phase: 'Off', durMin: 0, why: 'Shut off shortly after your typical wake time so you\'re not heating or cooling an empty bed.' });

  // fill in how long each setting holds
  for (let i = 0; i < segs.length - 1; i++) {
    segs[i].durMin = (((segs[i + 1].t - segs[i].t) % 1440) + 1440) % 1440;
  }
  return segs;
}

export const fmtTime = (m: number): string => {
  m = ((m % 1440) + 1440) % 1440;
  let h = Math.floor(m / 60);
  const mm = String(Math.round(m % 60)).padStart(2, '0');
  const ap = h >= 12 ? 'PM' : 'AM';
  h = h % 12 || 12;
  return `${h}:${mm} ${ap}`;
};

export const fmtDur = (m: number): string =>
  `${Math.floor(m / 60)}h ${String(Math.round(m % 60)).padStart(2, '0')}m`;

export const cvt = (f: number, u: 'F' | 'C'): string =>
  u === 'C' ? Math.round((f - 32) / 1.8) + '°C' : Math.round(f) + '°F';

export function demoCSV(): string {
  let csv = 'Cycle start time,Cycle end time,Cycle timezone,Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min),Light sleep duration (min),Deep (SWS) duration (min),REM duration (min),Awake duration (min),Sleep need (min),Sleep debt (min),Sleep efficiency %,Sleep consistency %,Nap\n';
  const today = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  for (let i = 0; i < 45; i++) {
    const d = new Date(today.getTime() - i * 864e5);
    const ds = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    const onH = 23 + (i % 3 === 0 ? 1 : 0), onM = 10 + (i * 17) % 40;
    const deep = 85 + (i * 13) % 30, rem = 110 + (i * 7) % 40, light = 200 + (i * 11) % 50;
    const perf = 75 + (i * 5) % 25, eff = 82 + (i * 3) % 14;
    csv += `${ds} ${pad(onH % 24)}:${pad(onM)}:00,,UTC-04:00,${ds} ${pad(onH % 24)}:${pad(onM)}:00,${ds} ${pad(7 + i % 2)}:${pad((i * 23) % 60)}:00,${perf},16.2,${deep + rem + light},${deep + rem + light + 45},${light},${deep},${rem},45,560,40,${eff},70,false\n`;
  }
  return csv;
}
