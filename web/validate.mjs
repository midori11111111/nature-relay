import { readFile, stat } from 'node:fs/promises';
import assert from 'node:assert/strict';
const rows=JSON.parse(await readFile(new URL('dist/data/catalog.json',import.meta.url)));
const seeds=JSON.parse(await readFile(new URL('dist/data/starter.json',import.meta.url)));
assert.equal(rows.length,100);
assert.equal(new Set(rows.map(x=>x.scientificName)).size,100);
assert.equal(seeds.length,20);
assert.equal(new Set(seeds).size,20);
for(const row of rows){
 assert(['cc-by','cc0'].includes(row.photoLicense));
 assert(row.sourceAttribution && row.sourceURL.startsWith('https://www.inaturalist.org/observations/'));
 assert(row.latitude>=-90 && row.latitude<=90 && row.longitude>=-180 && row.longitude<=180);
 assert(Math.abs(row.latitude*100-Math.round(row.latitude*100))<1e-8);
 assert(Math.abs(row.longitude*100-Math.round(row.longitude*100))<1e-8);
 for(const key of ['image','character']){
  assert(!row[key].includes('..') && row[key].startsWith('assets/'));
  assert((await stat(new URL('dist/'+row[key],import.meta.url))).size>1000);
 }
}
for(const id of seeds)assert(rows.some(x=>x.id===id));
for(const f of ['index.html','app.js','styles.css','assets/logo.png','assets/icon.png','vendor/leaflet.js','vendor/leaflet.css','credits.html'])assert((await stat(new URL('dist/'+f,import.meta.url))).size>0);
console.log('PASS: 100 unique species; 20 starter entries; licensed source metadata; rounded coordinates; 200 local image files; required app files.');
