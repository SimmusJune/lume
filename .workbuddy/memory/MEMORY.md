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
- 播放统计统一在 `PlaybackStatsStore`（`Lume/Services/PlaybackStatsStore.swift`，`@MainActor ObservableObject`，`shared` 单例）：累计时长 + 按天秒数 + 每首的播放次数 `playCounts` + 完整播放历史 `history`，四份都存 UserDefaults（各自 JSON 键），也随库一起导出/导入。**`PlaybackStatsSnapshot` 手写了 `init(from:)` 做缺字段容错**，以后再加字段照此办理，别依赖合成的 decoder。
- 「完整播放一次」的判定点唯一：`PlayerViewModel.itemDidFinish(_:)`（`AVPlayerItemDidPlayToEndTime`）里调 `recordCompletedPlayback(mediaID:)`。
- **坑：别给 `MediaCard` / `PlayCountBadge` 这类「多处外部调用」的组件加 `private` 存储属性**——Swift 会把隐式 memberwise init 也变成 private，所有外部调用点直接编译不过。需要额外数据时，做成能自己订阅 store 的内部小视图（如 `PlayCountBadge`）再插进去。

## Smart Review（间隔重复播放模式）

- `PlayMode` 第五档 `.review`（label `"Smart Review"`，icon `brain.head.profile`）。**给它加 case 是安全的**：`@AppStorage("lume.playMode")` 存的是 rawValue 字符串，老存档不会失效。
- 两层间隔，别混在一起：
  - **跨天档位** = `SpacedRepetitionStore`（`Lume/Services/SpacedRepetitionStore.swift`，UserDefaults key `lume.review.states`）。`ReviewIntervals.days = [1,2,4,8,16,30]` 对应 box 0…5；完整听完 `recordCompleted` 升一档，中途切走 `recordSkipped` 退一档。
  - **会话内递进穿插** = `SpacedRepetitionScheduler`（`Lume/Services/SpacedRepetitionScheduler.swift`，纯函数 `buildQueue(pool:states:now:)`）。间隔上限 [2,4] 首，**按池子大小自适应收缩**；只对主线前 6 首且到期的歌登记重复。
- **绝对不要复用 `PlaybackStatsStore.history` 做复习排期**：它 `historyMaxAgeDays = 7` 每天裁，跨天排期活不过一周，而且只记「完整播完」、记不了「中途切走」。
- **约定：跨天档位与播放模式无关**。`itemDidFinish` 里无条件 `reviewStore.recordCompleted(...)`，档位一直在累积，切进 Smart Review 才有真实依据。
- **判定「中途切走」的唯一入口是 `advanceTrack(auto: false)`**（`nextTrack()` 是唯一 `auto: false` 调用点），且要求 `positionSeconds >= 3`，否则家长连点下一首挑歌会被当成孩子跳过。
- **队列页必须用 `PlayerViewModel.displayQueueIDs`（去重版）**：`reviewQueue` 里同一首会出现 2~3 次，直接喂给 `ForEach(id: \.id)` 会撞 id。
- 列表导出的 payload 已是 **version 3**，新增 `review_states`；`ImportReport` 新增字段一律给默认值，免得每个构造点都要改。
- **坑：断言「隔 N 首」不能数数组下标差**——中间会夹着别的歌的重复项，下标差会偏大。要数两次出现之间有几首「首次出现」的歌。

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
