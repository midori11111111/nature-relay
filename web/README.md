# Nature Relay — Web

Interactive browser version of the Nature Relay iPhone app. Explore 100 credited California archive observations on a map, open their real photographs and illustrated companions, save discoveries to a Journal, and add your own photograph with a manually chosen species.

## Run

```sh
python3 -m http.server 4173 --directory dist
```

Open http://localhost:4173. No build step, paid API, account, or secret is required. The Leaflet library and all character/photo assets are bundled locally; OpenStreetMap supplies online map tiles.

The initial Journal contains 20 starter examples. Personal photographs stay in this browser's storage. They are not uploaded. Clearing browser storage removes local entries; the native iPhone Journal is separate and does not synchronize with this website. Sharing an archive discovery shares its public species page, not the private Journal.

Species selection is manual. The illustrated companions were made with AI during development and are looked up by species; this web release does not identify arbitrary species or generate new artwork at runtime. Archive records retain their original observer, observation date, photo license and approximate California area; they do not claim that a species is currently at De Anza.

## Credits

See `dist/credits.html` for all 100 source photographs and their individual CC BY 4.0 / CC0 links. Character artworks are original project illustrations. Leaflet 1.9.4's BSD-2-Clause license is bundled in `dist/vendor/LEAFLET-LICENSE.txt`. Map data © OpenStreetMap contributors.
