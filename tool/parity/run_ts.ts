// Runs the ORIGINAL TypeScript engine on deterministic scenarios and writes the reference trace.
// Usage: tsx tool/parity/run_ts.ts <path-to-RN-src/game/engine.ts> <out.json>
import { readFileSync, writeFileSync } from 'fs';
const [enginePath, out] = process.argv.slice(2);
function mulberry32(a: number) { return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
(async () => {
  const { Engine } = await import(enginePath);
  const scen = JSON.parse(readFileSync(new URL('./scenarios.json', import.meta.url), 'utf8'));
  const res: any[] = [];
  for (const s of scen) {
    Math.random = mulberry32(12345);
    const cfg: any = { field: s.field, ball: s.ball, forms: s.forms, ai: s.ai, aiLvl: s.aiLvl, limit: s.limit, matchTime: s.matchTime, turnTime: s.turnTime, vip: s.vip, first: s.first };
    if (s.stats) cfg.stats = s.stats.map((x: number[]) => ({ power: x[0], accuracy: x[1] }));
    const e = new Engine(cfg); if (s.aiTeam0) e.aiTeams[0] = true;
    const cps: any[] = []; const evs: string[] = [];
    for (let fr = 0; fr < s.frames; fr++) {
      for (const sh of s.shots) if (sh.f === fr && e.phase === 'aim') { const b = e.bodies.filter((x: any) => x.team === e.turn)[sh.b % 5] || e.bodies[0]; e.fire(b, sh.dx, sh.dy, Math.hypot(sh.dx, sh.dy), !!s.human); }
      e.update(s.dt[fr % s.dt.length]);
      for (const ev of e.events) evs.push(fr + ':' + ev.t + (ev.team !== undefined ? ev.team : '') + (ev.t === 'goal' ? (ev.nogoal ? 'n' : 'y') : ''));
      e.events.length = 0;
      if (fr % 20 === 19 || fr === s.frames - 1) cps.push({ f: fr, ph: e.phase, tu: e.turn, sc: [...e.score], n: e.bodies.length, parts: e.parts.length, acc: e.acc, b: e.bodies.flatMap((b: any) => [b.x, b.y, b.vx, b.vy, b.ang]), R: Array.from(e.ball.R) });
    }
    res.push({ name: s.name, cps, evs });
    console.log(s.name, 'score', e.score.join(':'), 'phase', e.phase, 'events', evs.length);
  }
  writeFileSync(out, JSON.stringify(res));
})();
