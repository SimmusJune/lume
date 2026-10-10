import SwiftUI

/// 编辑媒体的标题 / 副标题 / 标签。
/// 保存成功后由 `APIClient.didUpdateMedia` 通知驱动各列表自行刷新，这里只负责关掉自己。
struct MediaEditSheet: View {
    let mediaID: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MediaEditViewModel
    @FocusState private var isTagFieldFocused: Bool

    init(mediaID: String) {
        self.mediaID = mediaID
        _viewModel = StateObject(wrappedValue: MediaEditViewModel(mediaID: mediaID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $viewModel.title)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(true)
                }

                Section("Subtitle") {
                    TextField("Artist or description", text: $viewModel.subtitle)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(true)
                }

                tagsSection
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.save() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .task { await viewModel.load() }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - 标签

    private var tagsSection: some View {
        Section {
            tagInputField

            // 点进输入框就展开已有标签；继续打字则实时筛选。
            if showsSuggestions {
                ForEach(viewModel.suggestions, id: \.self) { tag in
                    Button {
                        viewModel.addTag(tag)
                    } label: {
                        suggestionRow(tag)
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.canCreateFromInput {
                    Button {
                        viewModel.commitTagInput()
                    } label: {
                        createRow
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Tags")
        } footer: {
            Text(tagsFooter)
        }
    }

    private var showsSuggestions: Bool {
        isTagFieldFocused || !viewModel.tagInput.isEmpty
    }

    private var tagInputField: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.tags.isEmpty {
                TagFlowLayout(spacing: 8) {
                    ForEach(viewModel.tags, id: \.self) { tag in
                        selectedChip(tag)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("Add a tag", text: Binding(
                    get: { viewModel.tagInput },
                    set: { viewModel.updateTagInput($0) }
                ))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isTagFieldFocused)
                .onSubmit { viewModel.commitTagInput() }

                if !viewModel.tagInput.isEmpty {
                    Button {
                        viewModel.commitTagInput()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "9dff85"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isTagFieldFocused = true }
        }
        .padding(.vertical, 2)
    }

    private func selectedChip(_ tag: String) -> some View {
        Button {
            viewModel.removeTag(tag)
        } label: {
            HStack(spacing: 6) {
                Text(tag)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove tag \(tag)")
    }

    private func suggestionRow(_ tag: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "9dff85"))

            Text(tag)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var createRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "9dff85"))

            Text(createRowTitle)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var createRowTitle: String {
        let creatable = viewModel.creatableTags
        guard let first = creatable.first else { return "Create tag" }
        return creatable.count == 1 ? "Create “\(first)”" : "Create \(creatable.count) tags"
    }

    private var tagsFooter: String {
        var text = "Tap the field to pick from tags already in your library, or type a new one. Each tag becomes a group under Playlists."
        if viewModel.hasMoreSuggestions {
            text += " Keep typing to narrow the list."
        }
        return text
    }
}

#Preview {
    MediaEditSheet(mediaID: "m_001")
}

/// 自动换行的横向流式布局：chip 宽度不一，放不下就换行（`LazyVGrid` 会强行等宽，不适合标签）。
private struct TagFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needsWrap = index > 0 && rowWidth + spacing + size.width > maxWidth
            if needsWrap {
                widestRow = max(widestRow, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (index == 0 ? 0 : spacing) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : widestRow, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
