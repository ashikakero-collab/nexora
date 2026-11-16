// Carrom deterministic physics + rules — JS mirror of lib/games/carrom/core/*.dart
// (operation-for-operation). Usage: node test/games/tools/carrom_ref.mjs
// Prints the golden vector used by test/games/carrom_test.dart.

export const C = {
  left: 75, top: 67, right: 949, bottom: 916, centerX: 512, centerY: 491.5,
  pockets: [[91.5, 88], [932.5, 88], [91.5, 895], [932.5, 895]],
  captureR: 44, coinR: 21, strikerR: 27, coinMass: 1.0, strikerMass: 2.0,
  dt: 1 / 120, drag: 1.3, stopSpeed: 8.0, ePiece: 0.90, eWall: 0.72, maxShotSpeed: 2600, maxSteps: 1200,
  baseline0: 797, baseline1: 186, baseMinX: 248, baseMaxX: 776, coinsPerSide: 9, queenBonus: 3, maxTurns: 160,
};
const STRIKER = 0, WHITE = 1, BLACK = 2, QUEEN = 3;
const K3 = 0.8660254037844386;

export function initialBodies() {
  const s = C.coinR * 2 + 0.5;
  const inner = [[s, 0], [s / 2, s * K3], [-s / 2, s * K3], [-s, 0], [-s / 2, -s * K3], [s / 2, -s * K3]];
  const outer = [[2 * s, 0], [1.5 * s, s * K3], [s, 2 * s * K3], [0, 2 * s * K3], [-s, 2 * s * K3], [-1.5 * s, s * K3],
    [-2 * s, 0], [-1.5 * s, -s * K3], [-s, -2 * s * K3], [0, -2 * s * K3], [s, -2 * s * K3], [1.5 * s, -s * K3]];
  const whites = [], blacks = [];
  for (let i = 0; i < 6; i++) (i % 2 === 0 ? whites : blacks).push(inner[i]);
  for (let j = 0; j < 12; j++) {
    let white;
    if (j % 2 === 0) white = (Math.trunc(j / 2)) % 2 === 1; else white = j === 1 || j === 5 || j === 9;
    (white ? whites : blacks).push(outer[j]);
  }
  const cx = C.centerX, cy = C.centerY;
  const bs = [{ id: 0, kind: STRIKER, r: C.strikerR, m: C.strikerMass, x: cx, y: C.baseline0, vx: 0, vy: 0, on: false }];
  for (let i = 0; i < 9; i++) bs.push({ id: 1 + i, kind: WHITE, r: C.coinR, m: C.coinMass, x: cx + whites[i][0], y: cy + whites[i][1], vx: 0, vy: 0, on: true });
  for (let i = 0; i < 9; i++) bs.push({ id: 10 + i, kind: BLACK, r: C.coinR, m: C.coinMass, x: cx + blacks[i][0], y: cy + blacks[i][1], vx: 0, vy: 0, on: true });
  bs.push({ id: 19, kind: QUEEN, r: C.coinR, m: C.coinMass, x: cx, y: cy, vx: 0, vy: 0, on: true });
  return bs;
}

function collidePair(a, b) {
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
    const j = -(1 + C.ePiece) * rv / isum;
    a.vx -= j * ia * nx; a.vy -= j * ia * ny;
    b.vx += j * ib * nx; b.vy += j * ib * ny;
  }
}

function cushions(b) {
  const e = C.eWall;
  if (b.x - b.r < C.left) { b.x = C.left + b.r; if (b.vx < 0) b.vx = -b.vx * e; }
  if (b.x + b.r > C.right) { b.x = C.right - b.r; if (b.vx > 0) b.vx = -b.vx * e; }
  if (b.y - b.r < C.top) { b.y = C.top + b.r; if (b.vy < 0) b.vy = -b.vy * e; }
  if (b.y + b.r > C.bottom) { b.y = C.bottom - b.r; if (b.vy > 0) b.vy = -b.vy * e; }
}

