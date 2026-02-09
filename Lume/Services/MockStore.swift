import Foundation

struct ImportReport: Hashable {
    let inserted: Int
    let updated: Int
    let skipped: Int

    var total: Int { inserted + updated + skipped }
}

actor LocalLibraryStore {
    static let shared = LocalLibraryStore()

    private let fileManager: FileManager
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var state: LibraryState
    private var recordsByID: [String: MediaRecord] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = Self.resolveStorageURL(fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if let loaded = Self.loadState(from: storageURL, decoder: decoder, fileManager: fileManager) {
            self.state = loaded
        } else {
            self.state = LibraryState()
        }

        if state.favoriteGroups.isEmpty {
            seedDefaultGroups()
        }

        rebuildIndex()
    }

    func listMedia(type: MediaType?, keyword: String?) -> [MediaItem] {
        var records = state.mediaRecords
        if let type {
            records = records.filter { $0.type == type }
        }
        if let keyword, !keyword.isEmpty {
            let needle = keyword.lowercased()
            records = records.filter { record in
                if record.title.lowercased().contains(needle) {
                    return true
                }
                if let subtitle = record.subtitle, subtitle.lowercased().contains(needle) {
                    return true
                }
                return false
            }
        }
        return records.map { $0.asMediaItem() }
    }

    func mediaDetail(id: String) throws -> MediaDetail {
        guard let record = recordsByID[id] else {
            throw APIError.httpStatus(404)
        }
        return record.asMediaDetail()
    }

    func importCSV(from url: URL) throws -> ImportReport {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw LibraryError.unreadableCSV
        }

        let rows = CSVParser.parse(content)
        guard let headerRow = rows.first, !headerRow.isEmpty else {
            throw LibraryError.emptyCSV
        }

        let headers = headerRow.map { normalizeHeader($0) }
        var headerIndex: [String: Int] = [:]
        for (index, header) in headers.enumerated() where headerIndex[header] == nil {
            headerIndex[header] = index
        }
        if !headerIndex.keys.contains(where: { ["url", "media_url", "source_url"].contains($0) }) {
            throw LibraryError.missingRequiredColumn("url")
        }

        var inserted = 0
        var updated = 0
        var skipped = 0
        var touchedIDs: Set<String> = []
        var seenIDs: Set<String> = []

        var indexByID: [String: Int] = Dictionary(uniqueKeysWithValues: state.mediaRecords.enumerated().map { ($0.element.id, $0.offset) })

        for row in rows.dropFirst() {
            guard let urlValue = fieldValue(headerIndex, row: row, keys: ["url", "media_url", "source_url"]) else {
                skipped += 1
                continue
            }
            guard let url = normalizedURL(from: urlValue) else {
                skipped += 1
                continue
            }

            let id = url.absoluteString
            if seenIDs.contains(id) {
                skipped += 1
                continue
            }
            seenIDs.insert(id)
            let titleValue = fieldValue(headerIndex, row: row, keys: ["title", "name"])
            let typeValue = fieldValue(headerIndex, row: row, keys: ["type", "media_type"])
            let durationMSValue = fieldValue(headerIndex, row: row, keys: ["duration_ms", "length_ms"])
            let durationValue = fieldValue(headerIndex, row: row, keys: ["duration", "length", "seconds"])
            let thumbValue = fieldValue(headerIndex, row: row, keys: ["thumb_url", "cover_url", "cover", "thumbnail"])
            let subtitleValue = fieldValue(headerIndex, row: row, keys: ["subtitle", "artist", "author", "creator"])
            let tagsValue = fieldValue(headerIndex, row: row, keys: ["tags", "tag"])
            let statusValue = fieldValue(headerIndex, row: row, keys: ["status"])
            let formatValue = fieldValue(headerIndex, row: row, keys: ["format", "ext"])

            let type = parseType(typeValue) ?? inferType(from: url) ?? .audio
            let durationMS = parseDurationMS(durationMSValue: durationMSValue, durationValue: durationValue)
            let thumbURL = normalizedURL(from: thumbValue)
            let tags = parseTags(tagsValue)
            let title = buildTitle(titleValue, fallbackURL: url)
            let status = (statusValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? statusValue!.trimmingCharacters(in: .whitespacesAndNewlines) : "ready"
            let format = resolveFormat(formatValue, url: url)

            let record = MediaRecord(
                id: id,
                url: url,
                type: type,
                title: title,
                durationMS: durationMS,
                thumbURL: thumbURL,
                status: status,
                subtitle: subtitleValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: tags,
                format: format
            )

            if let existingIndex = indexByID[id] {
                state.mediaRecords[existingIndex] = record
                updated += 1
            } else {
                state.mediaRecords.append(record)
                indexByID[id] = state.mediaRecords.count - 1
                inserted += 1
            }
            touchedIDs.insert(id)
        }

        if inserted > 0 || updated > 0 {
            rebuildIndex()
            refreshFavoriteItems(for: touchedIDs)
            try persist()
        }

        return ImportReport(inserted: inserted, updated: updated, skipped: skipped)
    }

    func importJSON(from url: URL) throws -> ImportReport {
        let data = try Data(contentsOf: url)
        let records = try decodeMediaImportRecords(from: data)
        guard !records.isEmpty else { return ImportReport(inserted: 0, updated: 0, skipped: 0) }

        var inserted = 0
        var updated = 0
        var skipped = 0
        var touchedIDs: Set<String> = []
        var seenIDs: Set<String> = []
        var indexByID: [String: Int] = Dictionary(uniqueKeysWithValues: state.mediaRecords.enumerated().map { ($0.element.id, $0.offset) })

        for record in records {
            guard let url = normalizedURL(from: record.url) else {
                skipped += 1
                continue
            }

            let id = url.absoluteString
            if seenIDs.contains(id) {
                skipped += 1
                continue
            }
            seenIDs.insert(id)

            let type = parseType(record.type) ?? inferType(from: url) ?? .audio
            let durationMS = parseDurationMS(durationMSValue: record.durationMS, durationValue: record.duration)
            let thumbURL = normalizedURL(from: record.thumbURL)
            let tags = normalizeTags(record.tags) ?? parseTags(record.tagsString)
            let title = buildTitle(record.title, fallbackURL: url)
            let status = (record.status?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? record.status!.trimmingCharacters(in: .whitespacesAndNewlines) : "ready"
            let format = resolveFormat(record.format, url: url)

            let mediaRecord = MediaRecord(
                id: id,
                url: url,
                type: type,
                title: title,
                durationMS: durationMS,
                thumbURL: thumbURL,
                status: status,
                subtitle: record.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: tags,
                format: format
            )

            if let existingIndex = indexByID[id] {
                state.mediaRecords[existingIndex] = mediaRecord
                updated += 1
            } else {
                state.mediaRecords.append(mediaRecord)
                indexByID[id] = state.mediaRecords.count - 1
                inserted += 1
            }
            touchedIDs.insert(id)
        }

        if inserted > 0 || updated > 0 {
            rebuildIndex()
            refreshFavoriteItems(for: touchedIDs)
            try persist()
        }

        return ImportReport(inserted: inserted, updated: updated, skipped: skipped)
    }

    func deleteMedia(id: String) throws {
        guard recordsByID[id] != nil else { return }
        state.mediaRecords.removeAll { $0.id == id }
        for (groupID, items) in state.favoriteItemsByGroup {
            state.favoriteItemsByGroup[groupID] = items.filter { $0.mediaID != id }
        }
        rebuildIndex()
        try persist()
    }

    func listGroups() -> [FavoriteGroup] {
        state.favoriteGroups.map { group in
            let count = state.favoriteItemsByGroup[group.id]?.count ?? 0
            return FavoriteGroup(id: group.id, name: group.name, mediaType: group.mediaType, count: count)
        }
    }

    func createGroup(name: String, mediaType: MediaType) throws -> FavoriteGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LibraryError.invalidGroupName
        }

        let id = "g_\(UUID().uuidString.prefix(8))"
        let group = FavoriteGroupSeed(id: id, name: trimmed, mediaType: mediaType)
        state.favoriteGroups.insert(group, at: 0)
        state.favoriteItemsByGroup[id] = []
        try persist()
        return FavoriteGroup(id: id, name: trimmed, mediaType: mediaType, count: 0)
    }

    func deleteGroup(id: String) throws {
        state.favoriteGroups.removeAll { $0.id == id }
        state.favoriteItemsByGroup[id] = nil
        try persist()
    }

    func listItems(groupID: String) -> [FavoriteListItem] {
        state.favoriteItemsByGroup[groupID] ?? []
    }

    func addItem(groupID: String, mediaID: String) throws -> FavoriteListItem {
        guard let group = state.favoriteGroups.first(where: { $0.id == groupID }) else {
            throw APIError.httpStatus(404)
        }
        guard let record = recordsByID[mediaID] else {
            throw APIError.httpStatus(404)
        }
        guard record.type == group.mediaType else {
            throw APIError.httpStatus(409)
        }

        var items = state.favoriteItemsByGroup[groupID] ?? []
        if let existing = items.first(where: { $0.mediaID == mediaID }) {
            return existing
        }

        let item = record.asFavoriteItem()
        items.insert(item, at: 0)
        state.favoriteItemsByGroup[groupID] = items
        try persist()
        return item
    }

    func removeItem(groupID: String, mediaID: String) throws {
        guard var items = state.favoriteItemsByGroup[groupID] else { return }
        items.removeAll { $0.mediaID == mediaID }
        state.favoriteItemsByGroup[groupID] = items
        try persist()
    }

    private func seedDefaultGroups() {
        let audio = FavoriteGroupSeed(id: "g_audio", name: "My Audios", mediaType: .audio)
        let video = FavoriteGroupSeed(id: "g_video", name: "My Videos", mediaType: .video)
        state.favoriteGroups = [audio, video]
        state.favoriteItemsByGroup[audio.id] = []
        state.favoriteItemsByGroup[video.id] = []
        try? persist()
    }

    private func rebuildIndex() {
        recordsByID = Dictionary(uniqueKeysWithValues: state.mediaRecords.map { ($0.id, $0) })
    }

    private func refreshFavoriteItems(for ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for (groupID, items) in state.favoriteItemsByGroup {
            var updatedItems: [FavoriteListItem] = []
            var changed = false
            updatedItems.reserveCapacity(items.count)
            for item in items {
                if ids.contains(item.mediaID), let record = recordsByID[item.mediaID] {
                    updatedItems.append(record.asFavoriteItem())
                    changed = true
                } else {
                    updatedItems.append(item)
                }
            }
            if changed {
                state.favoriteItemsByGroup[groupID] = updatedItems
            }
        }
    }

    private func persist() throws {
        let folderURL = storageURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        }
        let data = try encoder.encode(state)
        try data.write(to: storageURL, options: .atomic)
    }

    private static func resolveStorageURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent(AppConfig.libraryFolderName, isDirectory: true)
            .appendingPathComponent(AppConfig.libraryFileName)
    }

    private static func loadState(from url: URL, decoder: JSONDecoder, fileManager: FileManager) -> LibraryState? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(LibraryState.self, from: data)
    }

    private func normalizeHeader(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let noBom = trimmed.replacingOccurrences(of: "\u{FEFF}", with: "")
        return noBom
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func fieldValue(_ headers: [String: Int], row: [String], keys: [String]) -> String? {
        for key in keys {
            if let index = headers[key], index < row.count {
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func normalizedURL(from raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let url = URL(string: trimmed) {
            return url
        }
        if let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            return URL(string: escaped)
        }
        return nil
    }

    private func parseType(_ raw: String?) -> MediaType? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains("video") || value == "v" {
            return .video
        }
        if value.contains("audio") || value.contains("music") || value == "a" {
            return .audio
        }
        return nil
    }

    private func inferType(from url: URL) -> MediaType? {
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "mkv", "webm", "m4v"].contains(ext) {
            return .video
        }
        if ["mp3", "m4a", "aac", "flac", "wav", "ogg"].contains(ext) {
            return .audio
        }
        return nil
    }

    private func parseDurationMS(durationMSValue: String?, durationValue: String?) -> Int {
        if let durationMSValue, let ms = Int(durationMSValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(ms, 0)
        }
        guard let durationValue else { return 0 }
        let trimmed = durationValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(":") {
            if let seconds = parseTimeToSeconds(trimmed) {
                return max(Int(seconds * 1000), 0)
            }
        }
        if let seconds = Double(trimmed) {
            return max(Int(seconds * 1000), 0)
        }
        return 0
    }

    private func parseTimeToSeconds(_ value: String) -> Double? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2, parts.count <= 3 else { return nil }
        var total: Double = 0
        for part in parts {
            guard let component = Double(part) else { return nil }
            total = total * 60 + component
        }
        return total
    }

    private func decodeMediaImportRecords(from data: Data) throws -> [MediaImportRecord] {
        let decoder = JSONDecoder()
        if let records = try? decoder.decode([MediaImportRecord].self, from: data) {
            return records
        }
        if let payload = try? decoder.decode(MediaImportPayload.self, from: data) {
            return payload.items
        }
        throw LibraryError.unreadableJSON
    }

    private func parseTags(_ value: String?) -> [String]? {
        guard let value else { return nil }
        let tags = value.split { ",;|".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return tags.isEmpty ? nil : tags
    }

    private func normalizeTags(_ tags: [String]?) -> [String]? {
        guard let tags else { return nil }
        let trimmed = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return trimmed.isEmpty ? nil : trimmed
    }

    private func buildTitle(_ value: String?, fallbackURL: URL) -> String {
        if let value {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let fallback = fallbackURL.deletingPathExtension().lastPathComponent
        return fallback.isEmpty ? "Untitled" : fallback
    }

    private func resolveFormat(_ value: String?, url: URL) -> String {
        if let value {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed.lowercased() }
        }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "unknown" : ext
    }
}

