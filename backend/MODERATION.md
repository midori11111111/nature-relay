# Human moderation during the beta

New post photos/text, comments, and nickname changes require developer review. Nothing becomes approved just because time passes. Existing labeled demonstration content was retained by the additive migration. A new post's pending photo is available only with its owner's credential; its API response deliberately omits a public photo URL.

The developer must check the pending/report queue and the published support email during the invited beta. There is no automatic email/push notification, scheduled monitor, or paid moderation provider. Do not describe the service as having automatic image classification or guaranteed response times. The public contact is `support@example.com`.

Use the developer's existing Wrangler authorization. The helper defaults to the isolated local test database; `--remote` explicitly selects the existing production database. It never deletes users/posts and never exposes session token hashes. Do not put private review HTML in a source package, screenshots, or public repository.

```sh
# List only pending item identifiers and open reports.
node tools/moderation.mjs queue --remote

# Inspect an exact queued item; replace the UUID with a reviewed queue entry.
node tools/moderation.mjs review post 00000000-0000-0000-0000-000000000000 --remote

# After reviewing its private HTML/photo/text/credits, deliberately approve or reject it.
node tools/moderation.mjs approve post 00000000-0000-0000-0000-000000000000 --remote
node tools/moderation.mjs reject post 00000000-0000-0000-0000-000000000000 --remote
```

`review` writes to the repository's ignored `.local/moderation/`. Review nature relevance, sexual/violent content, harassment/hate, threats, personal information, spam, photo rights, and complete archive attribution. For an archive reference, inspect the original credited source photograph through its source link. Do not approve uncertain material. Approve a pending nickname separately with `approve user UUID --remote`; until then the public nickname remains the previously approved value or “Nature observer”.

For a report, run `review report UUID --remote`, then inspect the indicated target. Reject/remove public visibility with `reject post|comment UUID --remote`; suspend abusive access with `suspend user UUID --remote`. Suspension hides their posts/comments and rejects authenticated interactions, while preserving their right to delete the account. Use `restore user` only after deliberate review. `resolve report UUID --remote` changes its queue status, without deleting the report. A new report about that same target reopens it.

Profile deletion is available only to the authenticated profile owner through `DELETE /v1/me` with `{"confirmation":"DELETE"}`. It cascades active profile-associated public content/relationships/reports and removes session-linked quota records. No developer tool ran this against existing production users. Daily IP-derived abuse counters and provider backups have separate retention. Blocking is reciprocal for authenticated interactions; approved content remains public to unauthenticated readers.

Verification:

```sh
npm run check
npx wrangler d1 migrations apply nature-relay-community-db --local --persist-to .wrangler/moderation-local
npx wrangler dev --local --port 8791 --persist-to .wrangler/moderation-local --compatibility-date 2026-08-06
node tests/moderation-local.mjs
NATURE_RELAY_TEST_URL=https://nature-relay-community.midori-lab.workers.dev npm run test:live
```

The local compatibility override is needed by the installed workerd binary and does not alter the production compatibility date. The local test refuses non-loopback origins and uses only its isolated database. The current live smoke is GET-only and creates no test identities or posts. Historical `live-verification.json` describes the earlier, pre-moderation write suite; it is not the current suite.
