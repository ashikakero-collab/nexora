// Edge Function: validates and simulates a shot with the SAME deterministic physics as the client.
// Deploy: supabase functions deploy submit_shot
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { CFG, Body, Shot, applyShot, simulate, snap, stateHash, kickoff, validateShot } from "./physics.ts";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "content-type": "application/json" } });

function bodiesFromState(st: any): Body[] {
  return st.bodies.map((b: any) => {
    const ball = b.kind === 1;
    return { id: b.id, kind: b.kind, team: b.team, r: ball ? CFG.ballR : CFG.discR, m: ball ? CFG.ballMass : CFG.discMass, x: b.x, y: b.y, vx: 0, vy: 0 };
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const authed = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: u } = await authed.auth.getUser();
  if (!u?.user) return json({ error: "unauthorized" }, 401);

  const { matchId, shot } = (await req.json()) as { matchId: string; shot: Shot };
  const { data: m } = await admin.from("fs_matches").select("*").eq("id", matchId).single();
  if (!m || m.status !== "live") return json({ error: "match_not_live" }, 409);

  const st = m.state;
  const team = u.user.id === m.player0 ? 0 : u.user.id === m.player1 ? 1 : -1;
  if (team < 0) return json({ error: "not_a_player" }, 403);
  if (st.turnTeam !== team) return json({ error: "not_your_turn" }, 409);
  if (m.turn_deadline && new Date(m.turn_deadline) < new Date()) return json({ error: "turn_expired" }, 409);

  const bs = bodiesFromState(st);
  const err = validateShot(bs, team, shot);
  if (err) return json({ error: err }, 422);

  applyShot(bs, shot);
  const res = simulate(bs);
  let score: number[] = [...st.score];
  let turnTeam = st.turnTeam, turnNumber = st.turnNumber + 1, winner: number | null = null, status = "live";
  let nextBodies = bs;
  if (res.scorer >= 0) {
    score[res.scorer] += 1;
    if (score[res.scorer] >= CFG.goalsToWin) { winner = res.scorer; status = "finished"; snap(nextBodies); }
    else { nextBodies = kickoff(); turnTeam = 1 - res.scorer; }
  } else { snap(nextBodies); turnTeam = 1 - turnTeam; }
  if (status === "live" && turnNumber >= CFG.maxTurns) { status = "finished"; winner = score[0] === score[1] ? -1 : score[0] > score[1] ? 0 : 1; }

  const hash = stateHash(nextBodies);
  const newState = {
    bodies: nextBodies.map((b) => ({ id: b.id, kind: b.kind, team: b.team, x: b.x, y: b.y })),
    score, turnTeam, turnNumber, phase: status === "finished" ? 2 : 0, winner,
  };
  const { error: e1 } = await admin.from("fs_shots").insert({
    match_id: matchId, turn_number: st.turnNumber, team, body_id: shot.bodyId, dir_x: shot.dirX, dir_y: shot.dirY,
    power: shot.power, result_hash: hash, scorer: res.scorer >= 0 ? res.scorer : null,
  });
  if (e1) return json({ error: "duplicate_or_conflict" }, 409);
  await admin.from("fs_matches").update({
    state: newState, state_hash: hash, status, winner,
    turn_deadline: status === "live" ? new Date(Date.now() + CFG.turnSeconds * 1000 + 2000).toISOString() : null,
    updated_at: new Date().toISOString(),
  }).eq("id", matchId);
  return json({ ok: true, scorer: res.scorer, hash, steps: res.steps });
});
