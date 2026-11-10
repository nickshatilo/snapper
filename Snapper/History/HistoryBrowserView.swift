import SwiftUI
import SwiftData

private let historyThumbnailCache = NSCache<NSString, NSImage>()

struct HistoryBrowserView: View {
    let historyManager: HistoryManager
    @State private var records: [CaptureRecord] = []
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var showGrid = true
    @State private var selectedFilter: CaptureMode?
    @State private var selectedRecords: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)]
    /// Only modes that are stored on a record: timer captures are recorded
    /// under the mode they run, and OCR captures leave no record.
    private static let filterModes: [CaptureMode] = [.fullscreen, .area, .window, .scroll]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if filteredRecords.isEmpty {
                emptyState
            } else if showGrid {
                gridView
            } else {
                listView
            }
            Divider()
            statusBar
        }
        .onAppear(perform: reloadRecords)
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            if newValue.isEmpty {
                debouncedSearchText = ""
            } else {
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyDidChange)) { _ in
            reloadRecords()
        }
    }

    private var filteredRecords: [CaptureRecord] {
        var result = records
        if !debouncedSearchText.isEmpty {
            let query = debouncedSearchText
            result = result.filter {
                $0.ocrText?.localizedCaseInsensitiveContains(query) == true ||
                $0.applicationName?.localizedCaseInsensitiveContains(query) == true ||
                $0.captureType.localizedCaseInsensitiveContains(query)
            }
        }
        if let filter = selectedFilter {
            result = result.filter { $0.captureType == filter.rawValue }
        }
        return result
    }

    private var toolbar: some View {
        HStack {
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)

            Picker("Filter", selection: $selectedFilter) {
                Text("All").tag(nil as CaptureMode?)
                ForEach(Self.filterModes, id: \.self) { mode in
                    Text(mode.displayName).tag(mode as CaptureMode?)
                }
            }
            .frame(width: 150)

            Spacer()

            Button(action: { showGrid = true }) {
                Image(systemName: "square.grid.2x2")
            }
            .buttonStyle(.bordered)
            .tint(showGrid ? .accentColor : nil)

            Button(action: { showGrid = false }) {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(.bordered)
            .tint(!showGrid ? .accentColor : nil)

            if !selectedRecords.isEmpty {
                Button("Remove Selected (\(selectedRecords.count)) from History") {
                    deleteSelected()
                }
                .foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filteredRecords, id: \.id) { record in
                    historyGridItem(record)
                }
            }
            .padding(12)
        }
    }

    private var listView: some View {
        List(filteredRecords, id: \.id) { record in
            historyListRow(record)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No captures yet")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Your screenshots will appear here")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack {
            Text("\(filteredRecords.count) captures")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            let totalSize = records.reduce(0) { $0 + $1.fileSize }
            Text("Screenshots on disk: \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func historyGridItem(_ record: CaptureRecord) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            HistoryThumbnailImageView(path: record.thumbnailPath, cornerRadius: 6)

            Text(record.captureType.capitalized)
                .font(.caption)
                .fontWeight(.medium)
            Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let caption = missingFileCaption(for: record) {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(selectedRecords.contains(record.id) ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            toggleSelection(record)
        }
        .contextMenu {
            recordActions(record)
        }
    }

    private func toggleSelection(_ record: CaptureRecord) {
        if selectedRecords.contains(record.id) {
            selectedRecords.remove(record.id)
        } else {
            selectedRecords.insert(record.id)
        }
    }

    @ViewBuilder
    private func recordActions(_ record: CaptureRecord) -> some View {
        // Captures that were never saved, or whose file was moved or deleted
        // since, have nothing to open, reveal or copy.
        let fileExists = missingFileCaption(for: record) == nil
        Button("Open in Editor") {
            if let loaded = loadImage(for: record) {
                NotificationCenter.default.post(
                    name: .openEditor,
                    object: ImageWrapper(loaded.image, scale: loaded.scale)
                )
            }
        }
        .disabled(!fileExists)
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.filePath)])
        }
        .disabled(!fileExists)
        Button("Copy") {
            if let loaded = loadImage(for: record) {
                PasteboardHelper.copyImage(
                    loaded.image,
                    scale: loaded.scale,
                    showsConfirmation: true,
                    confirmationScreen: NSApp.keyWindow?.screen
                )
            }
        }
        .disabled(!fileExists)
        Divider()
        // Only the history entry goes away; the screenshot file is kept.
        Button("Remove from History", role: .destructive) {
            Task { @MainActor in
                removeThumbnailFromCache(for: record)
                historyManager.delete(record)
                records.removeAll { $0.id == record.id }
                selectedRecords.remove(record.id)
            }
        }
    }

    /// Why a record's screenshot can't be opened, or nil when its file exists.
    private func missingFileCaption(for record: CaptureRecord) -> String? {
        if record.filePath.isEmpty {
            return "Not saved to disk"
        }
        if !FileManager.default.fileExists(atPath: record.filePath) {
            return "File missing"
        }
        return nil
    }

    /// Loads a record's screenshot with its backing scale (pixels per point),
    /// so Retina captures keep their on-screen size in the editor and when
    /// pasted.
    private func loadImage(for record: CaptureRecord) -> (image: CGImage, scale: CGFloat)? {
        ImageUtils.loadImage(at: URL(fileURLWithPath: record.filePath))
    }

    private func historyListRow(_ record: CaptureRecord) -> some View {
        return HStack(spacing: 12) {
            HistoryThumbnailImageView(path: record.thumbnailPath, cornerRadius: 4)
                .frame(width: 80, height: 50)

            VStack(alignment: .leading) {
                Text(record.captureType.capitalized)
                    .fontWeight(.medium)
                Text("\(record.width) × \(record.height)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let caption = missingFileCaption(for: record) {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(ByteCountFormatter.string(fromByteCount: Int64(record.fileSize), countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .listRowBackground(
            selectedRecords.contains(record.id) ? Color.accentColor.opacity(0.2) : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(record)
        }
        .contextMenu {
            recordActions(record)
        }
    }

    private func deleteSelected() {
        Task { @MainActor in
            let idsToDelete = selectedRecords
            for record in records where idsToDelete.contains(record.id) {
                removeThumbnailFromCache(for: record)
                historyManager.delete(record)
            }
            records.removeAll { idsToDelete.contains($0.id) }
            selectedRecords.removeAll()
        }
    }

    private func reloadRecords() {
        let fetched = historyManager.fetchAll()
        records = fetched

        let validIDs = Set(fetched.map(\.id))
        selectedRecords = selectedRecords.intersection(validIDs)
    }

    private func removeThumbnailFromCache(for record: CaptureRecord) {
        if let path = record.thumbnailPath {
            historyThumbnailCache.removeObject(forKey: path as NSString)
        }
    }
}

private struct HistoryThumbnailImageView: View {
    let path: String?
    let cornerRadius: CGFloat
    @State private var image: NSImage?
    @State private var loadingPath: String?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .onAppear {
            loadThumbnailIfNeeded()
        }
        .onChange(of: path) { _, _ in
            image = nil
            loadingPath = nil
            loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() {
        guard let path else {
            image = nil
            return
        }
        let key = path as NSString
        if let cached = historyThumbnailCache.object(forKey: key) {
            image = cached
            return
        }
        guard loadingPath != path else { return }
        loadingPath = path

        DispatchQueue.global(qos: .utility).async {
            let loaded = NSImage(contentsOfFile: path)
            if let loaded {
                historyThumbnailCache.setObject(loaded, forKey: key)
            }
            DispatchQueue.main.async {
                guard loadingPath == path else { return }
                image = loaded
            }
        }
    }
}