export function pocketAt(x, y) {
  const c2 = C.captureR * C.captureR;
  for (let p = 0; p < C.pockets.length; p++) {
    const dx = x - C.pockets[p][0], dy = y - C.pockets[p][1];
    if (dx * dx + dy * dy < c2) return p;
  }
  return -1;
}

export function step(bs, pocketed) {
  const dt = C.dt;
  const k = Math.max(0, 1 - C.drag * dt);
  const s2 = C.stopSpeed * C.stopSpeed;
  const n = bs.length;
  for (let i = 0; i < n; i++) {
    const b = bs[i]; if (!b.on) continue;
    b.x += b.vx * dt; b.y += b.vy * dt; b.vx *= k; b.vy *= k;
    if (b.vx * b.vx + b.vy * b.vy < s2) { b.vx = 0; b.vy = 0; }
  }
  for (let i = 0; i < n; i++) {
    const a = bs[i]; if (!a.on) continue;
    for (let j = i + 1; j < n; j++) {
      const b = bs[j]; if (!b.on) continue;
      if (a.vx === 0 && a.vy === 0 && b.vx === 0 && b.vy === 0) continue;
      collidePair(a, b);
    }
  }
  for (let i = 0; i < n; i++) { const b = bs[i]; if (!b.on) continue; cushions(b); }
  for (let i = 0; i < n; i++) {
    const b = bs[i]; if (!b.on) continue;
    if (pocketAt(b.x, b.y) >= 0) { b.on = false; b.vx = 0; b.vy = 0; pocketed.push(b.id); }
  }
}

export function isSettled(bs) {
  for (const b of bs) if (b.on && (b.vx !== 0 || b.vy !== 0)) return false;
  return true;
}

export function simulate(bs) {
  const pocketed = []; let steps = 0;
  for (;;) { step(bs, pocketed); steps++; if (isSettled(bs) || steps >= C.maxSteps) break; }
  return { pocketed, steps };
}

const snap1 = (v) => Math.floor(v * 1000 + 0.5) / 1000;
export function snap(bs) { for (const b of bs) { b.x = snap1(b.x); b.y = snap1(b.y); b.vx = 0; b.vy = 0; } }

export function stateHash(bs) {
  let h = 2166136261;
  const mix = (v) => { h = (h ^ (v >>> 0)) >>> 0; h = Math.imul(h, 16777619) >>> 0; };
  for (const b of bs) { mix(Math.floor(b.x * 1000 + 0.5) | 0); mix(Math.floor(b.y * 1000 + 0.5) | 0); mix(b.on ? 1 : 0); }
  return h >>> 0;
}

export function isFree(bs, x, y, r, ignoreId) {
  for (const o of bs) {
    if (!o.on || o.id === ignoreId) continue;
    const dx = o.x - x, dy = o.y - y; const md = o.r + r + 1;
    if (dx * dx + dy * dy < md * md) return false;
  }
  return true;
}

export function respot(bs, id) {
  const b = bs[id]; b.vx = 0; b.vy = 0;
  const st = C.coinR;
  for (let k = 0; k <= 18; k++) for (let gy = -k; gy <= k; gy++) for (let gx = -k; gx <= k; gx++) {
    if (Math.abs(gx) !== k && Math.abs(gy) !== k) continue;
    const x = C.centerX + gx * st, y = C.centerY + gy * st;
    if (x - b.r < C.left + 40 || x + b.r > C.right - 40) continue;
    if (y - b.r < C.top + 40 || y + b.r > C.bottom - 40) continue;
    if (isFree(bs, x, y, b.r, id)) { b.x = x; b.y = y; b.on = true; return; }
  }
  b.x = C.centerX; b.y = C.centerY; b.on = true;
}

// ---------------------------------------------------------------- match (rules)
const kindFor = (seat) => seat === 0 ? WHITE : BLACK;
const baselineY = (seat) => seat === 0 ? C.baseline0 : C.baseline1;
export function newMatch() { return { bodies: initialBodies(), turn: 0, turnNumber: 0, winner: null, queenPendingFor: -1, queenCoveredBy: -1, points: [0, 0] }; }
const remaining = (m, seat) => m.bodies.filter((b) => b.kind === kindFor(seat) && b.on).length;

