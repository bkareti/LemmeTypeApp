# 0034. StoreKit subscription and the free trial

- Status: Proposed. The maintainer confirms the product id before the first App Store Connect save.
- Date: 2026-11-12
- Stories: [E13-S4](../backlog/epic-13-paid-launch.md), [E13-S5](../backlog/epic-13-paid-launch.md)
- Related: [ADR 0033](0033-speech-gateway.md) (the gateway checks the same signed transaction)

## Context

LemmeType is sold as one monthly subscription with a 7-day free trial, $1.99 a month, covering Local and
Cloud. There is no account (the Firebase issue #142 was closed), so the Apple ID and StoreKit identify the
subscriber. The gateway already accepts StoreKit 2 signed transactions (E13-S2).

## Decision

- **One auto-renewing monthly product** in one subscription group, id `com.lemmetype.LemmeType.iOS.pro.monthly`.
  It cannot be reused or renamed once saved in App Store Connect, so it is confirmed before then. Base price
  $1.99 USD (Apple's equivalent prices elsewhere), introductory offer free for one week, new subscribers only,
  Family Sharing off.
- **StoreKit 2 only.** A new module, `Subscriptions` (depends on Domain and Support), holds the one type that
  imports StoreKit, `StoreKitSubscriptionService`. It implements two Domain protocols: `SubscriptionProviding`
  (purchase, restore, state, product, manage) and `SubscriptionProofProviding` (the signed transaction for the
  gateway, from E13-S3). The UI module never imports StoreKit.
- **Nothing about price or trial is written in the app.** The price, the period, the trial length, and whether
  this Apple ID can still get the trial are read from StoreKit and shown as they come.
- **Unverified means no subscription.** Only a `.verified` transaction grants anything; an unverified one is
  reported and ignored.
- **State is derived, not stored.** `SubscriptionState` is computed from `Product.SubscriptionInfo.status` and
  `Transaction.currentEntitlements` at launch, after a purchase or restore, and on `Transaction.updates`. StoreKit
  keeps verified transactions on the device, so the state works offline.
- **A local StoreKit configuration file** (`Config/LemmeType.storekit`) mirrors the product for Xcode runs and
  for tests with `SKTestSession`.
- **The paywall can always be closed.** Settings, export, delete, and the privacy policy stay reachable
  (E13-S5 decides what an expired person may still do).

## Consequences

- A new module and a new network-free edge: `Subscriptions` imports StoreKit (and UIKit on iPhone, to find the
  window that shows Apple's manage-subscriptions sheet). It is listed in the module table.
- The Mac app is not sold through StoreKit (it is not on the Mac App Store), so the module is built for iPhone
  and iPad use and compiles on macOS only so the package builds there.
- The product, price, and offer must also exist in App Store Connect before a real purchase works. The Paid
  Applications Agreement, tax, and banking forms are the maintainer's to complete (`docs/release/app-store.md`).
- Tests that need StoreKit run in the iPhone app's unit-test target (`make test-ios`), because StoreKit's test
  session needs the Simulator.
