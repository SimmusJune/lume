# 项目长期备忘（Lume）

## 技术栈与结构

- iOS SwiftUI App，纯本地媒体库 + 播放器。无服务端。
- `LocalLibraryStore`（`Lume/Services/MockStore.swift` 里的 actor）是**唯一数据源**，整体序列化成 JSON 存 Application Support（文件名来自 `AppConfig`）。启动时若无存档会 `importBundledDefaultLibrary()` 灌内置数据。
- `APIClient`（`Lume/Services/APIClient.swift`）是薄封装：读写走 `LocalLibraryStore`，**变更后发 NotificationCenter 通知**——`didDeleteMedia(object: mediaID)` / `didUpdateMedia(object: mediaID)`。
- **约定：视图通过 `.onReceive(NotificationCenter.default.publisher(for: APIClient.didXxx))` 自行刷新**，而不是让 ViewModel 去订阅。新增会改数据的操作时，记得同时发通知，否则各列表不会更新。
- `MediaRecord`（private struct）是落盘结构；`MediaItem`（列表，无 subtitle）与 `MediaDetail`（详情，有 subtitle，现已含 tags）是两套对外 DTO。
- **Playlists 没有实体**，是 `TagPlaylistsViewModel.buildGroups` 运行时按 `item.tags` 分组算出来的；`TagPlaylistsViewModel.untaggedGroupName` / `belongsToGroup(_:tag:)` 是唯一判定入口。
- `MediaCard`（`Lume/Views/Components/UIComponents.swift`）是共用的列表行组件，回调按声明顺序：`onFavorite` / `onDelete` / `onEdit`。加回调必须同步改全部 5 处调用点（ExploreView 两处、TagPlaylistsView、FavoritesListView 两处）。
- 弹窗约定：`NavigationStack` + `Form` + toolbar 的 Cancel/Confirm，见 `FavoritesPickerSheet` / `CreateFavoriteGroupSheet`。
- 编辑三项（title / subtitle / tags）统一走 `MediaEditSheet` + `MediaEditViewModel`（按 id 拉 detail 填草稿）。标签是 token 式输入：已选标签以 chip 内联展示（点 xmark 删），输入框聚焦即下拉列出「曲库已有标签」，输入片段实时筛选，未匹配上则给一行 `Create “xxx”`；敲到 `,` `;` `|` 即刻确认（走 `updateTagInput(_:)`，不用 `.onChange`）。`availableTags` 由 `fetchMediaList(type: nil)` 遍历全库 tags 去重、按 `localizedCaseInsensitiveCompare` 排序得到。换行 chip 布局用的是 `MediaEditSheet.swift` 里的 `TagFlowLayout: Layout`（`LazyVGrid` 会强行等宽，不适合长度不一的标签）。
- `project.pbxproj` 用 Xcode 16 的 `PBXFileSystemSynchronizedRootGroup`：**在 `Lume/` 下新增文件不用改工程文件**，自动纳入 target。

## 构建与验证（重要）

本机 `xcodebuild` / `swiftc` 曾报 `swift-plugin-server produced malformed response`，导致所有 `@State` / `#Preview` 宏展开失败（`cannot find '$xxx' in scope`、`'self' is immutable` 都是它的连带错误）。

**根因是宏插件路径没被解析**，不是 Xcode 坏了。加上插件路径即可完全正常：

```
-plugin-path /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/usr/lib/swift/host/plugins
```

- 直接类型检查（整个工程 0 error）：
  ```sh
  SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
  swiftc -typecheck -sdk "$SDK" -target arm64-apple-ios16.0-simulator \
    -plugin-path /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/usr/lib/swift/host/plugins \
    Lume/Models/*.swift Lume/Services/*.swift Lume/ViewModels/*.swift \
    Lume/Views/*.swift Lume/Views/Components/*.swift Lume/*.swift
  ```
  （注意 `Lume/*.swift` 已含 `AppConfig.swift`，别再显式列一次，否则报 "used twice"。）
  **`-target` 必须写 `ios16.0`**：工程 `IPHONEOS_DEPLOYMENT_TARGET = 16.0`，用 17.0 检查会漏掉「API 需要 iOS 17」这类错误（踩过一次：`.onChange(of:) { _, new in }` 双参数版在类型检查里过了，`xcodebuild` 才报 `only available in iOS 17.0 or newer`）。
- 完整构建（`** BUILD SUCCEEDED **`）：
  ```sh
  xcodebuild -project Lume.xcodeproj -scheme Lume -sdk iphonesimulator -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath ./.build-dd \
    build CODE_SIGNING_ALLOWED=NO \
    OTHER_SWIFT_FLAGS='$(inherited) -plugin-path /Applications/Xcode.app/.../iPhoneOS.platform/Developer/usr/lib/swift/host/plugins'
  ```
- 用默认 DerivedData 会被沙箱拒绝写入，务必带 `-derivedDataPath ./.build-dd`，**用完删掉**。
- 命令管道 `| head` 时 `$?` 是 head 的退出码，会掩盖失败：要写日志后 grep，或 `; echo exit=$?`。