private struct LibraryState: Codable {
    var mediaRecords: [MediaRecord] = []
    var favoriteGroups: [FavoriteGroupSeed] = []
    var favoriteItemsByGroup: [String: [FavoriteListItem]] = [:]
}

private struct FavoriteGroupSeed: Codable, Hashable {
    let id: String
    let name: String
    let mediaType: MediaType
}

private struct MediaRecord: Codable, Hashable {
    let id: String
    let url: URL
    let type: MediaType
    let title: String
    let durationMS: Int
    let thumbURL: URL?
    let status: String
    let subtitle: String?
    let tags: [String]?
    let format: String

    func asMediaItem() -> MediaItem {
        MediaItem(
            id: id,
            type: type,
            title: title,
            durationMS: durationMS,
            thumbURL: thumbURL,
            status: status,
            tags: tags
        )
    }

    func asMediaDetail() -> MediaDetail {
        let source = MediaSource(format: format, quality: "source", url: url)
        return MediaDetail(
            id: id,
            type: type,
            title: title,
            subtitle: subtitle,
            durationMS: durationMS,
            status: status,
            thumbURL: thumbURL,
            sources: [source]
        )
    }

    func asFavoriteItem() -> FavoriteListItem {
        FavoriteListItem(
            id: id,
            mediaID: id,
            mediaType: type,
            title: title,
            subtitle: subtitle,
            durationMS: durationMS,
            thumbURL: thumbURL,
            tags: tags
        )
    }
}

