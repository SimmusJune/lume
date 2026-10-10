import Combine
import Foundation

/// 编辑一首媒体的标题 / 副标题 / 标签。
/// 打开时按 id 拉一次 `MediaDetail` 填充草稿，保存时写回并广播 `APIClient.didUpdateMedia`。
@MainActor
final class MediaEditViewModel: ObservableObject {
    let mediaID: String

    @Published var title = ""
    @Published var subtitle = ""
    /// 已选标签，是唯一的真实数据源；输入框只是「待确认」的草稿。
    @Published private(set) var tags: [String] = []
    /// 输入框里的草稿。输入逗号 / 分号 / 竖线或回车即确认成标签。
    @Published var tagInput = ""
    /// 曲库中已存在的全部标签（去重、按字母序），供下拉点选，避免手打出近义或错拼的新组。
    @Published private(set) var availableTags: [String] = []
    @Published private(set) var mediaType: MediaType = .audio
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    /// 下拉里最多同时列出的建议条数，超出的部分靠继续输入来收窄。
    private let maxSuggestions = 8

    private let api: APIClient

    init(mediaID: String, api: APIClient = .shared) {
        self.mediaID = mediaID
        self.api = api
    }

    // MARK: - 标题 / 副标题

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSubtitle: String? {
        let value = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var canSave: Bool {
        !trimmedTitle.isEmpty && !isSaving && !isLoading
    }

    // MARK: - 标签

    /// 输入框内容解析出的标签（逗号 / 分号 / 竖线分隔），用于「创建新标签」的判断。
    var pendingTags: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in tagInput.split(whereSeparator: { ",;|".contains($0) }) {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { continue }
            let key = tag.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(tag)
        }
        return result
    }

    /// 还没被选中的待创建标签。
    var creatableTags: [String] {
        pendingTags.filter { !isTagSelected($0) }
    }

    var canCreateFromInput: Bool {
        !creatableTags.isEmpty
    }

    /// 下拉建议：库里已有的标签中，未被选中、且包含当前输入片段的那些。
    private var matchingTags: [String] {
        let fragment = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return availableTags.filter { tag in
            guard !isTagSelected(tag) else { return false }
            guard !fragment.isEmpty else { return true }
            return tag.range(of: fragment, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var suggestions: [String] {
        Array(matchingTags.prefix(maxSuggestions))
    }

    /// 建议被截断了（列表比 `maxSuggestions` 长），界面上提示用户继续输入收窄。
    var hasMoreSuggestions: Bool {
        matchingTags.count > maxSuggestions
    }

    func isTagSelected(_ tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    func addTag(_ tag: String) {
        let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isTagSelected(value) else { return }
        tags.append(value)
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    func toggleTag(_ tag: String) {
        if isTagSelected(tag) {
            removeTag(tag)
        } else {
            addTag(tag)
        }
    }

    /// 把输入框里的草稿确认成标签并清空输入框。返回是否真的加进去了东西。
    @discardableResult
    func commitTagInput() -> Bool {
        let parsed = pendingTags
        tagInput = ""
        guard !parsed.isEmpty else { return false }
        for tag in parsed {
            addTag(tag)
        }
        return true
    }

    /// 输入框的写入口：敲到分隔符就当该标签已确认，省得还要按回车。
    /// 走这里而不是 `.onChange`，因为部署目标是 iOS 16，双参数版 `onChange` 用不了。
    func updateTagInput(_ value: String) {
        tagInput = value
        if value.contains(where: { ",;|".contains($0) }) {
            commitTagInput()
        }
    }

    // MARK: - 载入 / 保存

    func load() async {
        guard !isLoading, title.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        async let existingTags = fetchAvailableTags()
        do {
            let detail = try await api.fetchMediaDetail(id: mediaID)
            mediaType = detail.type
            title = detail.title
            subtitle = detail.subtitle ?? ""
            tags = Self.parseTags((detail.tags ?? []).joined(separator: ", "))
        } catch {
            errorMessage = "Failed to load this item."
        }
        availableTags = await existingTags
        isLoading = false
    }

    @discardableResult
    func save() async -> Bool {
        // 用户敲了标签但没按回车就直接点保存：先把草稿收下，避免丢内容。
        commitTagInput()
        guard canSave else { return false }
        isSaving = true
        errorMessage = nil
        do {
            try await api.updateMedia(
                id: mediaID,
                title: trimmedTitle,
                subtitle: trimmedSubtitle,
                tags: tags.isEmpty ? nil : tags
            )
            isSaving = false
            return true
        } catch {
            isSaving = false
            errorMessage = "Failed to save changes."
            return false
        }
    }

    /// 与导入时的解析规则保持一致：逗号 / 分号 / 竖线分隔，去空白、去空项、忽略大小写去重。
    static func parseTags(_ text: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in text.split(whereSeparator: { ",;|".contains($0) }) {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { continue }
            let key = tag.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(tag)
        }
        return result
    }

    /// 遍历曲库收集已有标签，去掉空白与重复项后按字母序排列（与 Playlists 的排序方式一致）。
    private func fetchAvailableTags() async -> [String] {
        guard let response = try? await api.fetchMediaList(type: nil, keyword: nil) else {
            return []
        }
        var seen: Set<String> = []
        var collected: [String] = []
        for item in response.items {
            for raw in item.tags ?? [] {
                let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty else { continue }
                let key = tag.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                collected.append(tag)
            }
        }
        return collected.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
