// NEXORA hub · nx-call-token — short-lived LiveKit token for an Orbit Network call.
// POST { room: <nx_chats.id>, video?: boolean }  (verify_jwt = true)
// → { url, token, room: 'nxg-call-<chat id>', identity, name, ttl }
// Only authenticated members of that chat (nx_chat_members, read with the caller's own RLS) get a token.
// Secrets (already on the project): LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET.
import { createClient } from "npm:@supabase/supabase-js@2";
import { AccessToken } from "npm:livekit-server-sdk@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  try {
    const url = Deno.env.get("LIVEKIT_URL") ?? "wss://nexora-space-xzjzlfyl.livekit.cloud";
    const key = Deno.env.get("LIVEKIT_API_KEY");
    const secret = Deno.env.get("LIVEKIT_API_SECRET");
    if (!key || !secret) return json({ error: "calls_not_configured" }, 503);

    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: u } = await sb.auth.getUser();
    if (!u?.user) return json({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const room = String(body.room ?? body.room_id ?? "");
    if (!UUID.test(room)) return json({ error: "room required" }, 400);

    const { data: m } = await sb.from("nx_chat_members").select("role").eq("chat_id", room).eq("user_id", u.user.id).maybeSingle();
    if (!m) return json({ error: "not_member" }, 403);
    const { data: chat } = await sb.from("nx_chats").select("kind").eq("id", room).maybeSingle();
    const { data: prof } = await sb.from("profiles").select("username, avatar").eq("id", u.user.id).maybeSingle();

    // Channels: only owner/admins speak; everyone else listens.
    const canPublish = chat?.kind !== "channel" || m.role === "owner" || m.role === "admin";
    const name = prof?.username ?? "Pilot";
    const lkRoom = `nxg-call-${room}`;
    const at = new AccessToken(key, secret, {
      identity: u.user.id,
      name,
      ttl: "15m", // only needed to join; LiveKit keeps the session after that
      metadata: JSON.stringify({ avatar: prof?.avatar ?? null, video: !!body.video }),
    });
    at.addGrant({ room: lkRoom, roomJoin: true, canPublish, canSubscribe: true, canPublishData: true });
    return json({ url, token: await at.toJwt(), room: lkRoom, identity: u.user.id, name, canPublish, ttl: 900 });
  } catch (e) {
    return json({ error: "server", detail: String(e).slice(0, 200) }, 500);
  }
});
