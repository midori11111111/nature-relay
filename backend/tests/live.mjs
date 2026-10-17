import assert from 'node:assert/strict';
import fs from 'node:fs/promises';

// Deliberately read-only: no profiles, posts, comments, reports or follows are created.
const base = process.env.NATURE_RELAY_TEST_URL;
if (!base || !/^https:\/\//.test(base)) throw new Error('Set NATURE_RELAY_TEST_URL to the existing deployed HTTPS origin.');
let calls = 0;
async function get(path,expected=200) {
  calls++;
  const response=await fetch(new URL(path,base));
  assert.equal(response.status,expected,`GET ${path}`);
  return response;
}
const health=await (await get('/health')).json();
assert.equal(health.freeOnly,true);
assert.equal(health.moderation,'manual-before-publication');
assert.equal(health.identificationConfigured,false,'Provider must remain disabled for this beta');
for (const path of ['/privacy','/support','/community']) {
  const response=await get(path);const html=await response.text();
  assert.ok(html.includes('support@example.com'));
  assert.ok(response.headers.get('Content-Security-Policy')?.includes("frame-ancestors 'none'"));
}
const feed=await (await get('/v1/posts')).json();
assert.ok(Array.isArray(feed.posts));
for(const post of feed.posts) {
  assert.equal(post.moderationStatus,'approved');
  if(post.latitude!=null) assert.ok(Math.abs(post.latitude*100-Math.round(post.latitude*100))<1e-8);
  if(post.isReference) assert.ok(post.sourceURL && post.sourcePhotoURL && post.sourceAuthor && post.sourceAttribution,'Archive source credit preserved');
}
if(feed.posts.length) {
  const post=feed.posts[0];
  assert.equal((await (await get(`/v1/posts/${post.id}`)).json()).post.id,post.id);
  const comments=await (await get(`/v1/posts/${post.id}/comments`)).json();
  assert.ok(comments.comments.every(comment=>comment.moderationStatus==='approved'));
}
await get('/v1/me',401);
await get('/v1/blocks',401);
await get('/v1/posts?following=1',401);
const record={testedAt:new Date().toISOString(),baseURL:base,passed:true,requests:calls,scope:'Read-only production smoke; no test identities or content created/deleted',checks:['manual pre-publication moderation advertised','public privacy/support/standards contacts available','only approved posts/comments public','archive attribution retained','coarse location retained','private endpoints require authentication','online identification disabled']};
await fs.writeFile(new URL('./live-moderation-readonly.json',import.meta.url),JSON.stringify(record,null,2)+'\n');
console.log(`PASS: ${calls} read-only production checks; no profiles/content mutations or provider calls.`);
