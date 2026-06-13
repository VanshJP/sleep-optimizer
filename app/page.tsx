"use client";

import { useMemo, useRef, useState } from "react";
import {
  analyze,
  buildCycles,
  buildSchedule,
  cvt,
  demoCSV,
  fmtDur,
  fmtTime,
  type Cycle,
  type ScheduleSeg,
  type SleepProfile,
} from "@/lib/sleep";

const STAGE_COLORS: Record<string, string> = {
  deep: "var(--deep)",
  light: "var(--lightstage)",
  rem: "var(--rem)",
};

/* A drifting thermal line — the brand's one ambient motion. Cold on the left,
   warm on the right, the same gradient as the schedule it will produce. */
function HeroWave() {
  return (
    <svg
      className="wave"
      viewBox="0 0 560 90"
      preserveAspectRatio="none"
      aria-hidden="true"
    >
      <defs>
        <linearGradient id="thermal" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor="var(--ice)" />
          <stop offset="55%" stopColor="var(--ice-deep)" />
          <stop offset="80%" stopColor="var(--ember)" />
          <stop offset="100%" stopColor="var(--amber)" />
        </linearGradient>
      </defs>
      {/* the night's temperature curve: dip cold for deep sleep, lift warm for waking */}
      <path
        className="drift"
        d="M0 60 C 70 60, 90 78, 150 78 S 250 40, 320 44 S 430 50, 470 30 S 540 14, 560 12"
        fill="none"
        stroke="url(#thermal)"
        strokeWidth="1.6"
        strokeDasharray="3 6"
        strokeLinecap="round"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}

function Hypnogram({
  profile,
  cycles,
}: {
  profile: SleepProfile;
  cycles: Cycle[];
}) {
  const W = 860,
    H = 240,
    L = 50,
    R = 20,
    T = 24,
    B = 40;
  const total = cycles[cycles.length - 1].end;
  const x = (m: number) => L + (m / total) * (W - L - R);
  const lanes = { deep: T + 142, light: T + 82, rem: T + 32 };

  const blocks: { stage: keyof typeof lanes; t: number; dur: number }[] = [];
  for (const c of cycles) {
    let t = c.start;
    for (const [stage, dur] of [
      ["deep", c.deep],
      ["light", c.light],
      ["rem", c.rem],
    ] as const) {
      if (dur > 1) blocks.push({ stage, t, dur });
      t += dur;
    }
  }
  const hours: number[] = [];
  for (let m = 0; m <= total; m += 60) hours.push(m);

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="xMidYMid meet"
      role="img"
      aria-label="Estimated sleep stage timeline across the night"
    >
      {(["rem", "light", "deep"] as const).map((s) => (
        <text
          key={s}
          x={6}
          y={lanes[s] + 14}
          fill="var(--faint)"
          fontSize={10}
          style={{ fontFamily: "var(--mono)" }}
        >
          {s === "rem" ? "REM" : s === "light" ? "LGT" : "DEEP"}
        </text>
      ))}
      {blocks.map((b, i) => (
        <rect
          key={i}
          x={x(b.t)}
          y={lanes[b.stage]}
          width={Math.max(1.5, x(b.t + b.dur) - x(b.t))}
          height={24}
          rx={4}
          fill={STAGE_COLORS[b.stage]}
          opacity={0.95}
        />
      ))}
      {cycles.map((c, i) => (
        <line
          key={`l${i}`}
          x1={x(c.end)}
          y1={T + 14}
          x2={x(c.end)}
          y2={H - B}
          stroke="var(--border-soft)"
          strokeDasharray="2,5"
        />
      ))}
      {cycles.map((c, i) => (
        <text
          key={`c${i}`}
          x={x((c.start + c.end) / 2)}
          y={T + 4}
          fill="var(--faint)"
          fontSize={9.5}
          textAnchor="middle"
          style={{ fontFamily: "var(--mono)", letterSpacing: "0.08em" }}
        >
          {i + 1}
        </text>
      ))}
      {hours.map((m) => (
        <text
          key={m}
          x={x(m)}
          y={H - 12}
          fill="var(--faint)"
          fontSize={10.5}
          textAnchor="middle"
          style={{ fontFamily: "var(--mono)" }}
        >
          {fmtTime(profile.onsetMin + m)}
        </text>
      ))}
    </svg>
  );
}

