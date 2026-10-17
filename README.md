# Nature Relay

Turn everyday nature into companions to collect and share. Nature Relay helps students notice the plants and animals around them, remember their discoveries, and start conversations with friends. Built for De Anza Hacks 5.0, October 16–17, 2026.

Team: Tomoki, Gina, Apryl and Rion.

## Try it

Public browser app: [Nature Relay](https://midori11111111.github.io/nature-relay/).

The browser app is in `web/dist` and needs no build step or API key:

```sh
python3 -m http.server 4173 --directory web/dist
```

Open http://localhost:4173. Explore the character map, open a species to see its original photograph and credits, collect it in Journal, or add your own photo with a manually selected species. Twenty labeled starter examples demonstrate the Journal. Browser records stay in local storage and do not synchronize with the iPhone. Online map tiles require an internet connection.

## iPhone app

Requires macOS, Xcode and an iOS 17+ Simulator/device. Generate the portable project, then open it in Xcode:

```sh
python3 tools/genproj.py
open NatureRelay.xcodeproj
```

Choose the NatureRelay scheme and an iPhone Simulator. For a physical device, supply your own signing team with `TEAM_ID=YOUR_TEAM_ID python3 tools/genproj.py`. No signing certificates, provisioning profiles or developer credentials are included.

The native app includes a map, 100 species companions, photo import, selected-photo date/location metadata when available, manual species selection, and a persistent private Journal. Apple's pretrained MobileNet supplies broad category suggestions; it does not establish an exact species. Camera subject highlighting is implemented; the edited camera-to-character demonstration is a concept visualization rather than evidence of automatic identification. Optional community posts/comments/follows use a moderated API. Saving a private Journal entry does not publish it.

## Community backend

See [backend/README.md](backend/README.md) and [backend/MODERATION.md](backend/MODERATION.md). To run an isolated local instance:

```sh
cd backend
npm ci
npm run types
npm run check
npx wrangler d1 migrations apply nature-relay-community-db --local
npx wrangler dev --local
```

Deployment identifiers and the contact address are placeholders in this submission checkout. Configure your own Cloudflare account, database, support address and application API origin before deploying. Never commit provider secrets.

## Current limits

Species selection is manual. Companions were generated during development and are retrieved by species; this release does not generate new artwork at runtime. Pl@ntNet integration code exists but no provider key is connected. Personal Journals are device/browser local. Community submissions require human moderation. A shared campus completion challenge is a future direction. The California archive contains historical records from several regions, rather than a verified list of organisms currently on campus.

## Sources and acknowledgments

- The 100 unmodified California source photographs retain their observation, date, approximate area, photographer and individual license. There are 68 CC BY 4.0 and 32 CC0 photographs. Full credits: [Resources/CaliforniaCatalog/README.md](Resources/CaliforniaCatalog/README.md), the catalog manifest and the web credits page. Preserve attribution when reusing them.
- AI coding assistance and the built-in image generation tool were used during development. Species companion prompts/provenance are in [Resources/CharacterDesignsA](Resources/CharacterDesignsA); these illustrations are artistic interpretations, not identification evidence. This uses existing AI tools and pretrained weights, rather than a newly trained model.
- MobileNet V2 is a pre-existing model distributed through Apple's Core ML model gallery. Attribution and the TensorFlow Apache 2.0 license accompany the compiled model: [Models/README.md](Models/README.md).
- Fallback graphics include credited Twemoji adaptations under CC BY 4.0 and original CC0 vectors: [Resources/character-asset-credits.json](Resources/character-asset-credits.json).
- The native app uses Apple's SwiftUI, MapKit, Vision, Core ML, Photos and AVFoundation frameworks. The backend uses Cloudflare Workers/D1, Wrangler and TypeScript. The web version uses Leaflet and OpenStreetMap; their notices travel with its files. These are pre-existing third-party tools.

Optional development sample photographs, private phone data, credentials, build products and raw demonstration footage are deliberately absent. Normal capture, map and Journal flows do not depend on those optional samples. No blanket code or artwork license is granted by this repository; third-party assets retain their stated licenses.

## Hackathon submission

The [official event page](https://dahacks5.devpost.com/) requires a publicly accessible source repository and final submission through Devpost. A GitHub upload alone is not the final submission. Include the project description, screenshots, technologies, team contributions, demo video (2–3 minutes recommended), and a live demo URL when available. The [official schedule](https://guide.deanzahacks.com/schedule) sets the deadline at October 17, 2026, 2:00 PM PDT. See also the [submission guide](https://guide.deanzahacks.com/guide).
