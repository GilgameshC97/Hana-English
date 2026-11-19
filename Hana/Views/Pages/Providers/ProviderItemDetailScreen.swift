import AVKit
import SwiftUI

/// Generic detail + playback screen for items from any `VideoProvider`
/// (Jellyfin today). Hanime items keep using `VideoDetailScreen`, which has
/// site-specific features (comments, likes, playlists).
struct ProviderItemDetailScreen: View {
    private struct Loaded {
        let detail: MediaItemDetail
        let episodes: [MediaEpisode]
        let streams: [StreamSource]
        let markers: [Marker]
    }

    let ref: MediaItemRef

    @Environment(HanaServices.self) private var services
    @AppStorage(HanaSettingsKey.blurThumbnails) private var blurThumbnails = false
    @State private var state: LoadableState<Loaded> = .idle
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var selectedStreamID: String?

    private var registry: ProviderRegistry { services.providerRegistry }

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView("Unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
            case .loaded(let loaded):
                content(loaded)
            }
        }
        .navigationTitle(loadedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ref) { await load() }
        .onDisappear { stopPlayback() }
    }

    private var loadedTitle: String {
        if case .loaded(let loaded) = state { return loaded.detail.title }
        return ""
    }

    @ViewBuilder
    private func content(_ loaded: Loaded) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                playerArea(loaded)

                VStack(alignment: .leading, spacing: 6) {
                    Text(loaded.detail.title).font(.title2.bold())
                    if let alternate = loaded.detail.alternateTitle {
                        Text(alternate).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let subtitle = loaded.detail.summary.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if loaded.streams.count > 1 {
                    Picker("Playback Resolution", selection: Binding(
                        get: { selectedStreamID ?? loaded.streams.first?.id ?? "" },
                        set: { selectedStreamID = $0 }
                    )) {
                        ForEach(loaded.streams) { stream in Text(stream.quality).tag(stream.id) }
                    }
                    .pickerStyle(.segmented)
                }

                if !loaded.markers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chapters").font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(loaded.markers) { marker in
                                    Button {
                                        seek(to: marker.seconds, loaded: loaded)
                                    } label: {
                                        Label(marker.title ?? Self.clock(marker.seconds), systemImage: "bookmark")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }

                if let overview = loaded.detail.overview, !overview.isEmpty {
                    Text(overview).font(.body)
                }

                if !loaded.detail.tags.isEmpty {
                    Text(loaded.detail.tags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !loaded.episodes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Episodes").font(.headline)
                        ForEach(loaded.episodes) { episode in
                            NavigationLink(value: HanaRoute.providerItem(episode.ref)) {
                                HStack {
                                    Text("\(episode.episodeNumber.map { "\($0). " } ?? "")\(episode.title)")
                                    Spacer()
                                    if episode.isCurrent { Image(systemName: "play.fill") }
                                    if episode.isPlayed { Image(systemName: "checkmark.circle") }
                                }
                                .padding(8)
                                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !loaded.detail.related.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Related").font(.headline)
                        ForEach(loaded.detail.related) { item in
                            NavigationLink(value: HanaRoute.providerItem(item.ref)) {
                                Text(item.title).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func playerArea(_ loaded: Loaded) -> some View {
        if let player {
            VideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            ZStack {
                AsyncImage(url: loaded.detail.summary.coverURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.fill.tertiary)
                }
                .blur(radius: blurThumbnails ? 24 : 0)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let stream = selectedStream(in: loaded) {
                    Button {
                        startPlayback(stream, loaded: loaded, at: loaded.detail.summary.resumePositionSeconds ?? 0)
                    } label: {
                        Label(
                            (loaded.detail.summary.resumePositionSeconds ?? 0) > 1 ? "Resume" : "Play",
                            systemImage: "play.fill"
                        )
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if loaded.detail.summary.kind != .series {
                    Text("No playable stream").font(.caption).padding(8).background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
    }

    private func selectedStream(in loaded: Loaded) -> StreamSource? {
        loaded.streams.first { $0.id == selectedStreamID } ?? loaded.streams.first
    }

    // MARK: Loading

    private func load() async {
        stopPlayback()
        state = .loading
        do {
            let detail = try await registry.details(for: ref)
            async let episodes: [MediaEpisode] = (try? await registry.episodes(for: ref)) ?? []
            async let markers: [Marker] = (try? await registry.markers(for: ref)) ?? []
            let streams = detail.summary.kind == .series ? [] : try await registry.streams(for: ref)
            state = .loaded(Loaded(detail: detail, episodes: await episodes, streams: streams, markers: await markers))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Playback

    private func startPlayback(_ stream: StreamSource, loaded: Loaded, at seconds: TimeInterval) {
        stopPlayback()
        let asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        if seconds > 1 {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        let ref = ref
        let registry = registry
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 10, preferredTimescale: 1),
            queue: .main
        ) { [weak player] time in
            let paused = (player?.rate ?? 0) == 0
            Task { @MainActor in
                await registry.reportPlayback(PlaybackProgress(ref: ref, positionSeconds: time.seconds, isPaused: paused, event: .progress))
            }
        }
        self.player = player
        player.play()
        Task { await registry.reportPlayback(PlaybackProgress(ref: ref, positionSeconds: seconds, isPaused: false, event: .started)) }
    }

    private func seek(to seconds: TimeInterval, loaded: Loaded) {
        if let player {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else if let stream = selectedStream(in: loaded) {
            startPlayback(stream, loaded: loaded, at: seconds)
        }
    }

    private func stopPlayback() {
        guard let player else { return }
        let position = player.currentTime().seconds
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        self.player = nil
        let ref = ref
        let registry = registry
        Task {
            await registry.reportPlayback(PlaybackProgress(
                ref: ref,
                positionSeconds: position.isFinite ? position : 0,
                isPaused: true,
                event: .stopped
            ))
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
