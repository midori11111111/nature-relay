import { publicPage } from "./public-pages";
// No request bodies, photos, IP addresses, session tokens, or provider keys are logged.
// All mutable state is scoped to this request or persisted in the bound D1 database.
type RuntimeEnv = Env & { PLANTNET_API_KEY?: string; PLANTNET_ENABLED?: string };
type RecordValue = Record<string, unknown>;
type UserRow = { id: string; nickname: string };
type PostRow = { id: string; author_id: string; nickname: string; client_observation_id: string; payload: string; has_photo: number; created_at: string; moderation_status: string; comment_count: number; following: number };
type CommentRow = { id: string; post_id: string; author_id: string; nickname: string; text: string; created_at: string; moderation_status: string };

class APIError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}
const securityHeaders = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
};
function json(value: unknown, status = 200): Response {
  return Response.json(value, { status, headers: securityHeaders });
}
function fail(status: number, message: string): never { throw new APIError(status, message); }
function text(value: unknown, max: number, field: string, required = true): string {
  if (value == null && !required) return "";
  if (typeof value !== "string") fail(400, `Add a valid ${field}.`);
  const result = value.trim();
  if ((required && !result) || result.length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(result)) fail(400, `Check the ${field}.`);
  return result;
}
function object(value: unknown): RecordValue {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(400, "Send a valid JSON object.");
  return value as RecordValue;
}
async function boundedBytes(body: ReadableStream<Uint8Array> | null, maximum: number): Promise<Uint8Array> {
  if (!body) fail(400, "The request body is empty.");
  const reader = body.getReader();
  const parts: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maximum) { await reader.cancel(); fail(413, "This photo or request is too large."); }
      parts.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) { bytes.set(part, offset); offset += part.length; }
  return bytes;
}
async function bodyJSON(request: Request, max = 190_000): Promise<RecordValue> {
  if (!request.headers.get("Content-Type")?.toLowerCase().startsWith("application/json")) fail(415, "Send JSON for this action.");
  try { return object(JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(await boundedBytes(request.body, max)))); }
  catch (error) { if (error instanceof APIError) throw error; fail(400, "Send valid JSON."); }
}
async function hash(value: string): Promise<string> {
  const result = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(result), byte => byte.toString(16).padStart(2, "0")).join("");
}
async function consume(db: D1Database, key: string, maximum: number, expires: number): Promise<void> {
  const row = await db.prepare("INSERT INTO request_limits(key,count,expires_at) VALUES(?1,1,?2) ON CONFLICT(key) DO UPDATE SET count=count+1 WHERE count<?3 RETURNING count")
    .bind(key, expires, maximum).first<{ count: number }>();
  if (!row) fail(429, "The free community limit has been reached. Please try again later.");
}
async function authenticate(request: Request, db: D1Database, allowSuspended = false): Promise<UserRow> {
  const token = request.headers.get("Authorization")?.match(/^Bearer ([a-f0-9]{64})$/)?.[1];
  if (!token) fail(401, "Your device session could not be verified.");
  const user = await db.prepare("SELECT id,nickname FROM users WHERE token_hash=?1 AND (suspended=0 OR ?2=1)").bind(await hash(token), allowSuspended ? 1 : 0).first<UserRow>();
  if (!user) fail(401, "Your device session could not be verified.");
  return user;
}
function safeURL(value: unknown, photo: boolean): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string" || value.length > 1000) fail(400, "Check the source link.");
  let url: URL;
  try { url = new URL(value); } catch { fail(400, "Check the source link."); }
  if (url.protocol !== "https:" || url.username || url.password || url.port || url.hash) fail(400, "Use a secure iNaturalist source link.");
  if (photo) {
    const allowed = ["inaturalist-open-data.s3.amazonaws.com", "static.inaturalist.org", "static.inaturalist.org.s3.amazonaws.com"];
    if (!allowed.includes(url.hostname) || !/^\/photos\/\d+\/(?:small|medium|large|original|square)\.(?:jpe?g|png)$/i.test(url.pathname) || url.search) fail(400, "Use an original iNaturalist photo link.");
  } else if (!["www.inaturalist.org", "inaturalist.org"].includes(url.hostname) || !/^\/observations\/\d+\/?$/.test(url.pathname) || url.search) fail(400, "Use an iNaturalist observation link.");
  return url.href;
}
function jpegBase64(value: unknown): string {
  if (typeof value !== "string" || !value || value.length > 170_668 || value.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) fail(400, "Add a JPEG photo smaller than 128 KB.");
  let decoded: string;
  try { decoded = atob(value); } catch { fail(400, "Add a valid JPEG photo."); }
  if (decoded.length > 128_000 || decoded.charCodeAt(0) !== 255 || decoded.charCodeAt(1) !== 216 || decoded.charCodeAt(2) !== 255 || decoded.charCodeAt(decoded.length - 2) !== 255 || decoded.charCodeAt(decoded.length - 1) !== 217) fail(400, "Add a valid JPEG photo smaller than 128 KB.");
  return value;
}
function postJSON(row: PostRow, origin: string): RecordValue {
  const following = row.following === 1;
  return {
    ...object(JSON.parse(row.payload)),
    id: row.id, author: { id: row.author_id, nickname: row.nickname, isFollowing: following },
    clientObservationID: row.client_observation_id, createdAt: row.created_at,
    imageURL: row.has_photo && row.moderation_status === "approved" ? `${origin}/v1/media/${row.id}` : null,
    moderationStatus: row.moderation_status,
    commentCount: row.comment_count, isFollowing: following,
  };
}
// Visibility is enforced for feed, direct post links, comment access and photo access.
function blockClause(viewer: string, author: string): string {
  return `NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=${viewer} AND b.blocked_id=${author}) OR (b.blocker_id=${author} AND b.blocked_id=${viewer}))`;
}
async function ensureNotBlocked(db: D1Database, first: string, second: string): Promise<void> {
  const row = await db.prepare("SELECT 1 AS blocked FROM blocks WHERE (blocker_id=?1 AND blocked_id=?2) OR (blocker_id=?2 AND blocked_id=?1) LIMIT 1").bind(first, second).first();
  if (row) fail(403, "This interaction is unavailable because a profile is blocked.");
}
function postSelect(viewerID: string): { sql: string; bind: string[] } {
  return { sql: `SELECT p.id,p.author_id,CASE WHEN u.id=?1 THEN u.nickname ELSE u.public_nickname END AS nickname,p.client_observation_id,p.payload,(p.photo_base64 IS NOT NULL) AS has_photo,p.created_at,p.moderation_status,
    (SELECT COUNT(*) FROM comments c JOIN users cu ON cu.id=c.author_id WHERE c.post_id=p.id AND cu.suspended=0 AND (c.moderation_status='approved' OR c.author_id=?1) AND ${blockClause('?1','c.author_id')}) AS comment_count,
    EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=?1 AND f.following_id=p.author_id) AS following
    FROM posts p JOIN users u ON u.id=p.author_id AND u.suspended=0 AND (p.moderation_status='approved' OR p.author_id=?1) AND ${blockClause('?1','p.author_id')}`, bind: [viewerID] };
}
async function getPost(db: D1Database, id: string, viewerID: string, origin: string): Promise<RecordValue> {
  const query = postSelect(viewerID);
  const row = await db.prepare(`${query.sql} WHERE p.id=?2`).bind(...query.bind, id).first<PostRow>();
  if (!row) fail(404, "This discovery is no longer available.");
  return postJSON(row, origin);
}
function commentJSON(row: CommentRow): RecordValue {
  return { id: row.id, postID: row.post_id, author: { id: row.author_id, nickname: row.nickname }, text: row.text, createdAt: row.created_at, moderationStatus: row.moderation_status };
}
function validID(value: string): string {
  if (!/^[a-f0-9-]{36}$/.test(value)) fail(404, "This item is not available.");
  return value;
}
async function identify(request: Request, env: RuntimeEnv, user: UserRow, day: string, expiry: number): Promise<Response> {
  // Fail before reading/uploading a photo or consuming provider quota if setup is incomplete.
  if (env.FREE_ONLY !== "true" || env.PLANTNET_ENABLED !== "true" || !env.PLANTNET_API_KEY) fail(503, "Plant identification is not connected yet. Choose a plant name yourself.");
  if (request.headers.get("Content-Type")?.split(";")[0].trim() !== "image/jpeg") fail(415, "Use a JPEG photo for identification.");
  const bytes = await boundedBytes(request.body, 1_572_864);
  if (bytes.length < 4 || bytes[0] !== 255 || bytes[1] !== 216 || bytes[2] !== 255) fail(400, "Use a valid JPEG photo.");
  await consume(env.DB, `identify:user:${user.id}:${day}`, 10, expiry);
  await consume(env.DB, `identify:global:${day}`, 450, expiry);
  const form = new FormData();
  form.append("images", new File([bytes], "plant.jpg", { type: "image/jpeg" }));
  form.append("organs", "auto");
  const upstream = new URL("https://my-api.plantnet.org/v2/identify/all");
  upstream.searchParams.set("api-key", env.PLANTNET_API_KEY);
  upstream.searchParams.set("lang", request.headers.get("X-NatureRelay-Language") === "ja" ? "ja" : "en");
  upstream.searchParams.set("nb-results", "5");
  upstream.searchParams.set("include-related-images", "false");
  let response: Response;
  try { response = await fetch(upstream, { method: "POST", body: form, signal: AbortSignal.timeout(30_000), redirect: "error" }); }
  catch { fail(503, "Plant identification is temporarily unavailable."); }
  if (response.status === 404) fail(422, "No plant candidates were found. Try a clearer close-up.");
  if (response.status === 429) fail(429, "The free plant identification limit has been reached.");
  if (!response.ok) fail(503, "Plant identification is temporarily unavailable.");
  let payload: RecordValue;
  try { payload = object(JSON.parse(new TextDecoder().decode(await boundedBytes(response.body, 256 * 1024)))); }
  catch { fail(502, "The plant service returned an unreadable result."); }
  const results = Array.isArray(payload.results) ? payload.results : [];
  const candidates = results.flatMap(value => {
    if (!value || typeof value !== "object") return [];
    const entry = value as RecordValue;
    if (typeof entry.score !== "number" || !Number.isFinite(entry.score) || entry.score < 0 || entry.score > 1 || !entry.species || typeof entry.species !== "object") return [];
    const species = entry.species as RecordValue;
    const name = species.scientificNameWithoutAuthor ?? species.scientificName;
    if (typeof name !== "string" || !name.trim() || name.length > 256) return [];
    return [{ scientificName: name.trim(), commonNames: Array.isArray(species.commonNames) ? species.commonNames.filter((name): name is string => typeof name === "string" && name.length <= 120).slice(0, 10) : [], score: entry.score }];
  }).sort((a, b) => b.score - a.score).slice(0, 5);
  if (!candidates.length) fail(422, "No plant candidates were found.");
  const remaining = payload.remainingIdentificationRequests;
  return json({ provider: "plantnet", candidates, remainingDailyRequests: typeof remaining === "number" && Number.isInteger(remaining) && remaining >= 0 ? remaining : null });
}

