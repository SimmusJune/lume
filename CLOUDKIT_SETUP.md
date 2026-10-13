# 家庭曲库 CloudKit 配置与验收

代码已启用 CloudKit、推送和共享邀请处理。发布前还需在 Apple Developer 后台及 CloudKit Console 完成以下配置。

1. 使用项目的 Team (`8PRQAX3V88`) 为 App ID `com.haohao.Lume` 启用 iCloud / CloudKit 和 Push Notifications，并关联容器 `iCloud.com.haohao.Lume`。在 Xcode 的 Signing & Capabilities 中确认签名后的 entitlements 与此一致。
2. 用已登录 iCloud 的真机安装开发版。打开「Profile → Family Library」，创建家庭曲库、导入歌曲、创建收藏夹并添加歌曲，播放一首歌曲至结束。这样开发环境会生成 `LumeMedia`、`LumeFavoriteGroup`、`LumeFavoriteEntry`、`LumePlaybackDevice`、`LumeReviewState` 和 `LumeProgress` 记录类型（字段 `payload` 为 Bytes）。
3. 在 CloudKit Console 检查开发环境中的上述记录类型，再将 schema 部署到 Production。TestFlight / App Store 使用 Production 环境；仅在开发环境创建记录不足以让正式版读写。
4. 用两个不同的 iCloud 账号在两台真机上安装同一版本。所有人各自完成 App 登录。创建者点击「Invite Family Members」，邀请成员；成员在自己的设备上打开邀请链接。确认双方可看到同一曲库及收藏，任一设备完整播放后双方的时长、次数和历史会更新；再检查复习状态及同一 iCloud 账号跨设备的续播位置。
5. 断网时增删歌曲或播放，联网并返回前台后检查同步。可在家庭曲库页面点击「Sync Now」查看错误和上次同步时间。

家庭曲库同步的是歌曲元数据、来源 URL、收藏关系及播放数据。现有曲库使用网络歌曲 URL；如果导入的是只在某台设备可访问的本地文件 URL，其他设备无法凭这个 URL 播放该文件。每个设备保留独立的个人曲库缓存，切换回个人曲库不会删除家庭曲库。家庭组目前通过 CloudKit 邀请链接加入，与 Apple 的“家人共享”成员资格没有自动绑定。
