import {execFileSync} from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// Human-operated D1 moderation. No network endpoint grants moderation privileges.
// Remote changes happen only when an operator explicitly selects --remote and an action.
const [action,kind,id,...flags]=process.argv.slice(2);
if(!action || action==='--help') {
  console.log('Usage: node tools/moderation.mjs queue [--remote]\n       node tools/moderation.mjs review post|comment|user|report UUID [--remote]\n       node tools/moderation.mjs approve post|comment|user UUID [--remote]\n       node tools/moderation.mjs reject post|comment UUID [--remote]\n       node tools/moderation.mjs suspend|restore user UUID [--remote]\n       node tools/moderation.mjs resolve report UUID [--remote]\nDefaults to isolated local D1. Review creates a private local HTML file; inspect the photo, text and attribution before approving. Remote requires the developer\'s existing Wrangler authorization. No users/posts are deleted by this tool.');
  process.exit(0);
}
const remote=process.argv.includes('--remote');
const location=remote?['--remote']:['--local','--persist-to','.wrangler/moderation-local'];
const cwd=fileURLToPath(new URL('../',import.meta.url));
function sql(statement) {
  const result=execFileSync('npx',['wrangler','d1','execute','nature-relay-community-db',...location,'--command',statement,'--json'],{cwd,encoding:'utf8',maxBuffer:2*1024*1024});
  const parsed=JSON.parse(result);return parsed.flatMap(item=>item.results??[]);
}
if(action==='queue') {
  const rows=sql("SELECT 'post' AS type,id,created_at FROM posts WHERE moderation_status='pending' UNION ALL SELECT 'comment',id,created_at FROM comments WHERE moderation_status='pending' UNION ALL SELECT 'user',id,created_at FROM users WHERE nickname!=public_nickname UNION ALL SELECT 'report',id,created_at FROM reports WHERE status='open' ORDER BY created_at LIMIT 200");
  console.log(JSON.stringify({location:remote?'remote':'local',items:rows},null,2));process.exit(0);
}
if(!['post','comment','user','report'].includes(kind)||!/^[a-f0-9-]{36}$/.test(id??'')||flags.some(flag=>flag!=='--remote')) throw new Error('Use an allowed type and UUID.');
const qid=`'${id}'`;
const escape=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
if(action==='review') {
  const statements={post:`SELECT p.id,p.author_id,p.payload,p.photo_base64,p.moderation_status,u.nickname FROM posts p JOIN users u ON u.id=p.author_id WHERE p.id=${qid}`,comment:`SELECT id,post_id,author_id,text,moderation_status FROM comments WHERE id=${qid}`,user:`SELECT id,nickname,public_nickname,suspended FROM users WHERE id=${qid}`,report:`SELECT id,target_type,target_id,reason,status,created_at FROM reports WHERE id=${qid}`};
  const rows=sql(statements[kind]);if(rows.length!==1)throw new Error('Item not found');
  const row=rows[0];const photo=row.photo_base64;delete row.photo_base64;
  let source='';if(row.payload){row.payload=JSON.parse(row.payload);const u=row.payload.sourcePhotoURL; if(typeof u==='string'&&new URL(u).protocol==='https:')source=`<p>Archive reference: <a href="${escape(u)}">open original credited source photograph</a></p>`;}
  const image=photo?`<img alt="Pending nature submission for moderator review" src="data:image/jpeg;base64,${photo}" style="max-width:100%;max-height:70vh">`:'';
  const directory=fileURLToPath(new URL('../../.local/moderation/',import.meta.url));await fs.mkdir(directory,{recursive:true});
  const destination=path.join(directory,`${kind}-${id}.html`);
  await fs.writeFile(destination,`<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'"><title>Private moderation review</title><body style="font:16px/1.5 system-ui;max-width:850px;margin:30px auto;padding:20px"><h1>Private ${escape(kind)} moderation review</h1><p>Review identity, nature relevance, photo rights/source credits, privacy, sexual/violent content, harassment/hate, threats and spam. Do not approve if uncertain. This file contains unpublished user content; do not share or include it in a source ZIP.</p>${image}${source}<pre style="white-space:pre-wrap">${escape(JSON.stringify(row,null,2))}</pre></body>`);
  console.log(`Private review saved: ${destination}`);process.exit(0);
}
let statement;
if(action==='approve'&&['post','comment'].includes(kind))statement=`UPDATE ${kind==='post'?'posts':'comments'} SET moderation_status='approved' WHERE id=${qid} AND moderation_status='pending'`;
if(action==='approve'&&kind==='user')statement=`UPDATE users SET public_nickname=nickname WHERE id=${qid} AND suspended=0`;
if(action==='reject'&&['post','comment'].includes(kind))statement=`UPDATE ${kind==='post'?'posts':'comments'} SET moderation_status='rejected' WHERE id=${qid}`;
if(['suspend','restore'].includes(action)&&kind==='user')statement=`UPDATE users SET suspended=${action==='suspend'?1:0} WHERE id=${qid}`;
if(action==='resolve'&&kind==='report')statement=`UPDATE reports SET status='resolved' WHERE id=${qid}`;
if(!statement)throw new Error('Unsupported action/type. See --help.');
sql(statement);
console.log(`Completed ${action} ${kind} in ${remote?'remote':'local'} D1. No email or push notification was sent.`);
