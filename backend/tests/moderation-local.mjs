import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { execFileSync } from 'node:child_process';

// This suite refuses non-loopback URLs and only mutates the isolated local D1 store.
// Tokens/photos/raw personal payloads are never printed or written to reports.
const base = process.env.NATURE_RELAY_LOCAL_URL ?? 'http://127.0.0.1:8791';
const origin = new URL(base);
assert.ok(['127.0.0.1','localhost'].includes(origin.hostname) && origin.protocol === 'http:','Local loopback URL required');
const persist = '.wrangler/moderation-local';
let requests = 0;
async function call(path,{method='GET',token,body,expected=200,bytes=false}={}) {
  requests++;
  const response = await fetch(new URL(path,base),{method,headers:{...(token?{Authorization:`Bearer ${token}`} : {}),...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined});
  assert.equal(response.status,expected,`${method} ${path} status`);
  if(bytes)return new Uint8Array(await response.arrayBuffer());
  return response.json();
}
function sql(statement) {
  const raw = execFileSync('npx',['wrangler','d1','execute','nature-relay-community-db','--local','--persist-to',persist,'--command',statement,'--json'],{encoding:'utf8',maxBuffer:1024*1024});
  return JSON.parse(raw)[0].results;
}
const a=await call('/v1/session',{method:'POST',body:{nickname:'Local pending observer A'},expected:201});
const b=await call('/v1/session',{method:'POST',body:{nickname:'Local pending observer B'},expected:201});
const c=await call('/v1/session',{method:'POST',body:{nickname:'Local pending observer C'},expected:201});
const fixture=await fs.readFile(new URL('../../Resources/PhotoMetadataFixtures/unlocated-fixture.jpg',import.meta.url));
const payload={clientObservationID:crypto.randomUUID(),name:'Local synthetic nature fixture',kind:'plant',note:'Isolated local verification only.',locality:'Local test',observedAt:new Date().toISOString(),latitude:37.32127,longitude:-122.04327,imageBase64:fixture.toString('base64'),isReference:false};
const first=await call('/v1/posts',{method:'POST',token:a.token,body:payload,expected:201});
const id=first.post.id;
assert.equal(first.post.moderationStatus,'pending');
assert.equal(first.post.latitude,37.32);
assert.equal(first.post.imageURL,null,'Pending photo has no public media URL');
assert.equal((await call('/v1/posts',{token:a.token})).posts.some(p=>p.id===id),true);
assert.equal((await call('/v1/posts',{token:b.token})).posts.some(p=>p.id===id),false);
assert.equal((await call('/v1/posts')).posts.some(p=>p.id===id),false);
await call(`/v1/posts/${id}`,{expected:404});
await call(`/v1/posts/${id}`,{token:b.token,expected:404});
await call(`/v1/media/${id}`,{expected:404});
assert.deepEqual(await call(`/v1/media/${id}`,{token:a.token,bytes:true}),new Uint8Array(fixture));
await call(`/v1/posts/${id}/comments`,{method:'POST',token:b.token,body:{text:'No access to pending post'},expected:404});
const duplicate=await call('/v1/posts',{method:'POST',token:a.token,body:payload});
assert.equal(duplicate.post.id,id);

// Approval is only possible through the developer's local/admin D1 access, never a public route.
sql(`UPDATE posts SET moderation_status='approved' WHERE id='${id}';`);
const approved=await call(`/v1/posts/${id}`);
assert.equal(approved.post.moderationStatus,'approved');
assert.equal(approved.post.author.nickname,'Nature observer','Unreviewed nickname stays private');
assert.deepEqual(await call(`/v1/media/${id}`,{bytes:true}),new Uint8Array(fixture));
const comment=await call(`/v1/posts/${id}/comments`,{method:'POST',token:b.token,body:{text:'Local pending comment'},expected:201});
assert.equal(comment.comment.moderationStatus,'pending');
assert.equal((await call(`/v1/posts/${id}/comments`)).comments.length,0);
assert.equal((await call(`/v1/posts/${id}/comments`,{token:a.token})).comments.length,0);
assert.equal((await call(`/v1/posts/${id}/comments`,{token:b.token})).comments.some(x=>x.id===comment.comment.id),true);
assert.equal((await call(`/v1/posts/${id}`)).post.commentCount,0);
assert.equal((await call(`/v1/posts/${id}`,{token:b.token})).post.commentCount,1);
sql(`UPDATE comments SET moderation_status='approved' WHERE id='${comment.comment.id}';`);
assert.equal((await call(`/v1/posts/${id}/comments`)).comments.length,1);

for(const [targetType,targetID] of [['post',id],['comment',comment.comment.id],['user',a.user.id]]) {
  const reporter=targetType==='comment'?c:b;
  assert.equal((await call('/v1/reports',{method:'POST',token:reporter.token,body:{targetType,targetID,reason:'privacy'}})).received,true);
}
sql(`UPDATE reports SET status='resolved' WHERE reporter_id='${b.user.id}' AND target_type='user' AND target_id='${a.user.id}';`);
await call('/v1/reports',{method:'POST',token:b.token,body:{targetType:'user',targetID:a.user.id,reason:'harassment'}});
assert.deepEqual(sql(`SELECT status,reason FROM reports WHERE reporter_id='${b.user.id}' AND target_type='user' AND target_id='${a.user.id}';`),[{status:'open',reason:'harassment'}],'A repeated report reopens a resolved item');
await call('/v1/reports',{method:'POST',token:b.token,body:{targetType:'post',targetID:id,reason:'invalid'},expected:400});
await call('/v1/reports',{method:'POST',body:{targetType:'post',targetID:id,reason:'privacy'},expected:401});
await call(`/v1/follows/${a.user.id}`,{method:'POST',token:b.token});
await call(`/v1/follows/${b.user.id}`,{method:'POST',token:a.token});
assert.equal((await call(`/v1/blocks/${a.user.id}`,{method:'POST',token:b.token})).blocked,true);
assert.equal((await call('/v1/blocks',{token:b.token})).users.some(u=>u.id===a.user.id),true);
assert.equal((await call('/v1/posts',{token:b.token})).posts.some(p=>p.id===id),false);
assert.equal((await call('/v1/users',{token:a.token})).users.some(u=>u.id===b.user.id),false);
await call(`/v1/posts/${id}`,{token:b.token,expected:404});
await call(`/v1/posts/${id}/comments`,{token:b.token,expected:404});
await call(`/v1/media/${id}`,{token:b.token,expected:404});
await call(`/v1/follows/${a.user.id}`,{method:'POST',token:b.token,expected:403});
await call(`/v1/follows/${b.user.id}`,{method:'POST',token:a.token,expected:403});
assert.equal((await call(`/v1/posts/${id}/comments`,{token:a.token})).comments.length,0,'Blocked commenter hidden from author');
assert.equal((await call(`/v1/posts/${id}`)).post.id,id,'Approved content stays public without identity');
assert.equal((await call(`/v1/blocks/${a.user.id}`,{method:'DELETE',token:b.token})).blocked,false);
assert.equal((await call('/v1/posts?following=1',{token:b.token})).posts.length,0,'Unblock does not recreate follows');
assert.equal((await call(`/v1/posts/${id}/comments`,{token:a.token})).comments.length,1);

sql(`UPDATE users SET suspended=1 WHERE id='${b.user.id}';`);
await call('/v1/me',{token:b.token,expected:401});
assert.equal((await call(`/v1/posts/${id}/comments`)).comments.length,0,'Suspended authors comments hidden');
assert.equal((await call(`/v1/posts/${id}`)).post.commentCount,0,'Suspended comments excluded from counts');
sql(`UPDATE users SET suspended=0 WHERE id='${b.user.id}';`);

const other=await call('/v1/posts',{method:'POST',token:c.token,body:{...payload,clientObservationID:crypto.randomUUID()},expected:201});
await call('/v1/me',{method:'DELETE',token:b.token,body:{confirmation:'wrong'},expected:400});
await call('/v1/me',{method:'DELETE',body:{confirmation:'DELETE'},expected:401});
assert.equal((await call('/v1/me',{token:b.token})).user.id,b.user.id);
// Deletion remains available even when session counters are deliberately exhausted locally.
sql(`UPDATE request_limits SET count=999999 WHERE key LIKE '%:user:${b.user.id}:%';`);
sql(`UPDATE users SET suspended=1 WHERE id='${b.user.id}';`);
assert.equal((await call('/v1/me',{method:'DELETE',token:b.token,body:{confirmation:'DELETE'}})).deleted,true);
await call('/v1/me',{token:b.token,expected:401});
assert.equal((await call(`/v1/posts/${id}/comments`)).comments.length,0,'Deleted identity comments cascade');
assert.equal((await call(`/v1/posts/${id}`)).post.id,id,'Another author post preserved');
assert.equal(sql(`SELECT COUNT(*) AS count FROM request_limits WHERE key LIKE '%:user:${b.user.id}:%';`)[0].count,0);
await call('/v1/me',{method:'DELETE',token:a.token,body:{confirmation:'DELETE'}});
await call(`/v1/posts/${id}`,{expected:404});
await call(`/v1/media/${id}`,{expected:404});
assert.equal((await call(`/v1/posts/${other.post.id}`,{token:c.token})).post.id,other.post.id,'Unrelated identity survives deletion');
await call('/v1/me',{method:'DELETE',token:c.token,body:{confirmation:'DELETE'}});
assert.equal(sql('SELECT COUNT(*) AS count FROM users;')[0].count,0,'Local fixture users fully removed');
assert.equal(sql('SELECT COUNT(*) AS count FROM reports;')[0].count,0,'Local reports cascade');
for(const path of ['/privacy','/support','/community']) {
  requests++;
  const response=await fetch(new URL(path,base));assert.equal(response.status,200);
  const html=await response.text();assert.ok(html.includes('support@example.com'));
  assert.ok(response.headers.get('Content-Security-Policy').includes("frame-ancestors 'none'"));
}
const record={testedAt:new Date().toISOString(),passed:true,scope:'isolated local D1/API; no remote writes or provider calls',requests,checks:['pending posts/photos private to owner','pending comments private to author and excluded from public counts','manual approval becomes public','generic nickname until approval','report validation and persistence','bidirectional block across feeds, direct links, comments, media, user search and follows','unblock leaves follows removed','account deletion requires auth+confirmation and bypasses exhausted quota','cascade deletion and unrelated data preservation','public privacy/support/standards pages'],runtimeNote:'Installed workerd supports through 2026-08-06; local-only CLI compatibility override used. Production config remains 2026-10-17.'};
await fs.writeFile(new URL('./moderation-verification.json',import.meta.url),JSON.stringify(record,null,2)+'\n');
console.log(`PASS: ${requests} isolated local moderation/privacy requests; fixture accounts/content removed; no remote writes.`);
