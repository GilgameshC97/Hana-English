import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SearchScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SearchHistoryRecord.createdAt, order: .reverse) private var searchHistory: [SearchHistoryRecord]
    @Query(sort: \AdvancedSearchHistoryRecord.createdAt, order: .reverse) private var advancedSearchHistory: [AdvancedSearchHistoryRecord]
    private let locksQueryEditing: Bool
    private let lockedQuery: String?
    @State private var criteria: HanimeSearchCriteria
    @State private var state: LoadableState<[HanimeInfo]> = .idle
    @State private var currentPage = 1
    @State private var canLoadMore = false
    @State private var isLoadingMore = false
    @State private var isFilterPresented = false
    @State private var hasLoadedInitialCriteria = false
    @State private var toastMessage: HanaToastMessage?

    init(initialCriteria: HanimeSearchCriteria = .empty, locksQueryEditing: Bool = false) {
        let normalizedCriteria = initialCriteria.normalized()
        self.locksQueryEditing = locksQueryEditing
        self.lockedQuery = locksQueryEditing ? normalizedCriteria.query.nilIfEmpty : nil
        _criteria = State(initialValue: normalizedCriteria)
    }

    var body: some View {
        Group {
            switch state {
            case .idle:
                SearchIdleView(histories: Array(advancedSearchHistory.prefix(12))) { history in
                    apply(history)
                } onDelete: { offsets in
                    deleteHistories(at: offsets, from: Array(advancedSearchHistory.prefix(12)))
                }
            case .loading:
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let videos):
                if videos.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if !visibleFilterTags.isEmpty {
                                SearchFilterSummary(tags: visibleFilterTags)
                                    .padding(.horizontal)
                            }

                            let portraitVideos = videos.filter { $0.style == .compact }
                            let normalVideos = videos.filter { $0.style == .normal }

                            if !portraitVideos.isEmpty {
                                SearchVideoGridLinks(videos: portraitVideos) { video in
                                    preloadNextSearchPageIfNeeded(after: video, in: videos)
                                }
                                    .padding(.horizontal)
                            }

                            ForEach(normalVideos) { video in
                                NavigationLink(value: HanaRoute.video(video.videoCode)) {
                                    HanaVideoListRow(info: video)
                                        .padding(10)
                                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                                .onAppear {
                                    preloadNextSearchPageIfNeeded(after: video, in: videos)
                                }
                            }

                            HanaInfiniteScrollTrigger(
                                isActive: canLoadMore,
                                isLoading: isLoadingMore,
                                action: loadNextSearchPageIfNeeded
                            )
                            .padding(.horizontal)
                        }
                        .padding(.vertical, 12)
                    }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label(message, systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Retry") {
                        Task { await search(reset: true) }
                    }
                }
            }
        }
        .navigationTitle(navigationTitleText)
        .hanaNavigationSubtitle(navigationSubtitleText)
        .hanaSearchInput(text: $criteria.query, isEnabled: !locksQueryEditing)
        .onSubmit(of: .search) {
            Task { await search(reset: true) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SearchFilterToolbarButton(
                    isPresented: $isFilterPresented,
                    criteria: $criteria,
                    lockedQuery: lockedQuery
                ) {
                    Task { await search(reset: true) }
                }

                if isShowingSearchHistory {
                    HanaToolbarIconButton(title: "Clear Search History", systemImage: "trash", role: .destructive) {
                        clearAllHistories()
                    }
                }
            }
        }
        .hanaToast($toastMessage)
        .searchFilterSheet(
            isPresented: $isFilterPresented,
            criteria: $criteria,
            lockedQuery: lockedQuery
        ) {
            Task { await search(reset: true) }
        }
        .task {
            guard !hasLoadedInitialCriteria else { return }
            hasLoadedInitialCriteria = true
            if !criteria.isEmpty {
                await search(reset: true)
            }
        }
        .onChange(of: services.siteSession.lastCookieSyncAt) {
            if !criteria.isEmpty {
                Task { await search(reset: true) }
            }
        }
    }

    private var navigationTitleText: String {
        lockedQuery ?? "Search"
    }

    private var navigationSubtitleText: String? {
        criteria.hasNonQueryFilters ? "Filtered" : nil
    }

    private var hasSearchHistories: Bool {
        !searchHistory.isEmpty || !advancedSearchHistory.isEmpty
    }

    private var visibleFilterTags: [String] {
        var visibleCriteria = criteria
        if lockedQuery != nil {
            visibleCriteria.query = ""
        }
        return visibleCriteria.activeFilters
    }

    private var isShowingSearchHistory: Bool {
        if case .idle = state {
            return hasSearchHistories
        }
        return false
    }

    private func search(reset: Bool) async {
        let nextCriteria = criteria.applyingLockedQuery(lockedQuery).normalized()
        guard !nextCriteria.isEmpty else {
            criteria = nextCriteria
            state = .idle
            return
        }

        criteria = nextCriteria
        let page = reset ? 1 : currentPage + 1
        if reset {
            state = .loading
            canLoadMore = false
        } else {
            guard canLoadMore, !isLoadingMore else { return }
            isLoadingMore = true
        }
        defer { isLoadingMore = false }

        do {
            let videos = try await services.repository.search(criteria: nextCriteria, page: page)
            currentPage = page
            canLoadMore = !videos.isEmpty
            saveSearch(nextCriteria)
            if reset {
                state = .loaded(videos)
            } else if case .loaded(let currentVideos) = state {
                state = .loaded(mergedVideos(currentVideos, videos))
            } else {
                state = .loaded(videos)
            }
        } catch {
            if services.siteSession.handle(error) {
                state = .failed("Cloudflare required")
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func mergedVideos(_ current: [HanimeInfo], _ next: [HanimeInfo]) -> [HanimeInfo] {
        (current + next).deduplicatedByVideoCode()
    }

    private func loadNextSearchPageIfNeeded() {
        guard canLoadMore, !isLoadingMore else { return }
        Task { await search(reset: false) }
    }

    private func preloadNextSearchPageIfNeeded(after video: HanimeInfo, in videos: [HanimeInfo]) {
        guard HanaInfiniteScrollPreload.shouldLoadNextPage(
            currentID: video.videoCode,
            orderedIDs: videos.map(\.videoCode)
        ) else {
            return
        }
        loadNextSearchPageIfNeeded()
    }

    private func saveSearch(_ criteria: HanimeSearchCriteria) {
        let criteria = criteria.normalized()
        guard !criteria.isEmpty else { return }
        let query = criteria.summary
        let key = criteria.historyKey
        try? modelContext.delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { record in
                record.query == query
            }
        )
        try? modelContext.delete(
            model: AdvancedSearchHistoryRecord.self,
            where: #Predicate<AdvancedSearchHistoryRecord> { record in
                record.criteriaKey == key
            }
        )
        modelContext.insert(SearchHistoryRecord(query: query))
        modelContext.insert(AdvancedSearchHistoryRecord(criteria: criteria))
        try? modelContext.save()
    }

    private func apply(_ history: AdvancedSearchHistoryRecord) {
        criteria = history.criteria
        Task { await search(reset: true) }
    }

    private func deleteHistories(at offsets: IndexSet, from histories: [AdvancedSearchHistoryRecord]) {
        for index in offsets where histories.indices.contains(index) {
            let history = histories[index]
            let query = history.summary
            try? modelContext.delete(
                model: SearchHistoryRecord.self,
                where: #Predicate<SearchHistoryRecord> { record in
                    record.query == query
                }
            )
            modelContext.delete(history)
        }
        try? modelContext.save()
    }

    private func clearAllHistories() {
        searchHistory.forEach(modelContext.delete)
        advancedSearchHistory.forEach(modelContext.delete)
        do {
            try modelContext.save()
            toastMessage = .success("Search history cleared")
        } catch {
            toastMessage = .info("Failed to clear search history")
        }
    }
}

