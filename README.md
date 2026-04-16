# thatDay

`thatDay` 是一个 iOS Journal App。它以 `lumina` 原型为视觉和交互参考，但做了几处面向真实使用的调整：

- 主界面改成原生 `TabView`，四个页签分别是 `Journal / Calendar / Search / Blog`
- `Journal` 顶部左侧保留日历入口，右侧改为设置页
- `Blog` 与 `Journal` 数据隔离，但两者都会进入统一搜索
- 设置页负责 CloudKit 仓库分享与邀请链接接入

CloudKit 分享能力的实现方式参考了 `/Users/wangyu/code/homeLibraryApp/homeLibrary` 里对 `CKShare`、`UICloudSharingController` 和分享链接接收流程的组织方式，并按当前项目做了简化。

## 功能概览

### Journal

- 默认展示当天日期
- 按“同月同日”聚合同一天历年的 Journal
- 每个条目显示图片、标题、摘要，卡片下方显示星期
- 支持新增、编辑、删除 Journal
- 左上角日历按钮可跳转到 `Calendar`

### Calendar

- 自定义月视图日历
- 支持前后切换月份
- 有 Journal 的日期会打点
- 点击某天会回到 `Journal` 并切到对应日期

### Search

- 即时搜索标题和正文
- 搜索范围同时覆盖 `Journal` 和 `Blog`

### Blog

- 时间流展示 Blog 内容
- 支持新增、编辑、删除
- 每篇文章保持“一张图片 + 一段长文本”的编辑模型
- Blog 不会进入 Journal/Calendar，但会进入 Search

### Settings / CloudKit

- 设置页位于 Journal 右上角
- 支持通过 `UICloudSharingController` 生成邀请链接
- 支持在邀请时限定权限：
  - `仅查看`
  - `允许编辑`
- 支持粘贴 iCloud 分享链接并接入共享仓库
- AppDelegate / SceneDelegate 已接入 `CKShare.Metadata` 分发，系统接受分享时可进入应用处理

## 存储设计

应用当前使用“本地 JSON 仓库 + CloudKit 共享快照”模型：

- 本地仓库：
  - `Application Support/thatDay/repository.json`
  - `Application Support/thatDay/descriptor.json`
  - `Application Support/thatDay/images/`
- CloudKit：
  - 以单独 `CKRecordZone` 保存整个仓库快照
  - 通过 `CKShare(recordZoneID:)` 分享该仓库 zone

这样做的原因：

- 方便在单元测试里稳定验证读写和切换共享仓库的行为
- 满足“整个仓库可分享”的需求
- 保持当前项目体量可控，不引入额外的 Core Data / SwiftData 迁移复杂度

## 关键文件

- `/Users/wangyu/code/thatDay/thatDay/App/AppStore.swift`
- `/Users/wangyu/code/thatDay/thatDay/Services/CloudRepositoryService.swift`
- `/Users/wangyu/code/thatDay/thatDay/Services/LocalRepositoryStore.swift`
- `/Users/wangyu/code/thatDay/thatDay/Features/Journal/JournalView.swift`
- `/Users/wangyu/code/thatDay/thatDay/Features/Calendar/CalendarView.swift`
- `/Users/wangyu/code/thatDay/thatDay/Features/Search/SearchView.swift`
- `/Users/wangyu/code/thatDay/thatDay/Features/Blog/BlogView.swift`
- `/Users/wangyu/code/thatDay/thatDay/Features/Settings/SettingsView.swift`

## 运行

```bash
xcodebuild -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' build
```

也可以直接在 Xcode 里打开 `/Users/wangyu/code/thatDay/thatDay.xcodeproj` 运行 `thatDay` scheme。

## 测试

全量测试命令：

```bash
xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324'
```

当前覆盖包括：

- 单元测试
  - Journal 同日跨年分组
  - 搜索命中 Journal / Blog
  - 日历网格生成
  - Blog 持久化
  - 共享链接接入后的仓库切换与只读权限
- UI 测试
  - Calendar 选日回跳 Journal
  - Blog 新建并进入 Search
  - Journal 右上角打开 Settings

最近一次完整测试结果：

- `xcodebuild test` 成功
- xcresult:
  - `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.16_23-29-16-+0800.xcresult`

## CloudKit 配置说明

要在真机或自己的 iCloud 环境里完整使用分享功能，需要确认：

1. Apple Developer 里已为 `yu.thatDay` 开启 iCloud / CloudKit capability
2. CloudKit 容器 `iCloud.yu.thatDay` 已创建
3. 当前签名团队和 bundle id 与 entitlement 保持一致
4. 设备已登录 iCloud

如果只是本地开发和测试，不依赖 CloudKit 的页面与测试已经可以独立运行。
