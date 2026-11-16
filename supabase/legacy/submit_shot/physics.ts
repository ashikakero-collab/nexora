// Finger Soccer deterministic physics — REFERENCE implementation (TypeScript, erasable syntax only).
// The Dart port in lib/finger_soccer/core/*.dart MUST mirror this file operation-for-operation.
// Any change here requires the same change in Dart and a regenerated golden vector (see docs).

export const CFG = {
  fieldW: 680, fieldH: 1000, goalW: 220, goalDepth: 46, postR: 6,
  discR: 34, ballR: 20, discMass: 1.0, ballMass: 0.35,
  dt: 1 / 120, drag: 1.35, stopSpeed: 6.0,
  eDisc: 0.90, eWall: 0.82, eBall: 0.96,
  maxShotSpeed: 2300, discsPerTeam: 5, maxSimTime: 9.0,
  goalsToWin: 5, maxTurns: 40, turnSeconds: 15,
};

export interface Body { id: number; kind: number; team: number; r: number; m: number; x: number; y: number; vx: number; vy: number }
export interface Shot { bodyId: number; dirX: number; dirY: number; power: number }

const MAX_STEPS = Math.floor(CFG.maxSimTime / CFG.dt);
const mL = (CFG.fieldW - CFG.goalW) / 2;
const mR = (CFG.fieldW + CFG.goalW) / 2;
const POSTS: number[][] = [[mL, 0], [mR, 0], [mL, CFG.fieldH], [mR, CFG.fieldH]];

export function kickoff(): Body[] {
  const W = CFG.fieldW, H = CFG.fieldH;
  const base: number[][] = [[0.30, 170], [0.70, 170], [0.50, 300], [0.22, 430], [0.78, 430]];
  const bs: Body[] = [];
  for (let i = 0; i < 5; i++) bs.push({ id: i, kind: 0, team: 0, r: CFG.discR, m: CFG.discMass, x: W * base[i][0], y: H - base[i][1], vx: 0, vy: 0 });
  for (let i = 0; i < 5; i++) bs.push({ id: 5 + i, kind: 0, team: 1, r: CFG.discR, m: CFG.discMass, x: W * base[i][0], y: base[i][1], vx: 0, vy: 0 });
  bs.push({ id: 10, kind: 1, team: -1, r: CFG.ballR, m: CFG.ballMass, x: W / 2, y: H / 2, vx: 0, vy: 0 });
  return bs;
}

function collideStatic(b: Body, px: number, py: number, pr: number): void {
  const dx = b.x - px, dy = b.y - py;
  const minD = b.r + pr;
  const d2 = dx * dx + dy * dy;
  if (d2 >= minD * minD) return;
  let nx = 1, ny = 0, d = 0;
  if (d2 > 0) { d = Math.sqrt(d2); nx = dx / d; ny = dy / d; }
  b.x = px + nx * minD; b.y = py + ny * minD;
  const vn = b.vx * nx + b.vy * ny;
  if (vn < 0) { b.vx -= (1 + CFG.eWall) * vn * nx; b.vy -= (1 + CFG.eWall) * vn * ny; }
}

function collidePair(a: Body, b: Body): void {
  const dx = b.x - a.x, dy = b.y - a.y;
  const minD = a.r + b.r;
  const d2 = dx * dx + dy * dy;
  if (d2 >= minD * minD) return;
  let nx = 1, ny = 0, d = 0;
  if (d2 > 0) { d = Math.sqrt(d2); nx = dx / d; ny = dy / d; }
  const overlap = minD - d;
  const ia = 1 / a.m, ib = 1 / b.m, isum = ia + ib;
  a.x -= nx * overlap * (ia / isum); a.y -= ny * overlap * (ia / isum);
  b.x += nx * overlap * (ib / isum); b.y += ny * overlap * (ib / isum);
  const rv = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
  if (rv < 0) {
    const e = (a.kind === 1 || b.kind === 1) ? CFG.eBall : CFG.eDisc;
    const j = -(1 + e) * rv / isum;
    a.vx -= j * ia * nx; a.vy -= j * ia * ny;
    b.vx += j * ib * nx; b.vy += j * ib * ny;
  }
}