export function playShot(m, s) {
  const len = Math.sqrt(s.dirX * s.dirX + s.dirY * s.dirY);
  const st = m.bodies[0];
  st.x = s.placeX; st.y = baselineY(m.turn); st.on = true;
  st.vx = s.dirX / len * s.power * C.maxShotSpeed; st.vy = s.dirY / len * s.power * C.maxShotSpeed;
  const sim = simulate(m.bodies);
  return finishShot(m, sim.pocketed, sim.steps);
}

function finishShot(m, pocketed, steps) {
  const bs = m.bodies; const p = m.turn, opp = 1 - p; const ownK = kindFor(p), oppK = kindFor(opp);
  const ownIds = [], oppIds = []; let strikerIn = false, queenIn = false;
  for (const id of pocketed) {
    const k = bs[id].kind;
    if (k === STRIKER) strikerIn = true; else if (k === QUEEN) queenIn = true; else if (k === ownK) ownIds.push(id); else if (k === oppK) oppIds.push(id);
  }
  bs[0].on = false; bs[0].vx = 0; bs[0].vy = 0;
  const returned = []; const foul = strikerIn; let cont = false;
  if (foul) {
    for (const id of ownIds) { respot(bs, id); returned.push(id); }
    if (queenIn || m.queenPendingFor === p) { respot(bs, 19); m.queenPendingFor = -1; }
    for (const b of bs) { if (b.kind === ownK && !b.on) { respot(bs, b.id); returned.push(b.id); break; } }
  } else {
    if (m.queenPendingFor === p) {
      if (ownIds.length > 0) m.queenCoveredBy = p; else respot(bs, 19);
      m.queenPendingFor = -1;
    }
    if (queenIn) { if (ownIds.length > 0) m.queenCoveredBy = p; else m.queenPendingFor = p; }
    cont = ownIds.length > 0 || queenIn;
  }
  if (m.queenCoveredBy < 0) {
    for (let q = 0; q < 2; q++) {
      const seat = q === 0 ? p : opp;
      if (remaining(m, seat) !== 0) continue;
      const k = kindFor(seat); let pick = -1;
      for (let i = pocketed.length - 1; i >= 0; i--) if (bs[pocketed[i]].kind === k) { pick = pocketed[i]; break; }
      if (pick < 0) for (let i = bs.length - 1; i >= 0; i--) if (bs[i].kind === k && !bs[i].on) { pick = i; break; }
      if (pick >= 0) { respot(bs, pick); returned.push(pick); }
      if (seat === p) cont = false;
    }
  }
  if (!cont && m.queenPendingFor === p) { respot(bs, 19); m.queenPendingFor = -1; }
  let over = false;
  if (m.queenCoveredBy >= 0) {
    if (remaining(m, p) === 0) m.winner = p; else if (remaining(m, opp) === 0) m.winner = opp;
    if (m.winner !== null && m.winner >= 0) { over = true; }
  }
  m.turnNumber += 1;
  if (!over && !cont) m.turn = opp;
  snap(bs);
  return { pocketed, steps, ownIds, oppIds, foul, cont, returned };
}

// ---------------------------------------------------------------- golden vector
import { fileURLToPath } from 'node:url';
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const m = newMatch();
  const o1 = playShot(m, { placeX: 512, dirX: 0.03, dirY: -1, power: 1.0 });
  console.log('shot1', JSON.stringify({ pocketed: o1.pocketed, steps: o1.steps, cont: o1.cont, turn: m.turn, hash: stateHash(m.bodies) }));
  console.log('  queen', m.bodies[19].x, m.bodies[19].y, m.bodies[19].on, 'w1', m.bodies[1].x, m.bodies[1].y);
  const placeX = m.turn === 0 ? 300 : 700;
  const o2 = playShot(m, { placeX, dirX: -0.4, dirY: m.turn === 0 ? -1 : 1, power: 0.75 });
  console.log('shot2', JSON.stringify({ placeX, pocketed: o2.pocketed, steps: o2.steps, cont: o2.cont, turn: m.turn, turnNumber: m.turnNumber, hash: stateHash(m.bodies) }));
}