function TempChart({
  segs,
  base,
  units,
}: {
  segs: ScheduleSeg[];
  base: number;
  units: "F" | "C";
}) {
  const W = 860,
    H = 210,
    L = 44,
    R = 20,
    T = 24,
    B = 32;
  const start = segs[0].t;
  const span = (((segs[segs.length - 1].t - start) % 1440) + 1440) % 1440 || 1;
  const rel = (t: number) => (((t - start) % 1440) + 1440) % 1440;
  const temps = segs
    .filter((s) => s.temp !== null)
    .map((s) => s.temp as number);
  const lo = Math.min(...temps) - 2,
    hi = Math.max(...temps) + 2;
  const x = (t: number) => L + (rel(t) / span) * (W - L - R);
  const y = (f: number) => T + ((hi - f) / (hi - lo)) * (H - T - B);
  const baseY = y(base);

  let path = "";
  segs.forEach((sg, i) => {
    if (sg.temp === null) return;
    const nx = x(sg.t),
      ny = y(sg.temp);
    path += path ? ` L ${nx} ${ny}` : `M ${nx} ${ny}`;
    // For ramp steps the next segment continues the diagonal — skip the
    // horizontal "hold" extension so the chart shows a smooth slope instead
    // of a staircase.
    const next = segs[i + 1];
    if (next && !sg.isRampStep) path += ` L ${x(next.t)} ${ny}`;
  });

  // The morning warm-up steps stay labelled so each degree change is visible;
  // the middle-of-night cooling ramp keeps its minimal "faint dot" look.
  const isWakeWarm = (s: ScheduleSeg) =>
    s.phase === "Wake warm-up" || s.phase === "Gradual wake warm-up";

  // Circles + temperature labels: every true anchor PLUS each wake-up ramp step.
  const labeledSegs = segs.filter(
    (s) => s.temp !== null && (!s.isRampStep || isWakeWarm(s)),
  );
  // Faint unlabelled dots: cooling ramp steps only.
  const rampSegs = segs.filter(
    (s) => s.temp !== null && s.isRampStep && !isWakeWarm(s),
  );
  // Time-axis ticks: only true anchors, so the x-axis never crowds.
  const timeSegs = segs.filter((s) => s.temp !== null && !s.isRampStep);

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="xMidYMid meet"
      role="img"
      aria-label="Mattress temperature setpoints across the night"
    >
      {/* baseline reference */}
      <line
        x1={L}
        y1={baseY}
        x2={W - R}
        y2={baseY}
        stroke="var(--border-soft)"
        strokeDasharray="2,4"
      />
      <text
        x={L}
        y={baseY - 5}
        fill="var(--faint)"
        fontSize={9.5}
        style={{ fontFamily: "var(--mono)" }}
      >
        baseline {cvt(base, units)}
      </text>
      <path d={path} fill="none" stroke="var(--ice-deep)" strokeWidth={2.5} />
      {/* Faint tick marks for each ramp step — visible but not labelled */}
      {rampSegs.map((sg, i) => (
        <circle
          key={`r${i}`}
          cx={x(sg.t)}
          cy={y(sg.temp as number)}
          r={2}
          fill={sg.temp! <= base ? "var(--ice)" : "var(--amber)"}
          opacity={0.4}
        />
      ))}
      {/* Full circles + temperature labels for anchors and wake-up ramp steps */}
      {labeledSegs.map((sg, i) => (
        <g key={i}>
          <circle
            cx={x(sg.t)}
            cy={y(sg.temp as number)}
            r={4.5}
            fill={sg.temp! <= base ? "var(--ice)" : "var(--amber)"}
          />
          <text
            x={x(sg.t)}
            y={y(sg.temp as number) - 10}
            fill="var(--text)"
            fontSize={11}
            fontWeight={700}
            textAnchor="middle"
            style={{ fontFamily: "var(--mono)" }}
          >
            {cvt(sg.temp as number, units)}
          </text>
        </g>
      ))}
      {/* Time-axis labels only for true anchor setpoints to avoid overlap */}
      {timeSegs.map((sg, i) => (
        <text
          key={`t${i}`}
          x={x(sg.t)}
          y={H - 10}
          fill="var(--faint)"
          fontSize={10}
          textAnchor="middle"
          style={{ fontFamily: "var(--mono)" }}
        >
          {fmtTime(sg.t)}
        </text>
      ))}
    </svg>
  );
}