private enum LibraryError: Error {
    case emptyCSV
    case unreadableCSV
    case unreadableJSON
    case invalidGroupName
    case missingRequiredColumn(String)
}

private struct MediaImportPayload: Decodable {
    let items: [MediaImportRecord]
}

private struct MediaImportRecord: Decodable {
    let url: String?
    let title: String?
    let type: String?
    let duration: String?
    let durationMS: String?
    let thumbURL: String?
    let subtitle: String?
    let tags: [String]?
    let tagsString: String?
    let format: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case type
        case duration
        case durationMSSnake = "duration_ms"
        case durationMSCamel = "durationMS"
        case thumbURLSnake = "thumb_url"
        case thumbURLCamel = "thumbURL"
        case subtitle
        case tags
        case format
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = Self.decodeLossyString(container, key: .url)
        title = Self.decodeLossyString(container, key: .title)
        type = Self.decodeLossyString(container, key: .type)
        duration = Self.decodeLossyString(container, key: .duration)
        durationMS = Self.decodeLossyString(container, key: .durationMSSnake)
            ?? Self.decodeLossyString(container, key: .durationMSCamel)
        thumbURL = Self.decodeLossyString(container, key: .thumbURLSnake)
            ?? Self.decodeLossyString(container, key: .thumbURLCamel)
        subtitle = Self.decodeLossyString(container, key: .subtitle)
        format = Self.decodeLossyString(container, key: .format)
        status = Self.decodeLossyString(container, key: .status)

        if let array = try? container.decode([String].self, forKey: .tags) {
            tags = array
            tagsString = nil
        } else {
            tags = nil
            tagsString = Self.decodeLossyString(container, key: .tags)
        }
    }

    private static func decodeLossyString(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

private struct CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if inQuotes {
                if char == "\"" {
                    let nextIndex = index + 1
                    if nextIndex < chars.count && chars[nextIndex] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    if index + 1 < chars.count, chars[index + 1] == "\n" {
                        index += 1
                    }
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.append(char)
                }
            }
            index += 1
        }

        if !row.isEmpty || !field.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
}
