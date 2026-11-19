# VideoProvider refactor

This branch (`feature/video-provider`) adds a provider layer so Hana can play
from more than one backend. The built-in hanime1.me scraper becomes one
provider, and a self-hosted Jellyfin server is the first new one.

## Layout

| Path | What |
| --- | --- |
| `Hana/Providers/Core/` | Foundation-only, `Sendable` core. Built by the app target (synchronized group) **and** by `Package.swift` as `HanaProviderCore` for tests. |
| `…/ProviderModels.swift` | `ProviderID`, `ProviderKind`, `MediaItemRef` (provider + itemID, with `storageKey`), `MediaItemSummary/Detail`, `MediaEpisode`, `StreamSource` (mp4/HLS + headers), `Marker`, `FilterSet`, `SearchQuery`, `PlaybackProgress`. |
| `…/VideoProvider.swift` | `VideoProvider` protocol + `VideoProviderError`. |
| `…/ContentSafetyPolicy.swift` | A blocklist that can't be turned off (see below). |
| `…/ProviderRegistry.swift` | `@MainActor @Observable` registry. Persists `hana.providers.v1`, migrates `hana.sources.v1`, and applies the policy to every result. |
| `…/ProviderSourceConfiguration.swift` | Stored source config, auth method, Keychain account names, legacy decoder, and `ProviderServerURL`. |
| `…/SecretStore.swift` | `HanaSecretStore`, `KeychainStore.hana` (service `sh.celia.hana.secrets`, this-device-only), `InMemorySecretStore`. |
| `…/SecretsMigration.swift` | One-time move of UserDefaults secrets into the Keychain. |
| `…/Jellyfin/` | `JellyfinProvider` (actor) + DTOs. |
| `Hana/Providers/Hanime/HanimeProvider.swift` | Adapter over `HanimeRepository`/`HanaHTTPClient` (app-only). |
| `Hana/Providers/App/HanaProviderEnvironment.swift` | Shared registry, provider factory, device ID. |
| `Hana/Services/Hanime/HanimeContentSafety.swift` | Applies the policy to parsed Hanime pages. |
| `Hana/Views/Pages/Providers/ProviderItemDetailScreen.swift` | Generic detail and player screen for provider items (`HanaRoute.providerItem`). |
| `Hana/Models/HanaSchemaVersions.swift` | `HanaSchemaV1` + migration plan sketch (not wired yet). |

## Integration points

- `HanaServices.providerRegistry`: `HanimeProvider` is registered as the built-in provider.
- `HanaSourceManager` is now a facade over the registry, so existing call sites keep working. It adds the `.jellyfin` source type, `setSecret`/`hasSecret`, and playable search results (`itemRef`).
- Settings → Sources: Jellyfin fields (sign-in method, user name, and a SecureField for the API key or password that goes straight to the Keychain). Link-only sources are labelled.
- Search → "From Enabled Sources": Jellyfin rows navigate to `ProviderItemDetailScreen`. Other rows still open links.
- `HanaApp.init` runs `HanaSecretsMigration` before any manager reads secrets.
- `HanaKeychain` (`save/read/delete/saveData/readData`) now delegates to `KeychainStore.hana`. Items written by older builds without a service are moved on first read.
- `HanaInfo.plist`: adds `NSFaceIDUsageDescription` (Biometric Lock), `NSLocalNetworkUsageDescription`, and `NSAllowsLocalNetworking`, so LAN Jellyfin servers over http work. Internet ATS rules are unchanged.

## Content policy (can't be turned off)

`ContentSafetyPolicy` has no setting or flag. It blocks any item, tag, filter
option, or search query that is minor-coded. It checks substrings in
CJK/Latin after NFKC normalization and lowercasing, and whole words for short
Latin tokens. It is applied in:

- `ProviderRegistry`: every provider's home, search, details, episodes,
  filters, and streams. Detail screens re-check tags before returning streams.
- `HanimeRepository`: home sections and banner, search (a blocked query
  returns nothing), video detail (throws `blockedByContentPolicy`), related
  and series lists, and account/playlist lists.
- `HanimeSearchOptionCatalog`: blocked options are dropped at load time, so
  they never appear in pickers or detail-tag lookups.
- `HanimeSearchCriteria.normalized()`: blocked tags are never sent.
- `tags.json`: Shota, JK, School Swimsuit, and Gothic Lolita are removed.
  `ShippedTagCatalogTests` fails if any of them comes back.

It is deliberately over-inclusive. For example, tags such as "School",
"Teacher Student", and "Young Lady" are also hidden at runtime. Don't add an
opt-out.

## Persistence and migration

- Sources: `hana.sources.v1` → `hana.providers.v1` on first launch. The first
  Hanime entry gets the fixed `ProviderID.builtInHanime`. The old key is left
  in place so a downgrade still works.
- SwiftData: `MediaItemRef.storageKey` for the built-in Hanime provider is the
  bare `videoCode`, so existing rows are already valid keys. The V2 plan
  (lightweight rename to `itemKey`, CloudKit-safe) is in
  `HanaSchemaVersions.swift`.
- Secrets: `hana.hh.*` and the lock PIN (any old UserDefaults spelling) move to the Keychain. Existing Keychain values are never overwritten. The flag is `hana.secrets.migratedToKeychain.v1`.

## Build and test

```sh
swift build
swift test                                   # 28 tests, 5 suites
swift build -Xswiftc -swift-version -Xswiftc 6   # strict Swift 6 check
```

These cover the core only. Open `Hana.xcodeproj` for the app, and run the
`HanaTests` scheme, which includes the updated `HanimeSearchContractTests`.

## Remaining TODOs

- Jellyfin: use `POST /Items/{id}/PlaybackInfo` with a DeviceProfile to pick
  direct play vs. transcode, plus subtitle and audio track selection. The
  current version uses static mp4 with an HLS fallback.
- Add the V2 SwiftData schema so Jellyfin items can be saved to history,
  favorites, watch later, and downloads (downloads are still keyed by `videoCode`).
- Move the main Hanime screens onto `HanimeProvider`/`ProviderRegistry`
  (they still call `HanimeRepository` directly, which is now policy-filtered).
- Add `Tests/HanaProviderCoreTests` to the Xcode test target, or keep running them via SPM in CI.
- Show Jellyfin libraries on Home (`ProviderRegistry.home`) and add a Jellyfin filter UI (`filters`).
- Verify on device: Keychain migration from a real older install, Face ID
  prompt text, LAN permission prompt, and AVPlayer header auth with Jellyfin.