export default function Home() {
  const [csv, setCsv] = useState("");
  const [submitted, setSubmitted] = useState("");
  const [units, setUnits] = useState<"F" | "C">("F");
  const [base, setBase] = useState(64);
  const [deepDrop, setDeepDrop] = useState(5);
  const [ramp, setRamp] = useState(6);
  const [gradual, setGradual] = useState(false);
  const [copied, setCopied] = useState(false);
  const resultsRef = useRef<HTMLDivElement>(null);

  const { profile, cycles, error } = useMemo(() => {
    if (!submitted) return { profile: null, cycles: null, error: "" };
    try {
      const p = analyze(submitted);
      return { profile: p, cycles: buildCycles(p), error: "" };
    } catch (e) {
      return {
        profile: null,
        cycles: null,
        error: e instanceof Error ? e.message : String(e),
      };
    }
  }, [submitted]);

  const segs = useMemo(
    () =>
      profile && cycles
        ? buildSchedule(profile, cycles, base, ramp, deepDrop, gradual)
        : null,
    [profile, cycles, base, ramp, deepDrop, gradual],
  );

  const run = (text: string) => {
    setSubmitted(text);
    setTimeout(
      () => resultsRef.current?.scrollIntoView({ behavior: "smooth" }),
      60,
    );
  };

  const loadFile = (f: File) =>
    f.text().then((t) => {
      setCsv(
        t.slice(0, 2000) + (t.length > 2000 ? "\n…(full file loaded)" : ""),
      );
      run(t);
    });

  const copySchedule = () => {
    if (!segs) return;
    const lines = segs.map(
      (s) =>
        `${fmtTime(s.t)}  ${s.temp === null ? "Off" : cvt(s.temp, units)}  ${s.phase}`,
    );
    navigator.clipboard.writeText(
      "My mattress temperature schedule\n" + lines.join("\n"),
    );
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  const stats = profile
    ? [
        [fmtTime(profile.onsetMin), "Typical bedtime"],
        [fmtTime(profile.wakeMin), "Typical wake"],
        [fmtDur(profile.asleep), "Time asleep"],
        [fmtDur(profile.deep), "Deep (SWS)"],
        [fmtDur(profile.rem), "REM"],
        [fmtDur(profile.light), "Light"],
        [Math.round(profile.perf) + "%", "Sleep performance"],
        [Math.round(profile.eff) + "%", "Sleep efficiency"],
      ]
    : [];

  return (
    <>
      <header className="hero">
        <div className="hero-inner">
          <h1>
            A temperature schedule for your bed,
            <br />
            from your own sleep data.
          </h1>
          <p className="tag">
            A simple tool for WHOOP users with a Sleepme / ChiliPad. It reads
            your sleep export and writes a night-long schedule
          </p>
          <p className="tag privacy-line">No data collected.</p>
        </div>
        <HeroWave />
      </header>

      <main className="wrap">
        <section className="start">
          <span className="kicker">How it works</span>
          <h2>Three steps, all on your device</h2>
          <div className="start-grid">
            <aside className="steps-rail">
              <div className="step">
                <span className="n">01 — export</span>
                <b>Get your WHOOP data</b>
                Whoop → More → App Settings → Data Export. WHOOP emails you a
                ZIP with <code>sleeps.csv</code> inside.
              </div>
              <div className="step">
                <span className="n">02 — drop</span>
                <b>Add the file here</b>
                Drag it onto the box or paste the text. It is read on your
                device and never sent anywhere.
              </div>
              <div className="step">
                <span className="n">03 — program</span>
                <b>Copy the setpoints</b>
                Enter the times and temperatures into a Sleepme schedule. Re-run
                weekly as your sleep shifts.
              </div>
            </aside>

            <div className="card drop-card">
              <textarea
                value={csv}
                onChange={(e) => setCsv(e.target.value)}
                onDragOver={(e) => e.preventDefault()}
                onDrop={(e) => {
                  e.preventDefault();
                  const f = e.dataTransfer.files[0];
                  if (f) loadFile(f);
                }}
                placeholder={
                  "Paste the contents of sleeps.csv here, or drag the file onto this box."
                }
                aria-label="WHOOP sleeps.csv contents"
              />
              <div className="row">
                <label className="filebtn" htmlFor="fileInput">
                  Choose sleeps.csv
                </label>
                <input
                  type="file"
                  id="fileInput"
                  accept=".csv,text/csv"
                  onChange={(e) => {
                    const f = e.target.files?.[0];
                    if (f) loadFile(f);
                  }}
                />
                <button
                  className="ghost"
                  onClick={() => {
                    const d = demoCSV();
                    setCsv(d);
                    run(d);
                  }}
                >
                  Try sample data
                </button>
              </div>
              <p className="privacy-inline">
                <b>Stays on your device.</b> The page makes no network requests
                with your data — it is parsed locally and gone when you close
                the tab. Full detail under &ldquo;How your data is
                handled.&rdquo;
              </p>
              {error && <div className="err">{error}</div>}
            </div>
          </div>
        </section>

        {profile && cycles && segs && (
          <div ref={resultsRef} className="results">
            <div className="note">
              Built from your <b>{profile.nGood}</b> best nights in the last 60
              days. We deliberately keep only your high-performance,
              high-efficiency nights, so the schedule chases your sleep at its
              best instead of averaging in the rough ones. The stage timing is
              an estimate — WHOOP exports nightly totals, which we place onto
              the standard 90-minute cycle structure. How and why is in the
              methodology below.
            </div>

            <span className="kicker">Your numbers</span>
            <h2>What a good night looks like for you</h2>
            <div className="card stats">
              {stats.map(([v, l]) => (
                <div className="stat" key={l}>
                  <div className="v">{v}</div>
                  <div className="l">{l}</div>
                </div>
              ))}
            </div>

            <span className="kicker">The night, mapped</span>
            <h2>When you reach each stage</h2>
            <div className="card">
              <Hypnogram profile={profile} cycles={cycles} />
              <div className="legend">
                <span>
                  <i style={{ background: "var(--deep)" }} />
                  Deep — physical recovery, front-loaded
                </span>
                <span>
                  <i style={{ background: "var(--lightstage)" }} />
                  Light — the connective tissue between stages
                </span>
                <span>
                  <i style={{ background: "var(--rem)" }} />
                  REM — dreaming and memory, back-loaded
                </span>
              </div>
            </div>

            <span className="kicker">Tune it, then program it</span>
            <h2>Your schedule</h2>
            <div className="tune-grid">
              <aside className="tune-rail">
                <div className="card controls">
                  <div className="ctl">
                    <label>Units</label>
                    <select
                      value={units}
                      onChange={(e) => setUnits(e.target.value as "F" | "C")}
                    >
                      <option value="F">Fahrenheit</option>
                      <option value="C">Celsius</option>
                    </select>
                    <p className="hint">
                      These are water temperatures for the pad, not room
                      temperature.
                    </p>
                  </div>
                  <div className="ctl">
                    <label>
                      Comfort baseline{" "}
                      <output className="plain">{cvt(base, units)}</output>
                    </label>
                    <input
                      type="range"
                      min={55}
                      max={95}
                      step={1}
                      value={base}
                      onChange={(e) => setBase(+e.target.value)}
                      aria-label="Comfort baseline temperature"
                    />
                    <p className="hint">
                      The temperature you like falling asleep at.
                    </p>
                  </div>
                  <div className="ctl">
                    <label>
                      Deep-sleep cold drop{" "}
                      <output className="cold">
                        &minus;
                        {units === "C"
                          ? (deepDrop / 1.8).toFixed(1) + "°C"
                          : deepDrop + "°F"}
                      </output>
                    </label>
                    <input
                      type="range"
                      min={0}
                      max={15}
                      step={1}
                      value={deepDrop}
                      onChange={(e) => setDeepDrop(+e.target.value)}
                      aria-label="Deep sleep cold drop"
                    />
                    <p className="hint">
                      How much colder the bed runs in the early night, when most
                      of your deep sleep happens. Colder here tends to mean more
                      deep sleep.
                    </p>
                  </div>
                  <div className="ctl">
                    <label>
                      Wake-up warm-up{" "}
                      <output className="warm">
                        +
                        {units === "C"
                          ? (ramp / 1.8).toFixed(1) + "°C"
                          : ramp + "°F"}
                      </output>
                    </label>
                    <input
                      type="range"
                      min={0}
                      max={25}
                      step={1}
                      value={ramp}
                      onChange={(e) => setRamp(+e.target.value)}
                      aria-label="Wake-up warming"
                    />
                    <p className="hint">
                      How much warmer the bed gets in the last half hour before
                      your usual wake time, so the alarm lands gently. Set to 0
                      to stay cool.
                    </p>
                  </div>
                  <div className="ctl">
                    <label className="toggle-label">
                      <span>Gradual transitions</span>
                      <span className={`toggle-pill${gradual ? " on" : ""}`}>
                        <input
                          type="checkbox"
                          role="switch"
                          aria-checked={gradual}
                          checked={gradual}
                          onChange={(e) => setGradual(e.target.checked)}
                          aria-label="Gradual temperature transitions"
                        />
                        <span className="toggle-thumb" />
                      </span>
                    </label>
                    <p className="hint">
                      Smooths every transition — the evening cool-down and the
                      pre-wake warm-up — into small 2–3°F steps about 30 min
                      apart instead of abrupt jumps. Tracks the natural circadian
                      glide of core body temperature (distal vasodilation at
                      night, the pre-wake rise at dawn) and keeps each change
                      small enough to set by hand.
                    </p>
                  </div>
                </div>
              </aside>

              <div className="card output-card">
                <TempChart segs={segs} base={base} units={units} />
                <table>
                  <thead>
                    <tr>
                      <th>Time</th>
                      <th>Set to</th>
                      <th>Phase</th>
                      <th>Why this temperature</th>
                    </tr>
                  </thead>
                  <tbody>
                    {segs.map((s, i) => (
                      <tr key={i}>
                        <td className="time">
                          {fmtTime(s.t)}
                          {s.durMin > 0 && (
                            <small>holds {fmtDur(s.durMin)}</small>
                          )}
                        </td>
                        <td
                          className="temp"
                          style={{
                            color:
                              s.temp === null
                                ? "var(--faint)"
                                : s.temp <= base
                                  ? "var(--ice)"
                                  : "var(--amber)",
                          }}
                        >
                          {s.temp === null ? "Off" : cvt(s.temp, units)}
                        </td>
                        <td className="phase-cell">{s.phase}</td>
                        <td className="why">{s.why}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <div className="row">
                  <button className="ghost" onClick={copySchedule}>
                    {copied ? "Copied" : "Copy as text"}
                  </button>
                  <a className="why-link" href="#reasoning">
                    Why these temperatures? See the reasoning &amp; sources ↓
                  </a>
                </div>
              </div>
            </div>

            <div className="explain-grid">
              <div id="reasoning">
                <span className="kicker">The reasoning</span>
                <h2>How this schedule is built</h2>
                <div className="card">
                  <details open>
                    <summary>We keep only your recent, good nights</summary>
                    <div className="body">
                      <p>
                        From your export we take the last 60 days of full-night
                        sleeps (naps excluded), then keep nights with sleep
                        performance &ge; 80% and efficiency &ge; 85%. If that
                        leaves fewer than 10, we fall back to the top half of
                        recent nights by performance + efficiency. For you that
                        was <b>{profile.nGood}</b> of {profile.nRecent} recent
                        nights.
                      </p>
                      <p>
                        Averaging in bad nights would tune the schedule toward
                        mediocre sleep. We use medians, not means, so a single
                        strange night cannot drag the numbers around.
                      </p>
                    </div>
                  </details>
                  <details>
                    <summary>We estimate when each stage happens</summary>
                    <div className="body">
                      <p>
                        WHOOP&rsquo;s CSV reports <em>totals</em> (e.g.{" "}
                        {fmtDur(profile.deep)} of deep sleep) but not the
                        minute-by-minute hypnogram. The <em>shape</em> of a
                        night, though, is one of the most reproducible findings
                        in sleep science: sleep runs in ~90-minute cycles, deep
                        sleep dominates the first cycles and fades, REM is brief
                        early and expands toward morning.
                      </p>
                      <p>
                        We split your median night ({fmtDur(profile.asleep)})
                        into {cycles.length} cycles and distribute your measured
                        totals across them with decaying weights for deep sleep
                        and growing weights for REM — anchored to your real
                        totals and bedtime, not a textbook night.
                      </p>
                    </div>
                  </details>
                  <details>
                    <summary>
                      We map temperature to the stages — and what the research
                      says
                    </summary>
                    <div className="body">
                      <p>
                        <b>Falling asleep — get into an already-cool bed.</b>{" "}
                        Sleep onset is triggered by a fall in core body
                        temperature, driven by heat escaping through the skin of
                        your hands and feet. The distal-to-proximal skin
                        temperature gradient predicts how fast you fall asleep
                        better than core temperature, melatonin, or sleepiness
                        do
                        <a
                          href="https://journals.physiology.org/doi/full/10.1152/ajpregu.2000.278.3.R741"
                          target="_blank"
                          rel="noopener"
                        >
                          [3]
                        </a>
                        . A cool surface speeds that heat loss, so you lie down
                        in a bed already set to your comfort baseline rather
                        than cooling it afterward.
                      </p>
                      <p>
                        <b>Deep sleep, early night — coldest.</b> A 72-person,
                        three-center randomized blinded crossover trial
                        (Herberger 2024) found a cooling mattress added
                        <b>+7.5&nbsp;min</b> of slow-wave sleep per night
                        (p=0.004) and lowered heart rate
                        <b>−2.36&nbsp;bpm</b> (p&lt;0.0001)
                        <a
                          href="https://pmc.ncbi.nlm.nih.gov/articles/PMC10897321/"
                          target="_blank"
                          rel="noopener"
                        >
                          [1]
                        </a>
                        . Deep sleep is front-loaded, so the bed runs coldest
                        exactly where your data says your deep sleep
                        concentrates.
                      </p>
                      <p>
                        <b>REM, late night — stay cool, don&rsquo;t warm.</b>{" "}
                        This is the part most ChiliPad advice gets backwards.
                        During REM the body nearly stops regulating its own
                        temperature, so the surface does the work. A 2025
                        polysomnography trial (Kim 2025) cooled the bed to{" "}
                        <b>30&deg;C during REM</b> (vs 33&deg;C in non-REM) and
                        measured REM rise from <b>17.7% to 20.8%</b> (p=0.006)
                        with REM onset <b>31&nbsp;min faster</b>
                        (p=0.002)
                        <a
                          href="https://pmc.ncbi.nlm.nih.gov/articles/PMC12524338/"
                          target="_blank"
                          rel="noopener"
                        >
                          [2]
                        </a>
                        . So we hold REM nearly as cold as deep sleep — about
                        70% of the deep drop — instead of warming your REM-heavy
                        final cycles.
                      </p>
                      <p>
                        <b>Waking — a short warm ramp.</b> The same 2025 trial
                        warmed the bed to
                        <b>36&deg;C</b> in the half hour before waking, part of
                        the protocol that lifted sleep efficiency from{" "}
                        <b>82.8% to 87.3%</b> (p=0.030). Core temperature rises
                        naturally before you wake; matching it makes the alarm
                        feel less like being pulled out of deep sleep. Set the
                        warm-up to 0 if you&rsquo;d rather stay cool to the end.
                      </p>
                    </div>
                  </details>
                  <details>
                    <summary>References</summary>
                    <div className="body refs">
                      <p>
                        [1] Herberger S, et&nbsp;al.{" "}
                        <em>
                          Enhanced conductive body heat loss during sleep
                          increases slow-wave sleep and calms the heart.
                        </em>{" "}
                        Scientific Reports 2024;14:4669.
                        <a
                          href="https://pmc.ncbi.nlm.nih.gov/articles/PMC10897321/"
                          target="_blank"
                          rel="noopener"
                        >
                          pmc.ncbi.nlm.nih.gov
                        </a>
                      </p>
                      <p>
                        [2] Kim J-W, et&nbsp;al.{" "}
                        <em>
                          Polysomnographic evidence of enhanced sleep quality
                          with adaptive thermal regulation.
                        </em>{" "}
                        Healthcare (Basel) 2025;13:2521.
                        <a
                          href="https://pmc.ncbi.nlm.nih.gov/articles/PMC12524338/"
                          target="_blank"
                          rel="noopener"
                        >
                          pmc.ncbi.nlm.nih.gov
                        </a>
                      </p>
                      <p>
                        [3] Kräuchi K, et&nbsp;al.{" "}
                        <em>
                          Functional link between distal vasodilation and
                          sleep-onset latency?
                        </em>{" "}
                        Am J Physiol Regul Integr Comp Physiol 2000;278:R741.
                        <a
                          href="https://journals.physiology.org/doi/full/10.1152/ajpregu.2000.278.3.R741"
                          target="_blank"
                          rel="noopener"
                        >
                          journals.physiology.org
                        </a>
                      </p>
                      <p>
                        [4] Harding EC, Franks NP, Wisden W.{" "}
                        <em>The temperature dependence of sleep.</em>
                        Frontiers in Neuroscience 2019;13:336.
                        <a
                          href="https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2019.00336/full"
                          target="_blank"
                          rel="noopener"
                        >
                          frontiersin.org
                        </a>
                      </p>
                      <p className="refs-note">
                        Cooling is the most replicated of these effects. REM and
                        wake-ramp moves rest on smaller trials, and lab
                        skin-contact temperatures don&rsquo;t map one-to-one
                        onto pad water setpoints — so treat the numbers as a
                        starting point and let your own WHOOP deep and REM
                        minutes settle the final values.
                      </p>
                    </div>
                  </details>
                  <details>
                    <summary>Limits — read once</summary>
                    <div className="body">
                      <p>
                        This is an estimate from your stage totals, not a
                        recording of tonight. Alcohol, late meals, stress, and
                        illness all shift your architecture night to night. The
                        strongest, most replicated result is the early-night
                        cooling; the REM and wake moves are supported but from
                        smaller trials, and absolute water setpoints don&rsquo;t
                        map one-to-one to the skin-contact temperatures used in
                        labs. Treat this as a starting point: run it a week,
                        watch your WHOOP deep and REM minutes, and nudge in
                        small steps. Not a medical device, not medical advice —
                        see a clinician for a suspected sleep disorder.
                      </p>
                    </div>
                  </details>
                </div>
              </div>

              <div>
                <span className="kicker">Your data</span>
                <h2>How it&rsquo;s handled</h2>
                <div className="card">
                  <ul className="checklist">
                    <li>
                      Your CSV is parsed by JavaScript in your browser. It is
                      never uploaded.
                    </li>
                    <li>
                      Zero network requests carry your data — no analytics,
                      trackers, cookies, or external fonts and scripts.
                    </li>
                    <li>
                      Nothing is written to disk or browser storage. Close the
                      tab and it is gone.
                    </li>
                    <li>
                      A Content-Security-Policy blocks all outbound connections,
                      so even injected code could not send your data anywhere.
                    </li>
                    <li>
                      Verify it yourself: open developer tools, watch the
                      Network tab while you load your file, and you will see no
                      requests.
                    </li>
                  </ul>
                </div>
              </div>
            </div>

            <footer>
              <hr className="arc" />
              For Sleepme / ChiliPad owners who track with WHOOP. Not affiliated
              with either. Not medical advice. Your ideal temperatures are yours
              — let your own deep and REM numbers be the judge.
            </footer>
          </div>
        )}
      </main>
    </>
  );
}
