import Foundation
import SwiftData

// SwiftData versioning for the provider refactor.
//
// Status: V1 describes the store exactly as it ships today. It is NOT yet
// passed to the ModelContainer in HanaApp.swift, so behavior is unchanged.
//
// Why no V2 migration is needed for existing rows:
// `MediaItemRef.storageKey` is the bare `videoCode` for the built-in Hanime
// provider (fixed ID `ProviderID.builtInHanime`). Every existing
// `videoCode` value is already a valid storage key, so current rows need no
// rewrite.
//
// When Jellyfin items should appear in history/favorites/watch later:
//   1. Add `HanaSchemaV2` whose record types store `itemKey: String`
//      (= MediaItemRef.storageKey, `@Attribute(.unique)`), plus optional
//      `providerKind: String?` and `title`/`coverURL` snapshots so rows render
//      without a network call.
//   2. Use a *lightweight* stage, renaming with
//      `@Attribute(originalName: "videoCode") var itemKey: String`, so the
//      values carry over unchanged. Lightweight stages are needed because the
//      store syncs through CloudKit (`cloudKitDatabase: .automatic`): CloudKit
//      schemas are add-only, so custom stages that delete or retype
//      attributes would break sync for older installs.
//   3. Keep `videoCode` as a computed property
//      (`MediaItemRef(storageKey: itemKey)?.itemID`) so existing Hanime screens
//      compile unchanged.
//   4. Pass `migrationPlan: HanaMigrationPlan.self` to `ModelContainer`.
//   5. PlaylistItemRecord / DownloadQueueRecord build ids from `videoCode`;
//      keep the same format with `itemKey` substituted.
//   6. Test on a device with real iCloud data before release; CloudKit
//      schema changes must also be deployed to production in the CloudKit
//      console.

nonisolated enum HanaSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            WatchHistoryRecord.self,
            SearchHistoryRecord.self,
            AdvancedSearchHistoryRecord.self,
            FavoriteVideoRecord.self,
            WatchLaterRecord.self,
            PlaylistRecord.self,
            PlaylistItemRecord.self,
            DownloadQueueRecord.self,
            DownloadGroupRecord.self,
            HKeyframeRecord.self,
        ]
    }
}

nonisolated enum HanaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HanaSchemaV1.self] }

    // Add `.lightweight(fromVersion: HanaSchemaV1.self, toVersion: HanaSchemaV2.self)`
    // here together with HanaSchemaV2.
    static var stages: [MigrationStage] { [] }
}
