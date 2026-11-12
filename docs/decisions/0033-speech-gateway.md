# 0033. Speech gateway: one server that holds the speech provider keys

- Status: Proposed. The maintainer confirms the repository, language, and hosting below before E13-S1 is merged.
- Date: 2026-11-12
- Stories: [Epic 13](../backlog/epic-13-paid-launch.md), E13-S1 ([#152](https://github.com/bkareti/LemmeTypeApp/issues/152)) and E13-S2 ([#153](https://github.com/bkareti/LemmeTypeApp/issues/153))
- Updates: [ADR 0031](0031-cloud-speech-provider.md), which proposed a relay for the public release

## Context

Cloud speech today needs each user's own Sarvam key. That does not work for a public App Store
launch. A key built into the app can be extracted (ADR 0031). The maintainer wants users to turn on
Cloud and use it with no setup, to be able to change speech provider later, and to reuse the same
server for MeetQyl.

## Decision

- **A separate gateway service**, in its own repository (`speech-gateway`, private), not in this one.
  MeetQyl must not depend on the LemmeType repository.
- **TypeScript on Node 22**, Fastify. Small, easy to test without a network, and the App Store
  Server Library for E13-S2 is available for Node.
- **Hosting (default): Google Cloud Run in `asia-south1` (Mumbai)** with Secret Manager. It scales to
  zero, keeps keys out of the image, and is close to Sarvam. Nothing in the code depends on this
  vendor: it is a container that listens on `PORT`, so another host is a deploy-file change.
- **API `v1`**, described by `openapi.yaml` in the gateway repository: `GET /v1/health`,
  `GET /v1/capabilities`, `POST /v1/speech/transcriptions` (one 16 kHz mono 16-bit WAV, a `task`,
  and a `language`). One error shape with the codes `bad_request`, `unauthorized`,
  `subscription_required`, `rate_limited`, `quota_exceeded`, `unsupported_language`,
  `audio_invalid`, `audio_too_long`, `provider_busy`, `provider_unavailable`, `service_unavailable`.
- **Per-app configuration, not code** (`apps.yaml`): languages, tasks, clip limit, consent version,
  and which provider serves each language and task. The app comes from the verified token, never from
  a header the caller picks.
- **Providers behind one interface** (`SpeechProvider`) with a contract test every provider must pass.
  `SarvamProvider` mirrors the app's current adapter. Changing the provider for a language is one
  line in `apps.yaml`.
- **Nothing stored.** Audio and text live in memory for one request. No disk, queue, cache, or log.
  Logs hold a request id, app, route, status, duration, byte count, provider time, and error code.
- **Consent follows the provider list.** The gateway returns `consentVersion` from `/v1/capabilities`.
  A provider swap inside the approved list (same country, same terms) keeps the number. Anything else
  raises it, and apps ask for consent again before the next Cloud use (E13-S3).
- **Access is a separate part.** E13-S1 ships a placeholder gate (static test tokens, never in
  production). E13-S2 replaces it with Apple signed-transaction checks, quotas, and cost caps. Until
  then production answers `/v1/health` and refuses everything else.

## Alternatives considered

| Option | Why not |
|---|---|
| Put the server in this repository | MeetQyl would depend on the LemmeType repository and its release rhythm |
| Firebase or another all-in-one backend | The maintainer closed the Firebase account issue (#142); the gateway needs no accounts |
| Cloudflare Workers | Good fit for a proxy, but Apple's server library and larger uploads are simpler on Node in a container |
| A key encrypted inside the app | The app must decrypt it to use it, so anyone with a copy can extract it (ADR 0031) |
| Keep each user's own key | Too technical for a public release |

## Consequences

- LemmeType audio for Cloud now passes through a server we run before the provider. The app's consent,
  privacy policy, and App Store privacy answers must say so (E13-S3, E13-S8).
- We pay for hosting and for the provider. E13-S2 limits how much each person can use.
- A second party (the host) can see traffic in transit; audio is never stored by us.
- Sarvam's account allows 60 requests a minute for all users together (ADR 0031). E13-S2 adds a
  global limiter below that.
- The ADR 0031 launch gate "How keys reach the app" is closed by the gateway once E13-S2 and E13-S3 land.
  The gates on Sarvam's data terms stay open.