function walls(b: Body): void {
  const W = CFG.fieldW, H = CFG.fieldH, e = CFG.eWall;
  if (b.x - b.r < 0) { b.x = b.r; if (b.vx < 0) b.vx = -b.vx * e; }
  if (b.x + b.r > W) { b.x = W - b.r; if (b.vx > 0) b.vx = -b.vx * e; }
  const inMouth = b.kind === 1 && b.x > mL && b.x < mR;
  if (!inMouth) {
    if (b.y - b.r < 0) { b.y = b.r; if (b.vy < 0) b.vy = -b.vy * e; }
    if (b.y + b.r > H) { b.y = H - b.r; if (b.vy > 0) b.vy = -b.vy * e; }
  } else {
    if (b.y < 0) {
      if (b.x - b.r < mL) { b.x = mL + b.r; if (b.vx < 0) b.vx = -b.vx * e; }
      if (b.x + b.r > mR) { b.x = mR - b.r; if (b.vx > 0) b.vx = -b.vx * e; }
      if (b.y - b.r < -CFG.goalDepth) { b.y = -CFG.goalDepth + b.r; if (b.vy < 0) b.vy = -b.vy * e; }
    } else if (b.y > H) {
      if (b.x - b.r < mL) { b.x = mL + b.r; if (b.vx < 0) b.vx = -b.vx * e; }
      if (b.x + b.r > mR) { b.x = mR - b.r; if (b.vx > 0) b.vx = -b.vx * e; }
      if (b.y + b.r > H + CFG.goalDepth) { b.y = H + CFG.goalDepth - b.r; if (b.vy > 0) b.vy = -b.vy * e; }
    }
  }
}

/** One fixed step. Returns scoring team (0 = bottom team scores in top goal, 1 = top team scores in bottom goal) or -1. */
export function step(bs: Body[]): number {
  const dt = CFG.dt;
  const k = Math.max(0, 1 - CFG.drag * dt);
  const s2 = CFG.stopSpeed * CFG.stopSpeed;
  for (let i = 0; i < bs.length; i++) {
    const b = bs[i];
    b.x += b.vx * dt; b.y += b.vy * dt;
    b.vx *= k; b.vy *= k;
    if (b.vx * b.vx + b.vy * b.vy < s2) { b.vx = 0; b.vy = 0; }
  }
  for (let i = 0; i < bs.length; i++) for (let p = 0; p < POSTS.length; p++) collideStatic(bs[i], POSTS[p][0], POSTS[p][1], CFG.postR);
  for (let i = 0; i < bs.length; i++) for (let j = i + 1; j < bs.length; j++) collidePair(bs[i], bs[j]);
  for (let i = 0; i < bs.length; i++) walls(bs[i]);
  const ball = bs[bs.length - 1];
  if (ball.y < -CFG.ballR) return 0;
  if (ball.y > CFG.fieldH + CFG.ballR) return 1;
  return -1;
}

export function isSettled(bs: Body[]): boolean {
  for (let i = 0; i < bs.length; i++) if (bs[i].vx !== 0 || bs[i].vy !== 0) return false;
  return true;
}

export function applyShot(bs: Body[], s: Shot): void {
  const len = Math.sqrt(s.dirX * s.dirX + s.dirY * s.dirY);
  const b = bs[s.bodyId];
  b.vx = s.dirX / len * s.power * CFG.maxShotSpeed;
  b.vy = s.dirY / len * s.power * CFG.maxShotSpeed;
}

export interface SimResult { scorer: number; steps: number }

export function simulate(bs: Body[]): SimResult {
  let n = 0;
  while (n < MAX_STEPS) {
    const sc = step(bs); n++;
    if (sc >= 0) return { scorer: sc, steps: n };
    if (isSettled(bs)) break;
  }
  return { scorer: -1, steps: n };
}

export function snap(bs: Body[]): void {
  for (let i = 0; i < bs.length; i++) {
    const b = bs[i];
    b.x = Math.floor(b.x * 1000 + 0.5) / 1000; b.y = Math.floor(b.y * 1000 + 0.5) / 1000;
    b.vx = 0; b.vy = 0;
  }
}

export function stateHash(bs: Body[]): number {
  let h = 2166136261;
  const mix = (v: number) => { h = (h ^ (v >>> 0)) >>> 0; h = Math.imul(h, 16777619) >>> 0; };
  for (let i = 0; i < bs.length; i++) {
    mix(Math.floor(bs[i].x * 1000 + 0.5) | 0);
    mix(Math.floor(bs[i].y * 1000 + 0.5) | 0);
  }
  return h >>> 0;
}

export function validateShot(bs: Body[], turnTeam: number, s: Shot): string | null {
  if (!Number.isInteger(s.bodyId) || s.bodyId < 0 || s.bodyId >= bs.length - 1) return "bad_body";
  if (bs[s.bodyId].team !== turnTeam) return "not_your_disc";
  if (!isFinite(s.dirX) || !isFinite(s.dirY) || !isFinite(s.power)) return "not_finite";
  if (s.dirX * s.dirX + s.dirY * s.dirY < 1e-12) return "zero_dir";
  if (s.power <= 0 || s.power > 1) return "bad_power";
  return null;
}