export default {
  async fetch(request: Request, env: RuntimeEnv): Promise<Response> {
    try {
      const url = new URL(request.url);
      const path = url.pathname.replace(/\/$/, "");
      const method = request.method;
      if (method === "GET") { const page = publicPage(path); if (page) return page; }
      if (path === "/health" && method === "GET") return json({ service: "Nature Relay Community", status: "ok", freeOnly: true, moderation: "manual-before-publication", identificationConfigured: env.PLANTNET_ENABLED === "true" && !!env.PLANTNET_API_KEY });
      if (!path.startsWith("/v1/")) fail(404, "This endpoint is not available.");
      if (env.FREE_ONLY !== "true") fail(503, "The free community service is unavailable.");
      // A signed-in user can erase their profile even after reaching write/API quotas.
      if (path === "/v1/me" && method === "DELETE") {
        const user = await authenticate(request, env.DB, true);
        const payload = await bodyJSON(request, 512);
        if (payload.confirmation !== "DELETE") fail(400, "Confirm deletion of your community profile.");
        await env.DB.batch([
          env.DB.prepare("DELETE FROM request_limits WHERE key LIKE ?1").bind(`%:user:${user.id}:%`),
          env.DB.prepare("DELETE FROM users WHERE id=?1").bind(user.id),
        ]);
        return json({ deleted: true });
      }
      const now = new Date();
      const day = now.toISOString().slice(0, 10);
      const expiry = Math.floor(now.getTime() / 1000) + 172_800;
      await consume(env.DB, `api:global:${day}`, 5000, expiry);
      // Only the hash is persisted, not the IP. Rotate the input daily.
      const ipHash = await hash(`${day}:${request.headers.get("CF-Connecting-IP") ?? "unknown"}`);
      await consume(env.DB, `api:ip:${ipHash}:${day}`, 1000, expiry);
      // At most 5,000 requests/day and 48h retention bound the rate-limit table's size.
      await env.DB.prepare("DELETE FROM request_limits WHERE expires_at<?1").bind(Math.floor(now.getTime() / 1000)).run();

      if (path === "/v1/session" && method === "POST") {
        const payload = await bodyJSON(request, 1024);
        const nickname = text(payload.nickname, 40, "nickname");
        await consume(env.DB, `session:ip:${ipHash}:${day}`, 30, expiry);
        const token = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
        const user = { id: crypto.randomUUID(), nickname };
        await env.DB.prepare("INSERT INTO users(id,nickname,token_hash,created_at) VALUES(?1,?2,?3,?4)")
          .bind(user.id, nickname, await hash(token), now.toISOString()).run();
        return json({ token, user }, 201);
      }
      const media = path.match(/^\/v1\/media\/([^/]+)$/);
      if (media && method === "GET") {
        const viewer = request.headers.has("Authorization") ? await authenticate(request, env.DB) : { id: "" };
        const row = await env.DB.prepare(`SELECT photo_base64 FROM posts p JOIN users u ON u.id=p.author_id WHERE p.id=?1 AND u.suspended=0 AND (moderation_status='approved' OR author_id=?2) AND ${blockClause('?2','p.author_id')}`).bind(validID(media[1]), viewer.id).first<{ photo_base64: string | null }>();
        if (!row?.photo_base64) fail(404, "This photo is no longer available.");
        const raw = atob(row.photo_base64);
        const bytes = Uint8Array.from(raw, char => char.charCodeAt(0));
        return new Response(bytes, { headers: { ...securityHeaders, "Content-Type": "image/jpeg" } });
      }
      // Browsing is public and never creates a silent identity. A supplied token is still
      // validated, while following-only views and every mutation require a session.
      const publicRead = method === "GET" && url.searchParams.get("following") !== "1" &&
        (path === "/v1/posts" || /^\/v1\/posts\/[^/]+(?:\/comments)?$/.test(path));
      const user = publicRead && !request.headers.has("Authorization")
        ? { id: "", nickname: "" }
        : await authenticate(request, env.DB);
      if (user.id) await consume(env.DB, `api:user:${user.id}:${day}`, 500, expiry);
      if (method !== "GET") await consume(env.DB, `write:user:${user.id}:${day}`, 150, expiry);

      if (path === "/v1/me" && method === "GET") return json({ user });
      if (path === "/v1/me" && method === "PATCH") {
        const payload = await bodyJSON(request, 1024);
        const nickname = text(payload.nickname, 40, "nickname");
        await env.DB.prepare("UPDATE users SET nickname=?1 WHERE id=?2").bind(nickname, user.id).run();
        return json({ user: { ...user, nickname } });
      }
      if (path === "/v1/blocks" && method === "GET") {
        const rows = await env.DB.prepare("SELECT u.id,u.public_nickname AS nickname FROM blocks b JOIN users u ON u.id=b.blocked_id WHERE b.blocker_id=?1 ORDER BY b.created_at DESC LIMIT 500").bind(user.id).all<UserRow>();
        return json({ users: rows.results });
      }
      const block = path.match(/^\/v1\/blocks\/([^/]+)$/);
      if (block && (method === "POST" || method === "DELETE")) {
        const target = validID(block[1]);
        if (target === user.id) fail(400, "Choose another profile to block.");
        if (!await env.DB.prepare("SELECT id FROM users WHERE id=?1").bind(target).first()) fail(404, "This profile is no longer available.");
        if (method === "POST") {
          await env.DB.batch([
            env.DB.prepare("INSERT OR IGNORE INTO blocks(blocker_id,blocked_id,created_at) VALUES(?1,?2,?3)").bind(user.id,target,now.toISOString()),
            env.DB.prepare("DELETE FROM follows WHERE (follower_id=?1 AND following_id=?2) OR (follower_id=?2 AND following_id=?1)").bind(user.id,target),
          ]);
        } else {
          await env.DB.prepare("DELETE FROM blocks WHERE blocker_id=?1 AND blocked_id=?2").bind(user.id,target).run();
        }
        return json({ blocked: method === "POST" });
      }
      if (path === "/v1/reports" && method === "POST") {
        const payload = await bodyJSON(request, 1024);
        const targetType = text(payload.targetType, 20, "report target");
        const targetID = validID(text(payload.targetID, 36, "report item"));
        const reason = text(payload.reason, 20, "report reason");
        if (!["post","comment","user"].includes(targetType) || !["inappropriate","harassment","spam","privacy","other"].includes(reason)) fail(400, "Choose a valid report category.");
        let targetUserID: string;
        if (targetType === "post") {
          const post = await getPost(env.DB,targetID,user.id,url.origin);
          targetUserID = (post.author as {id:string}).id;
        } else if (targetType === "comment") {
          const row = await env.DB.prepare("SELECT author_id,post_id FROM comments WHERE id=?1 AND (moderation_status='approved' OR author_id=?2)").bind(targetID,user.id).first<{author_id:string;post_id:string}>();
          if (!row) fail(404,"This comment is no longer available.");
          await getPost(env.DB,row.post_id,user.id,url.origin);
          targetUserID = row.author_id;
        } else {
          if (!await env.DB.prepare("SELECT id FROM users WHERE id=?1").bind(targetID).first()) fail(404,"This profile is no longer available.");
          targetUserID = targetID;
        }
        if (targetUserID === user.id) fail(400,"Choose another person's content to report.");
        await env.DB.prepare("INSERT INTO reports(id,reporter_id,target_user_id,target_type,target_id,reason,created_at) VALUES(?1,?2,?3,?4,?5,?6,?7) ON CONFLICT(reporter_id,target_type,target_id) DO UPDATE SET reason=excluded.reason,status='open',created_at=excluded.created_at")
          .bind(crypto.randomUUID(),user.id,targetUserID,targetType,targetID,reason,now.toISOString()).run();
        return json({ received: true });
      }
      if (path === "/v1/identify" && method === "POST") return await identify(request, env, user, day, expiry);
      if (path === "/v1/users" && method === "GET") {
        const query = text(url.searchParams.get("query") ?? "", 40, "search", false).replace(/[\\%_]/g, "\\$&");
        const rows = await env.DB.prepare(`SELECT u.id,u.public_nickname AS nickname,EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=?1 AND f.following_id=u.id) AS following FROM users u WHERE u.id!=?1 AND u.suspended=0 AND u.public_nickname LIKE ?2 ESCAPE '\\' AND ${blockClause('?1','u.id')} ORDER BY u.created_at DESC LIMIT 50`)
          .bind(user.id, `%${query}%`).all<UserRow & { following: number }>();
        return json({ users: rows.results.map(row => ({ id: row.id, nickname: row.nickname, isFollowing: row.following === 1 })) });
      }
      const follow = path.match(/^\/v1\/follows\/([^/]+)$/);
      if (follow && (method === "POST" || method === "DELETE")) {
        const target = validID(follow[1]);
        if (target === user.id) fail(400, "Choose another person to follow.");
        if (!await env.DB.prepare("SELECT id FROM users WHERE id=?1 AND suspended=0").bind(target).first()) fail(404, "This person is not available.");
        if (method === "POST") await ensureNotBlocked(env.DB, user.id, target);
        if (method === "POST") {
          await env.DB.prepare(`INSERT OR IGNORE INTO follows(follower_id,following_id,created_at) SELECT ?1,?2,?3 WHERE ${blockClause('?1','?2')}`).bind(user.id, target, now.toISOString()).run();
          await ensureNotBlocked(env.DB,user.id,target);
        }
        else await env.DB.prepare("DELETE FROM follows WHERE follower_id=?1 AND following_id=?2").bind(user.id, target).run();
        return json({ following: method === "POST" });
      }
      if (path === "/v1/posts" && method === "GET") {
        const query = postSelect(user.id);
        const cursor = url.searchParams.get("cursor") ?? "";
        const [cursorDate, cursorID] = cursor.split("|");
        if (cursor && (!cursorDate || !cursorID || !Number.isFinite(Date.parse(cursorDate)))) fail(400, "Check the page cursor.");
        const followingOnly = url.searchParams.get("following") === "1";
        const rows = await env.DB.prepare(`${query.sql} WHERE (?2=0 OR EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=?1 AND f.following_id=p.author_id)) AND (?3='' OR p.created_at<?3 OR (p.created_at=?3 AND p.id<?4)) ORDER BY p.created_at DESC,p.id DESC LIMIT 50`)
          .bind(...query.bind, followingOnly ? 1 : 0, cursorDate ?? "", cursorID ?? "").all<PostRow>();
        const last = rows.results.at(-1);
        return json({ posts: rows.results.map(row => postJSON(row, url.origin)), nextCursor: rows.results.length === 50 && last ? `${last.created_at}|${last.id}` : null });
      }
      if (path === "/v1/posts" && method === "POST") {
        const payload = await bodyJSON(request);
        const clientID = text(payload.clientObservationID, 80, "local discovery ID");
        if (!/^[A-Za-z0-9-]+$/.test(clientID)) fail(400, "Check the local discovery ID.");
        const existing = await env.DB.prepare("SELECT id FROM posts WHERE author_id=?1 AND client_observation_id=?2").bind(user.id, clientID).first<{ id: string }>();
        if (existing) return json({ post: await getPost(env.DB, existing.id, user.id, url.origin) });
        const kind = text(payload.kind, 30, "category");
        if (!["flower", "plant", "tree", "bird", "butterfly", "other"].includes(kind)) fail(400, "Choose a nature category.");
        const reference = payload.isReference === true;
        const sourceURL = reference ? safeURL(payload.sourceURL, false) : null;
        const sourcePhotoURL = reference ? safeURL(payload.sourcePhotoURL, true) : null;
        if (reference && (!sourceURL || !sourcePhotoURL)) fail(400, "Keep the original observation and photo links with a reference.");
        const photo = reference ? null : jpegBase64(payload.imageBase64);
        const observedAt = text(payload.observedAt, 40, "observation date");
        const observedTime = Date.parse(observedAt);
        if (!Number.isFinite(observedTime) || observedTime < Date.UTC(1800, 0, 1) || observedTime > now.getTime() + 86_400_000) fail(400, "Check the observation date.");
        let latitude: number | null = null;
        let longitude: number | null = null;
        if (payload.latitude != null || payload.longitude != null) {
          if (typeof payload.latitude !== "number" || typeof payload.longitude !== "number" || !Number.isFinite(payload.latitude) || !Number.isFinite(payload.longitude) || Math.abs(payload.latitude) > 90 || Math.abs(payload.longitude) > 180) fail(400, "Check the shared location.");
          latitude = Math.round(payload.latitude * 100) / 100;
          longitude = Math.round(payload.longitude * 100) / 100;
        }
        const stored = {
          name: text(payload.name, 120, "discovery name"), kind,
          commonName: text(payload.commonName, 120, "common name", false) || null,
          scientificName: text(payload.scientificName, 256, "scientific name", false) || null,
          note: text(payload.note, 2000, "note", false), locality: text(payload.locality, 120, "city or area"),
          latitude, longitude, observedAt: new Date(observedTime).toISOString(),
          sourceURL, sourcePhotoURL,
          sourceAuthor: reference ? text(payload.sourceAuthor, 120, "source author") : null,
          sourceAttribution: reference ? text(payload.sourceAttribution, 1000, "source attribution") : null,
          isReference: reference,
        };
        const id = crypto.randomUUID();
        await env.DB.prepare("INSERT OR IGNORE INTO posts(id,author_id,client_observation_id,payload,photo_base64,created_at,moderation_status) VALUES(?1,?2,?3,?4,?5,?6,'pending')")
          .bind(id, user.id, clientID, JSON.stringify(stored), photo, now.toISOString()).run();
        const inserted = await env.DB.prepare("SELECT id FROM posts WHERE author_id=?1 AND client_observation_id=?2").bind(user.id, clientID).first<{ id: string }>();
        if (!inserted) fail(503, "Your discovery could not be saved. Please try again.");
        return json({ post: await getPost(env.DB, inserted.id, user.id, url.origin) }, 201);
      }
      const comment = path.match(/^\/v1\/posts\/([^/]+)\/comments$/);
      if (comment && (method === "GET" || method === "POST")) {
        const postID = validID(comment[1]);
        const visiblePost = await getPost(env.DB, postID, user.id, url.origin);
        if (method === "POST") await ensureNotBlocked(env.DB, user.id, (visiblePost.author as { id: string }).id);
        if (method === "GET") {
          const rows = await env.DB.prepare(`SELECT c.id,c.post_id,c.author_id,CASE WHEN u.id=?2 THEN u.nickname ELSE u.public_nickname END AS nickname,c.text,c.created_at,c.moderation_status FROM comments c JOIN users u ON u.id=c.author_id WHERE c.post_id=?1 AND u.suspended=0 AND (c.moderation_status='approved' OR c.author_id=?2) AND ${blockClause('?2','c.author_id')} ORDER BY c.created_at,c.id LIMIT 50`).bind(postID,user.id).all<CommentRow>();
          return json({ comments: rows.results.map(commentJSON) });
        }
        const payload = await bodyJSON(request, 5000);
        const value = text(payload.text, 1000, "comment");
        const id = crypto.randomUUID();
        const inserted = await env.DB.prepare(`INSERT INTO comments(id,post_id,author_id,text,created_at,moderation_status) SELECT ?1,?2,?3,?4,?5,'pending' WHERE EXISTS(SELECT 1 FROM posts p WHERE p.id=?2 AND (p.moderation_status='approved' OR p.author_id=?3) AND ${blockClause('?3','p.author_id')})`).bind(id, postID, user.id, value, now.toISOString()).run();
        if (inserted.meta.changes !== 1) fail(404,"This discovery is no longer available.");
        return json({ comment: { id, postID, author: user, text: value, createdAt: now.toISOString(), moderationStatus: "pending" } }, 201);
      }
      const post = path.match(/^\/v1\/posts\/([^/]+)$/);
      if (post && method === "GET") return json({ post: await getPost(env.DB, validID(post[1]), user.id, url.origin) });
      if (post && method === "DELETE") {
        const id = validID(post[1]);
        const owner = await env.DB.prepare("SELECT author_id FROM posts WHERE id=?1").bind(id).first<{ author_id: string }>();
        if (!owner) fail(404, "This discovery is no longer available.");
        if (owner.author_id !== user.id) fail(403, "Only the person who shared a discovery can delete it.");
        await env.DB.prepare("DELETE FROM posts WHERE id=?1 AND author_id=?2").bind(id, user.id).run();
        return json({ deleted: true });
      }
      fail(404, "This endpoint is not available.");
    } catch (error) {
      if (error instanceof APIError) return json({ error: error.message }, error.status);
      // Never relay raw D1/HTTP errors: those may contain personal data or upstream credentials.
      if (error instanceof Error && error.message.includes("demo_capacity")) return json({ error: "The free demo has reached its storage capacity. Please try again later." }, 429);
      return json({ error: "The free community service is temporarily unavailable. Please try again later." }, 503);
    }
  },
} satisfies ExportedHandler<RuntimeEnv>;