private struct SearchFilterToolbarButton: View {
    @Binding var isPresented: Bool
    @Binding var criteria: HanimeSearchCriteria
    let lockedQuery: String?
    let onSearch: () -> Void

    var body: some View {
        let button = Button {
            isPresented = true
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("Filter")

#if os(macOS)
        button
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                MacOSHanimeSearchFilterPopover(
                    isPresented: $isPresented,
                    criteria: $criteria,
                    lockedQuery: lockedQuery,
                    onSearch: onSearch
                )
            }
#else
        button
#endif
    }
}

private struct SearchVideoGridLinks: View {
    let videos: [HanimeInfo]
    var onVideoAppear: (HanimeInfo) -> Void = { _ in }

    private var minimumCardWidth: CGFloat {
        videos.first?.style == .compact ? 132 : 180
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: minimumCardWidth),
                spacing: 12,
                alignment: .top
            )
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(videos) { video in
                NavigationLink(value: HanaRoute.video(video.videoCode)) {
                    HanaVideoGridCard(info: video)
                }
                .buttonStyle(.plain)
                .onAppear {
                    onVideoAppear(video)
                }
            }
        }
    }
}

private struct SearchIdleView: View {
    let histories: [AdvancedSearchHistoryRecord]
    let onSelect: (AdvancedSearchHistoryRecord) -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        if histories.isEmpty {
            ContentUnavailableView("Search keyword or filter", systemImage: "magnifyingglass")
        } else {
            List {
                ForEach(histories) { history in
                    Button {
                        onSelect(history)
                    } label: {
                        AdvancedSearchHistoryRow(history: history)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: onDelete)
            }
        }
    }
}

