# Nature Relay community API

Deployed origin: https://nature-relay-community.midori-lab.workers.dev

This is the native app's small public demo API. Cloudflare Workers handles requests and the bound D1 database stores anonymous users, posts, JPEG photos, comments, and follows. No R2, Workers AI, paid service, billing upgrade, or automatic paid fallback is configured.

## Run locally

```sh
npm ci
npm run types
npm run check
npx wrangler d1 migrations apply nature-relay-community-db --local
npx wrangler dev --local
```

The repository contains placeholder deployment identifiers and `support@example.com`. Before deploying your own instance, create your own D1 database, set its binding ID in `wrangler.jsonc`, configure a real support address in `src/public-pages.ts`, and use your own Cloudflare authentication. Do not reuse the demo operator's account. Keep API keys in Worker Secrets, never in the repository or iOS bundle. The native bundle points to the public demonstration API; change `NatureRelayConfig.json` to your own origin when forking.

## API

`POST /v1/session` accepts `{ "nickname": "Name" }` and returns `{ "token", "user" }`. Browsing the public feed, post details, photos, and comments does not require or create an identity. Following-only feeds, user search, personal settings, identification, and mutations require `Authorization: Bearer <token>`. A supplied token is always validated, including on public routes. A 64-character random token is returned once and only its SHA-256 digest is stored in D1. The app stores the original token in device-only Keychain. This is a device identity, without a password, recovery flow, or cross-device account synchronization.

- `GET /health`: service status and whether an identification key is configured; no key value.
- `GET /v1/me`, `PATCH /v1/me`: read or rename this device's identity.
- `GET /v1/posts?following=1&cursor=...`: at most 50 posts, optionally followed authors only; response includes `nextCursor`.
- `POST /v1/posts`: `CommunityPublishRequest` from `SocialAPIService.swift`; retries for an author's `clientObservationID` return the same post.
- `GET /v1/posts/:id`, `DELETE /v1/posts/:id`: read a post; deletion requires its owner and cascades its comments and photo.
- `GET /v1/media/:id`: the public JPEG attached to a shared post.
- `GET /v1/posts/:id/comments`, `POST /v1/posts/:id/comments`: read up to 50 comments or add one.
- `GET /v1/users?query=...`: search up to 50 other users.
- `POST /v1/follows/:userID`, `DELETE /v1/follows/:userID`: follow or unfollow another identity.

Fresh uploads require a JPEG of at most 128,000 bytes, encoded as base64. The app redraws/downsizes the photo to remove EXIF/GPS before the user explicitly publishes it. Shared coordinates are rounded again on the server to 0.01 degree. Reference posts require HTTPS links to an iNaturalist observation and its original photo host, preserving author and attribution. The server never downloads an arbitrary submitted URL.

## Plant identification

`POST /v1/identify` requires the same session token and a raw `image/jpeg` body of at most 1.5 MiB. `X-NatureRelay-Language: ja` requests Japanese common names. The iOS service redraws/resizes the photo before this explicit request. The Worker passes the pixels to Pl@ntNet's `/v2/identify/all` route and returns:

```json
{
  "provider": "plantnet",
  "candidates": [
    {"scientificName": "Species name", "commonNames": ["Common name"], "score": 0.75}
  ],
  "remainingDailyRequests": 490
}
```

Candidates are suggestions ranked by the provider score, not confirmed species or guaranteed probabilities. The remaining allowance belongs to the shared provider account. No image is saved to D1 by identification. Photo filename, journal text, and location are not sent to Pl@ntNet. There is no retry or paid provider fallback.

The optional `PLANTNET_API_KEY` must be provisioned only as a Worker Secret after the required user authorization. Until then, the route returns HTTP 503 and makes no provider call. There is no key in this repository or bundle. Do not pipe a secret through `echo`, put it in a command argument, print it, or save it in a checked-in file.

Pl@ntNet's [free plan](https://my.plantnet.org/pricing) lists 500 identifications/day. This Worker stops at 450 attempts/day globally and 10/day per session, leaving a margin; requests elsewhere on the same provider account share that allowance. A provider quota rejection also fails closed. The app must display Pl@ntNet attribution when connected. See the official [single-species API](https://my.plantnet.org/doc/api/identify) and [input guidance](https://my.plantnet.org/doc/getting-started/faq).

## Demo limits and verification

Application caps are 5,000 API requests/day globally, 1,000/day per IP hash, 500/day per session, 150 write attempts/day per session, and 30 new sessions/day per IP hash. Limits are persisted atomically in D1 with 48-hour retention; plain IP addresses are not stored. The free demo also caps the database at 500 users, 1,000 posts, 50 posts per user, 5,000 comments, 100 comments per post, and 5,000 follow relationships. Atomic SQL triggers enforce storage counts. All user values use prepared SQL parameters. Errors do not relay internal query details, photos, tokens, or upstream URLs. Request/body logging is disabled.

These are this demo's caps, separate from Cloudflare's account-wide free quotas. No upgrade is attempted when either is exhausted. Cloudflare documents [Workers Free limits](https://developers.cloudflare.com/workers/platform/pricing/) and [D1 Free limits and quota rejection](https://developers.cloudflare.com/d1/platform/pricing/). Existing account usage also consumes those shared allowances.

```sh
NATURE_RELAY_TEST_URL=https://nature-relay-community.midori-lab.workers.dev npm run test:live
```

Each live test run uses two real anonymous sessions, a clearly synthetic temporary photo, and real persistent API operations. It verifies authentication, post idempotency, cross-user comments, follows, source validation, ownership, missing-key identification failure, and deletion. It removes its post/photo/comments/follows. Each run leaves two QA user rows, without their original tokens being saved or printed. Aggregate evidence is saved in `tests/live-verification.json`. This does not verify live Pl@ntNet inference or the native app's UI.
