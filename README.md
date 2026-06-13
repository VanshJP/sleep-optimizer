# Sleep Optimizer

A web app that turns your **WHOOP sleep history** into a personalized,
science-backed **ChiliPad mattress temperature schedule** for the night.

It reads your exported `sleeps.csv`, finds your typical sleep timing and stage
mix across recent good nights, models how sleep cycles progress in ~90-minute
intervals, and produces a setpoint schedule that cools you into deep sleep and
gently warms you toward your usual wake time.

## How it works

1. **Parse & filter** — your WHOOP `sleeps.csv` is parsed in the browser and
   filtered down to recent, good-quality nights.
2. **Profile** — typical sleep onset, wake time, and the average split of
   deep / REM / light / awake time are estimated.
3. **Cycle model** — the night is divided into ~90-minute cycles, each with its
   own stage timing, to decide when the body benefits most from cooling.
4. **Schedule** — a list of temperature setpoints (°F) is generated, each
   annotated with the physiological reasoning behind it.

### Gradual transitions

An optional **Gradual transitions** toggle smooths every change — the evening
cool-down and the pre-wake warm-up — into small **2–3 °F steps about 30 minutes
apart** instead of abrupt jumps. This tracks the natural circadian glide of core
body temperature (distal vasodilation at night, the pre-wake rise at dawn) while
keeping each change small enough to set by hand.

The temperature chart renders these as a smooth diagonal slope, with labeled
setpoints at each anchor and at every morning warm-up step.

## Scientific basis

The schedule logic draws on published thermoregulation research, including
Herberger et al. (2024) on slow-wave sleep, Kim et al. (2025) on REM
thermoregulation and pre-wake warming, and Kräuchi (2000) on distal
vasodilation and core body temperature decline.

> **Note:** This project is for personal experimentation and is not medical
> advice.

## Tech stack

- [Next.js](https://nextjs.org) (App Router)
- React 19 + TypeScript
- Client-side CSV parsing and SVG chart rendering (no backend required)

## Getting started

Install dependencies and run the development server:

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

Then export your sleep data from the WHOOP app as `sleeps.csv` and load it into
the app to generate your schedule.

## Scripts

| Command         | Description                  |
| --------------- | ---------------------------- |
| `npm run dev`   | Start the development server |
| `npm run build` | Build for production         |
| `npm run start` | Run the production build     |

## Project structure

- `app/page.tsx` — main UI, controls, and the `TempChart` SVG component
- `lib/sleep.ts` — CSV parsing, sleep profiling, and `buildSchedule` logic
- `app/globals.css` — theme and component styling