private struct AdvancedSearchHistoryRow: View {
    let history: AdvancedSearchHistoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(history.summary)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            Text(history.createdAt.hanaChineseDateTimeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct SearchFilterSummary: View {
    let tags: [String]

    var body: some View {
        FlowTags(tags: tags)
    }
}

#if os(macOS)
private enum MacOSSearchFilterPane: String, CaseIterable, Identifiable {
    case basic = "Basic"
    case tags = "Tags"
    case brands = "Brands"

    var id: Self { self }
}

private struct MacOSHanimeSearchFilterPopover: View {
    @Binding var isPresented: Bool
    @Binding var criteria: HanimeSearchCriteria
    let lockedQuery: String?
    let onSearch: () -> Void

    @State private var draft: HanimeSearchCriteria
    @State private var pane: MacOSSearchFilterPane = .basic

    init(
        isPresented: Binding<Bool>,
        criteria: Binding<HanimeSearchCriteria>,
        lockedQuery: String?,
        onSearch: @escaping () -> Void
    ) {
        _isPresented = isPresented
        _criteria = criteria
        self.lockedQuery = lockedQuery
        self.onSearch = onSearch
        _draft = State(initialValue: criteria.wrappedValue.applyingLockedQuery(lockedQuery))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Picker("Filter Category", selection: $pane) {
                ForEach(MacOSSearchFilterPane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(width: 560, height: 540)
        .onAppear {
            draft = criteria.applyingLockedQuery(lockedQuery)
        }
    }

    private var header: some View {
        HStack {
            Text("Filter")
                .font(.headline)
            Spacer()
            if draft.hasNonQueryFilters {
                Text("\(draft.activeFilters.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .basic:
            MacOSSearchBasicFilterPane(
                draft: $draft,
                datePresetSelection: datePresetSelection,
                releaseYearSelection: releaseYearSelection,
                releaseMonthSelection: releaseMonthSelection,
                releaseYearOptions: releaseYearOptions
            )
        case .tags:
            MacOSSearchOptionPane(
                title: "Tags",
                sections: HanimeSearchOptionCatalog.tagSections,
                selectedValues: $draft.tags
            )
        case .brands:
            MacOSSearchOptionPane(
                title: "Brands",
                sections: HanimeSearchOptionCatalog.brandSections,
                selectedValues: $draft.brands
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Reset", role: .destructive) {
                draft = HanimeSearchCriteria.empty.applyingLockedQuery(lockedQuery)
            }

            Spacer()

            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)

            Button("Search") {
                criteria = draft.applyingLockedQuery(lockedQuery)
                isPresented = false
                onSearch()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var datePresetSelection: Binding<String> {
        Binding {
            draft.date ?? ""
        } set: { value in
            draft.date = value.isEmpty ? nil : value
            if !value.isEmpty {
                draft.releaseYear = nil
                draft.releaseMonth = nil
            }
        }
    }

    private var releaseYearSelection: Binding<Int> {
        Binding {
            draft.releaseYear ?? 0
        } set: { value in
            draft.releaseYear = value == 0 ? nil : value
            if value == 0 {
                draft.releaseMonth = nil
            } else {
                draft.date = nil
            }
        }
    }

    private var releaseMonthSelection: Binding<Int> {
        Binding {
            draft.releaseMonth ?? 0
        } set: { value in
            draft.releaseMonth = value == 0 ? nil : value
            if value != 0 {
                draft.releaseYear = draft.releaseYear ?? Calendar.current.component(.year, from: .now)
                draft.date = nil
            }
        }
    }

    private var releaseYearOptions: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        return Array((1990...(currentYear + 1)).reversed())
    }
}

private struct MacOSSearchBasicFilterPane: View {
    @Binding var draft: HanimeSearchCriteria
    let datePresetSelection: Binding<String>
    let releaseYearSelection: Binding<Int>
    let releaseMonthSelection: Binding<Int>
    let releaseYearOptions: [Int]

    var body: some View {
        Form {
            Picker("Genre:", selection: optionalSelection(\.genre)) {
                Text("All").tag("")
                ForEach(HanimeSearchOption.genres) { option in
                    Text(option.title).tag(option.value ?? "")
                }
            }
            .pickerStyle(.menu)

            Picker("Sort:", selection: optionalSelection(\.sort)) {
                Text("Default").tag("")
                ForEach(HanimeSearchOption.sortOptions) { option in
                    Text(option.title).tag(option.value ?? "")
                }
            }
            .pickerStyle(.menu)

            Divider()

            Picker("Date Range:", selection: datePresetSelection) {
                Text("All").tag("")
                ForEach(HanimeSearchOption.dateOptions) { option in
                    Text(option.title).tag(option.value ?? "")
                }
            }
            .pickerStyle(.menu)

            Picker("Year:", selection: releaseYearSelection) {
                Text("All").tag(0)
                ForEach(releaseYearOptions, id: \.self) { year in
                    Text("\(year)").tag(year)
                }
            }
            .pickerStyle(.menu)

            Picker("Month:", selection: releaseMonthSelection) {
                Text("All Year").tag(0)
                ForEach(1...12, id: \.self) { month in
                    Text("Month \(month)").tag(month)
                }
            }
            .pickerStyle(.menu)

            Picker("Duration:", selection: optionalSelection(\.duration)) {
                Text("All").tag("")
                ForEach(HanimeSearchOption.durationOptions) { option in
                    Text(option.title).tag(option.value ?? "")
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func optionalSelection(_ keyPath: WritableKeyPath<HanimeSearchCriteria, String?>) -> Binding<String> {
        Binding {
            draft[keyPath: keyPath] ?? ""
        } set: { value in
            draft[keyPath: keyPath] = value.isEmpty ? nil : value
        }
    }
}

private struct MacOSSearchOptionPane: View {
    let title: String
    let sections: [HanimeSearchOptionSection]
    @Binding var selectedValues: [String]
    @State private var query = ""

    private var selectedSet: Set<String> {
        Set(selectedValues)
    }

    private var displayedSections: [HanimeSearchOptionSection] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sections.compactMap { section in
            let options = section.options.filter { option in
                if let value = option.value, selectedSet.contains(value) {
                    return false
                }
                guard !text.isEmpty else { return true }
                return option.title.localizedCaseInsensitiveContains(text)
                    || (option.value?.localizedCaseInsensitiveContains(text) == true)
            }
            guard !options.isEmpty else { return nil }
            return HanimeSearchOptionSection(title: section.title, options: options)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search \(title)", text: $query)
                    .textFieldStyle(.roundedBorder)

                Button("Clear All", role: .destructive) {
                    selectedValues = []
                }
                .disabled(selectedValues.isEmpty)
            }

            Text(selectedValues.isEmpty ? "None" : "\(selectedValues.count) Selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                if !selectedValues.isEmpty {
                    Section("Selected") {
                        ForEach(selectedValues, id: \.self) { value in
                            Button {
                                remove(value)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(displayTitle(for: value))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if sections.isEmpty {
                    ContentUnavailableView("Options Unavailable", systemImage: "exclamationmark.triangle")
                        .listRowBackground(Color.clear)
                } else if displayedSections.isEmpty {
                    ContentUnavailableView(emptyOptionsTitle, systemImage: "magnifyingglass")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(displayedSections) { section in
                        Section(section.title) {
                            ForEach(section.options) { option in
                                Button {
                                    toggle(option)
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(option.title)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .padding(20)
    }

    private var emptyOptionsTitle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "All options selected" : "No options match"
    }

    private func toggle(_ option: HanimeSearchOption) {
        guard let value = option.value, !value.isEmpty else { return }
        if selectedSet.contains(value) {
            remove(value)
        } else {
            selectedValues.append(value)
            selectedValues = normalized(selectedValues)
        }
    }

    private func remove(_ value: String) {
        selectedValues.removeAll { $0 == value }
    }

    private func displayTitle(for value: String) -> String {
        sections.lazy
            .flatMap(\.options)
            .first { $0.value == value }?
            .title ?? value
    }

    private func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
#endif

private struct HanimeSearchFilterSheet: View {
    @Binding var criteria: HanimeSearchCriteria
    let lockedQuery: String?
    let onSearch: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: HanimeSearchCriteria

    init(
        criteria: Binding<HanimeSearchCriteria>,
        lockedQuery: String? = nil,
        onSearch: @escaping () -> Void
    ) {
        _criteria = criteria
        self.lockedQuery = lockedQuery
        self.onSearch = onSearch
        let value = criteria.wrappedValue.applyingLockedQuery(lockedQuery)
        _draft = State(initialValue: value)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    Picker("Genre", selection: optionalSelection(\.genre)) {
                        Text("All").tag("")
                        ForEach(HanimeSearchOption.genres) { option in
                            Text(option.title).tag(option.value ?? "")
                        }
                    }

                    Picker("Sort", selection: optionalSelection(\.sort)) {
                        Text("Default").tag("")
                        ForEach(HanimeSearchOption.sortOptions) { option in
                            Text(option.title).tag(option.value ?? "")
                        }
                    }
                }

                Section("Time") {
                    Picker("Date Range", selection: datePresetSelection) {
                        Text("All").tag("")
                        ForEach(HanimeSearchOption.dateOptions) { option in
                            Text(option.title).tag(option.value ?? "")
                        }
                    }

                    Picker("Year", selection: releaseYearSelection) {
                        Text("All").tag(0)
                        ForEach(releaseYearOptions, id: \.self) { year in
                            Text("\(year)").tag(year)
                        }
                    }

                    Picker("Month", selection: releaseMonthSelection) {
                        Text("All Year").tag(0)
                        ForEach(1...12, id: \.self) { month in
                            Text("Month \(month)").tag(month)
                        }
                    }

                    Picker("Duration", selection: optionalSelection(\.duration)) {
                        Text("All").tag("")
                        ForEach(HanimeSearchOption.durationOptions) { option in
                            Text(option.title).tag(option.value ?? "")
                        }
                    }
                }

                Section("Tags") {
                    NavigationLink {
                        HanimeSearchOptionSelectionView(
                            title: "Tags",
                            sections: HanimeSearchOptionCatalog.tagSections,
                            selectedValues: $draft.tags
                        )
                    } label: {
                        SearchSelectionSummaryRow(title: "Selected", count: draft.tags.count)
                    }
                }

                Section("Brands") {
                    NavigationLink {
                        HanimeSearchOptionSelectionView(
                            title: "Brands",
                            sections: HanimeSearchOptionCatalog.brandSections,
                            selectedValues: $draft.brands
                        )
                    } label: {
                        SearchSelectionSummaryRow(title: "Selected", count: draft.brands.count)
                    }
                }
            }
            .navigationTitle("Filter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .destructiveAction) {
                    HanaToolbarIconButton(title: "Reset", systemImage: "eraser", role: .destructive) {
                        draft = HanimeSearchCriteria.empty.applyingLockedQuery(lockedQuery)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "Done", systemImage: "checkmark") {
                        criteria = draft.applyingLockedQuery(lockedQuery)
                        dismiss()
                        onSearch()
                    }
                }
            }
        }
    }

    private func optionalSelection(_ keyPath: WritableKeyPath<HanimeSearchCriteria, String?>) -> Binding<String> {
        Binding {
            draft[keyPath: keyPath] ?? ""
        } set: { value in
            draft[keyPath: keyPath] = value.isEmpty ? nil : value
        }
    }

    private var datePresetSelection: Binding<String> {
        Binding {
            draft.date ?? ""
        } set: { value in
            draft.date = value.isEmpty ? nil : value
            if !value.isEmpty {
                draft.releaseYear = nil
                draft.releaseMonth = nil
            }
        }
    }

    private var releaseYearSelection: Binding<Int> {
        Binding {
            draft.releaseYear ?? 0
        } set: { value in
            draft.releaseYear = value == 0 ? nil : value
            if value == 0 {
                draft.releaseMonth = nil
            } else {
                draft.date = nil
            }
        }
    }

    private var releaseMonthSelection: Binding<Int> {
        Binding {
            draft.releaseMonth ?? 0
        } set: { value in
            draft.releaseMonth = value == 0 ? nil : value
            if value != 0 {
                draft.releaseYear = draft.releaseYear ?? Calendar.current.component(.year, from: .now)
                draft.date = nil
            }
        }
    }

    private var releaseYearOptions: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        return Array((1990...(currentYear + 1)).reversed())
    }
}

private extension View {
    @ViewBuilder
    func searchFilterSheet(
        isPresented: Binding<Bool>,
        criteria: Binding<HanimeSearchCriteria>,
        lockedQuery: String?,
        onSearch: @escaping () -> Void
    ) -> some View {
#if os(macOS)
        self
#else
        sheet(isPresented: isPresented) {
            HanimeSearchFilterSheet(criteria: criteria, lockedQuery: lockedQuery, onSearch: onSearch)
        }
#endif
    }
}

private struct SearchSelectionSummaryRow: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(count == 0 ? "None" : "\(count)")
                .foregroundStyle(.secondary)
        }
    }
}

private struct HanimeSearchOptionSelectionView: View {
    let title: String
    let sections: [HanimeSearchOptionSection]
    @Binding var selectedValues: [String]
    @State private var query = ""

    private var selectedSet: Set<String> {
        Set(selectedValues)
    }

    private var displayedSections: [HanimeSearchOptionSection] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sections.compactMap { section in
            let options = section.options.filter { option in
                if let value = option.value, selectedSet.contains(value) {
                    return false
                }
                guard !text.isEmpty else { return true }
                return option.title.localizedCaseInsensitiveContains(text)
                    || (option.value?.localizedCaseInsensitiveContains(text) == true)
            }
            guard !options.isEmpty else { return nil }
            return HanimeSearchOptionSection(title: section.title, options: options)
        }
    }

    var body: some View {
        List {
            Section("Selected") {
                if selectedValues.isEmpty {
                    Text("Not Selected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedValues, id: \.self) { value in
                        Button {
                            remove(value)
                        } label: {
                            HStack {
                                Text(displayTitle(for: value))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button(role: .destructive) {
                        selectedValues = []
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }

            if sections.isEmpty {
                ContentUnavailableView("Options Unavailable", systemImage: "exclamationmark.triangle")
                    .listRowBackground(Color.clear)
            } else if displayedSections.isEmpty {
                ContentUnavailableView(emptyOptionsTitle, systemImage: "magnifyingglass")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(displayedSections) { section in
                    Section(section.title) {
                        ForEach(section.options) { option in
                            Button {
                                toggle(option)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(option.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .searchable(text: $query, prompt: "Search \(title)")
    }

    private var emptyOptionsTitle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "All options selected" : "No options match"
    }

    private func toggle(_ option: HanimeSearchOption) {
        guard let value = option.value, !value.isEmpty else { return }
        if selectedSet.contains(value) {
            remove(value)
        } else {
            selectedValues.append(value)
            selectedValues = normalized(selectedValues)
        }
    }

    private func remove(_ value: String) {
        selectedValues.removeAll { $0 == value }
    }

    private func displayTitle(for value: String) -> String {
        sections.lazy
            .flatMap(\.options)
            .first { $0.value == value }?
            .title ?? value
    }

    private func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
