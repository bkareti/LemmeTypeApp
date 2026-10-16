# 0011 — Model downloads, verification, and removal

- Status: Accepted
- Date: 2026-10-16
- Story: E2-S4

## Context

The optional local model (E2-S3) is too large to ship in the app. Downloading
it is LemmeType's first network access, so it must be narrow, explicit, and
verifiable, and it must not weaken the network-silent dictation promise.

## Decision

- **Catalog in code**: `ModelCatalog` (Domain) lists every model with its file
  URLs, byte sizes, lowercase SHA-256 digests, languages, licence, and hardware
  requirement. Sources and digests are never read from user input, a remote
  index, or redirects. Changing them is a reviewed code change.
- **Allowlisted HTTPS only**: `ModelCatalog.isTrustedSource` accepts `https`
  URLs on `ModelCatalog.allowedHosts` (`huggingface.co`). The system follows
  that host's redirects to its CDN; integrity rests on the digest, not the host.
- **One network module**: `ModelAssets` is the only module allowed to use
  `URLSession` (the `no_network_apis` SwiftLint rule is disabled only in
  `URLSessionModelDownloader.swift`). It uses an ephemeral session with no
  cookies, cache, or credential storage, and is never called during dictation.
- **Explicit consent**: `install` requires a `ModelDownloadConsent` whose byte
  count matches the catalog, created by the confirmation UI after showing the
  download size and storage use (E2-S9).
- **Free space** must cover the download plus 10% (minimum 100 MB); otherwise the
  download does not start and the required space is reported.
- **Staging**: files download into `Models/Staging/<asset>/`, with
  `URLSession` resume data saved when paused or interrupted. A stale resume
  token triggers one fresh restart. Staged files are never used.
- **Verification**: size, then streaming SHA-256 (CryptoKit). A mismatch
  deletes the staged file and reports `model.digest-mismatch` /
  `model.size-mismatch`, which the user can retry.
- **Activation**: verified files move to `Models/<asset>/<version>/` with a
  `.verified` marker; older versions and unknown staging folders are removed
  at launch.
- **Removal** deletes only `Models/<asset>/` and its staging folder; preferences
  are untouched. Engines depending on the model report `assetsMissing`, and
  Automatic engine selection falls back to an available engine (E2-S9).
- **Diagnostics** record asset id, outcome, and error identifier only.

## Consequences

- A new model needs a catalog entry with its digest computed from the exact
  upstream file and a licence review (see ADR 0012 for whisper.cpp).
- Downloads cannot be "pushed" to users: nothing downloads without consent.
