import SwiftUI
import SwiftData

struct HistoryBrowserView: View {
    let historyManager: HistoryManager
    @State private var records: [CaptureRecord] = []
    @State private var searchText = ""
    @State private var showGrid = true
    @State private var selectedFilter: CaptureMode?
    @State private var selectedRecords: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)]

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
    }

    private var filteredRecords: [CaptureRecord] {
        var result = records
        if !searchText.isEmpty {
            result = result.filter {
                $0.ocrText?.localizedCaseInsensitiveContains(searchText) == true ||
                $0.applicationName?.localizedCaseInsensitiveContains(searchText) == true ||
                $0.captureType.localizedCaseInsensitiveContains(searchText)
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
                ForEach(CaptureMode.allCases, id: \.self) { mode in
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
                Button("Delete Selected (\(selectedRecords.count))") {
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
            Text("Total: \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func historyGridItem(_ record: CaptureRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let thumbPath = record.thumbnailPath,
               let image = NSImage(contentsOfFile: thumbPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                    }
            }

            Text(record.captureType.capitalized)
                .font(.caption)
                .fontWeight(.medium)
            Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(selectedRecords.contains(record.id) ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if selectedRecords.contains(record.id) {
                selectedRecords.remove(record.id)
            } else {
                selectedRecords.insert(record.id)
            }
        }
        .contextMenu {
            Button("Open in Editor") {
                if let image = NSImage(contentsOfFile: record.filePath)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    NotificationCenter.default.post(name: .openEditor, object: ImageWrapper(image))
                }
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.filePath)])
            }
            Button("Copy") {
                if let image = NSImage(contentsOfFile: record.filePath) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    historyManager.delete(record)
                    records.removeAll { $0.id == record.id }
                }
            }
        }
    }

    private func historyListRow(_ record: CaptureRecord) -> some View {
        HStack(spacing: 12) {
            if let thumbPath = record.thumbnailPath,
               let image = NSImage(contentsOfFile: thumbPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading) {
                Text(record.captureType.capitalized)
                    .fontWeight(.medium)
                Text("\(record.width) × \(record.height)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(ByteCountFormatter.string(fromByteCount: Int64(record.fileSize), countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func deleteSelected() {
        Task { @MainActor in
            for id in selectedRecords {
                if let record = records.first(where: { $0.id == id }) {
                    historyManager.delete(record)
                }
            }
            records.removeAll { selectedRecords.contains($0.id) }
            selectedRecords.removeAll()
        }
    }
}
