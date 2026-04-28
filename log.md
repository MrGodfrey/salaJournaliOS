# log

## 2026-04-16 23:15

- 完成应用主体重构，替换模板项目为真实的 iOS Journal App
- 落地 `Journal / Calendar / Search / Blog` 四个页面
- 建立本地仓库存储：`repository.json + descriptor.json + images/`
- 增加 Journal / Blog 的新增、编辑、删除能力

## 2026-04-16 23:18

- 完成 Settings 页面
- 接入 CloudKit 仓库快照存储与 `CKShare` 分享
- 增加邀请权限控制：`仅查看 / 允许编辑`
- 接入分享链接粘贴接受，以及 AppDelegate / SceneDelegate 的 `CKShare.Metadata` 分发

## 2026-04-16 23:31

- 补齐单元测试和 UI 测试
- 修复样例数据的跨时区日期偏移问题
- 完整执行 `xcodebuild test`，确认当前测试套件通过

## 2026-04-17 07:46

- 调整文章交互：卡片统一只负责进入阅读页，不再支持左滑编辑/删除
- 新增独立文章阅读页的编辑流：阅读模式进入、`编辑` 切换、编辑态 `取消 / 保存 / 删除`
- 删除编辑器里的“图片链接”输入，只保留相册选图
- 重做 Journal 顶部日期操作：去掉左右滑切日，改为 `Previous / Next` 小按钮，中心日期点击回到今天
- 重做文章卡片元信息展示，统一为 `星期 + 月日年`，并移除 Journal 卡片下方单独星期
- 搜索页空输入不再展示结果
- 只保留一篇引导用测试文章，清理原有样例内容
- 更新单元测试和 UI 测试以匹配新的阅读/编辑流与 Journal 日期切换按钮
- 核查 `xcodebuild` 生成 simulator clone 的原因，确认来自默认并行测试
- 使用 `-parallel-testing-enabled NO` 串行执行完整测试，避免额外 clone 模拟器
- 完整执行测试命令并通过：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO`

## 2026-04-17 07:52

- 补充记录测试运行行为：默认并行测试会触发多个 simulator clone，这不是业务代码导致的问题
- 确认 `thatDayUITestsLaunchTests` 的 `runsForEachTargetApplicationUIConfiguration = true` 会让启动测试按多种配置重复执行
- 同步更新 README 中最近一次完整测试产物路径：
  - `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_07-48-08-+0800.xcresult`

## 2026-04-17 07:56

- 去掉文章卡片所在列表行默认显示的向右箭头，Journal / Blog / Search 三处统一保留完整卡片视觉

## 2026-04-17 14:57

- 补记今天早些时候遗漏到 `log.md` 的改动：
  - 忽略 Xcode 用户态文件，减少仓库里的无关噪音
  - 补齐 `App Store / Play Store` 商店素材与 asset metadata
  - 增加应用展示名、应用分类、非加密声明、相册访问说明，以及 CloudKit / ubiquity 相关 entitlement
  - 将本地存储从单仓库目录升级为 `preferences.json + repositories.json + repositories/<repository-id>/...` 的多仓库结构
  - 新增 `RepositoryReference` / `AppPreferences` / `RepositoryLibraryStore` / `RepositoryArchiveService`
  - 设置页补齐共享仓库更新提醒、Face ID、ZIP 导入导出、默认仓库选择、当前仓库切换与清空当前仓库
  - 接通远端变更刷新、本地通知点击跳转和共享仓库订阅
  - 重构文章卡片布局，统一无箭头卡片视觉和信息层次
- 新增图片插入压缩链路：相册选图后立即压缩，并在保存时再次兜底，保证单张落盘图片控制在 `100KB` 以下
- 编辑页补充用户提示：明确说明插图会自动压缩到 `100KB` 以内
- 新增单元测试 `testStoreImageCompressesImportedPhotoBelow100KB`，并同步修正仓库导入导出测试里的图片写入用例
- 按新的仓库现状重写 `README.md`：
  - 先写设计方式，再写需求完成情况
  - 单独补全用户接口、架构层、已知边界、运行与测试
  - 明确写入“每次功能改动后都要检查 `log.md` 和 `README.md` 是否同步更新”
- 完整执行测试并通过：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO`
  - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_14-54-43-+0800.xcresult`

## 2026-04-17 15:15

- 修复共享仓库通知订阅：共享所有者继续使用 `CKRecordZoneSubscription`，共享成员改用 `CKDatabaseSubscription`，避免在 shared database 上开启 zone subscription 时触发 `Subscription evaluation type not allowed in shared database`
- Journal 和 Blog 页面新增下拉刷新，手动下拉会立即拉取共享仓库最新快照
- 明确应用启动和每次回到前台时都会自动刷新共享仓库，并复用同一条刷新链路
- 修复共享仓库图片缺失：共享快照现在会携带文章引用到的本地图片，其他设备拉取后会自动恢复到本地 `images/` 缓存
- 新增单元测试：
  - `testManualRefreshUpdatesSharedRepositoryAndMaterializesImages`
  - `testSavingSharedRepositoryUploadsEmbeddedImagesToCloud`
- 完整执行测试并通过：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO`
  - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_15-12-44-+0800.xcresult`

## 2026-04-17 15:31

- 修复生物识别兼容性：
  - `Info.plist` 补齐 `NSFaceIDUsageDescription`，避免在支持 Face ID 的设备上打开生物识别开关时直接闪退
  - 设置页和锁屏层文案统一改为“生物识别解锁 / 生物识别保护”，不再把 Touch ID 设备误写成 Face ID
  - `AppStore` 的前台认证状态机改为只在真正从后台回到前台后再触发验证，避免 Touch ID 弹窗本身引起 `.active` 回调时进入重复认证死循环
- 加固本地图像引用解析：
  - 兼容旧的绝对路径 / `file://` 图片引用，统一回落到仓库内 `images/` 文件名
  - 如果本地图片文件已经不存在，则不再把失效的 `file://` URL 继续交给 `AsyncImage`
- 新增单元测试：
  - `testBiometricLockAuthenticatesOnLaunchAndOnlyReauthenticatesAfterBackground`
  - `testImageURLNormalizesLegacyLocalReferencesAndSkipsMissingFiles`
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO`
    - 单元测试 `16/16` 通过
    - UI 测试主体与 Launch Tests 均显示通过，但整轮执行里有两条 UI 用例被 runner 以 `signal kill` 重启，导致命令返回 `65`
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_15-25-26-+0800.xcresult`
  - 单独重跑上述两条 UI 用例并通过：
    - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testCreateBlogPostAppearsInSearch -only-testing:thatDayUITests/thatDayUITests/testCreateEditAndDeleteBlogPost`
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_15-29-14-+0800.xcresult`
  - `xcodebuild build -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=E86E7D78-27BA-41D7-82F4-FE3AF76FB0DA'` 构建通过，确认 iPad simulator 编译正常

## 2026-04-17 15:36

- 修复 ZIP 导入权限问题：从系统文件选择器拿到外部 ZIP 后，导入链路现在会先 `startAccessingSecurityScopedResource()`，在整个解压过程结束后再释放访问权限，避免真机上误报“没有足够的权限”
- 为导入失败补充更明确的用户提示：当底层返回 `fileReadNoPermission` 时，统一映射为“无法读取所选 ZIP 文件，请重新选择后再试。”
- 新增单元测试：
  - `testImportArchiveStartsAndStopsSecurityScopedAccess`
  - `testImportArchiveMapsNoPermissionToUserFacingError`
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `18/18` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_15-36-43-+0800.xcresult`

## 2026-04-17 15:47

- 修复导入后当前设备看不到本地图片的问题：仓库内 `file://` 图片现在统一改为直接用 `UIImage(contentsOfFile:)` 从沙盒文件读取，避免导入过程中同一路径文件被覆盖后，当前设备继续沿用 `AsyncImage` 的失败态

## 2026-04-17 16:59

- 把 CloudKit 生产 schema 缺失错误翻译成明确提示：当服务端返回 `Cannot create new type RepositoryRoot in production schema` 时，界面会直接提示先部署 production schema，再重新生成邀请链接
- 新增单元测试，覆盖直接错误和 `partialFailure` 嵌套错误两条 CloudKit 生产 schema 提示映射路径
- README 补充 CloudKit production schema 部署前置条件，并明确当前共享快照使用的 `RepositoryRoot` 记录类型与字段
- 调整图片展示入口：
  - 文章卡片封面
  - 文章详情页头图
  - 编辑页已有图片预览
- 新增单元测试：
  - `testRepositoryLocalImageLoadsFileURLAndSkipsRemoteURL`
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `21/21` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_15-48-54-+0800.xcresult`

## 2026-04-17 16:10

- 继续定位“导出 ZIP 再导回同仓库后图片消失”：
  - 新增回归测试 `testExportThenImportIntoSameRepositoryKeepsLoadableImage`
  - 新增路径别名回归测试 `testRepositoryArchiveRoundTripRestoresImagesForTmpSymlinkPaths`
- 确认根因不在文章数据本身，而在归档服务用绝对路径字符串替换计算相对路径：
  - 当同一目录可能同时出现 `/tmp/...` 和 `/private/tmp/...` 这类等价前缀时，图片会被打包到错误的 `privateimages/` 路径
  - 导入后 `repository.json` 里的 `imageReference` 仍然是 `images/<uuid>.jpg` 语义，但实际图片文件落在错误目录，所以当前设备读不到
- 修复 `RepositoryArchiveService`：
  - 导入导出时统一基于标准化后的 URL 计算仓库内相对路径，避免图片被归档到错误目录
  - 保留图片视图刷新版本号，在导入、换图、共享刷新后强制重建本地图片视图，避免同路径文件替换后停留在旧状态
- 手工验证记录：
  - 在本地调试场景里先复现出无图卡片，再在修复后确认 Blog 卡片封面恢复
  - 修复后截图：`/tmp/thatday-manual-eFVbuF/self-import-blog-fixed-2.png`
  - 修复后仓库图片已回到正确目录：`/tmp/thatday-manual-eFVbuF/repositories/local/images/EEE4CF13-0E8F-48F0-A8A2-248B06A20C6B.jpg`
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `23/23` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_16-11-21-+0800.xcresult`

## 2026-04-17 15:44

- 共享仓库更新提醒补上应用角标：
  - 共享仓库在应用未打开期间收到远端更新时，会把应用角标置为 `1`
  - 只要应用进入前台，或者用户关闭“共享仓库更新提醒”，就会立即清空角标
  - 前台自动刷新仍然保留现有通知链路，但不会在应用已经打开后再把角标补回去
- `README.md` 同步补充共享更新角标规则和设置项说明
- 新增单元测试：
  - `testSharedRepositoryPushRefreshSetsBadgeAndActiveClearsIt`
  - `testForegroundRefreshDoesNotRestoreBadgeAfterAppOpens`
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `20/20` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_15-43-41-+0800.xcresult`

## 2026-04-17 17:03

- 追加记录本次 CloudKit 生产环境修复说明：
  - 把 `Cannot create new type RepositoryRoot in production schema` 翻译成明确提示，直接引导先部署 production schema 再重试邀请
  - 新增单元测试覆盖直接错误和 `partialFailure` 嵌套错误两条提示映射路径
  - README 补充 CloudKit production schema 前置条件，并明确共享快照使用的 `RepositoryRoot` 记录类型与字段

## 2026-04-17 17:02

- 收口本次修复细节：
  - 保持 `AppStore` 的 `@MainActor` 隔离不变，仅把新加的 CloudKit 提示映射测试标记为 `@MainActor`
  - 重新执行定向单元测试并通过：
    - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/thatDayTests/testUserFacingMessageMapsCloudKitProductionSchemaError -only-testing:thatDayTests/thatDayTests/testUserFacingMessageMapsNestedCloudKitProductionSchemaError`
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_17-01-46-+0800.xcresult`

## 2026-04-17 17:34

- 完成一轮 UI 英文化收口：
  - SwiftUI 页面、空态、按钮、弹窗、错误提示、CloudKit 共享提示、导入导出提示、示例文章文案全部改为英文
  - `Info.plist` 里的相册 / Face ID 权限说明改为英文
  - App 显示名改为 `thatDay`
- 应用语言偏好切到英文：
  - 根视图注入英文 `Locale`
  - 日期标题、月份、星期和卡片日期统一走英文格式化
- 只读仓库交互收紧：
  - `Journal` 和 `Blog` 在 `canEditRepository == false` 时不再渲染右下角新增按钮，而不是仅做禁用
- `README.md` 已同步更新：
  - 补充 UI 默认英文
  - 补充只读仓库不显示 `Journal / Blog` 新建按钮
- 新增 / 更新测试：
  - 更新单元测试中的英文提示断言
  - 更新 UI 测试中的英文文案断言
  - 新增 UI 测试 `testReadOnlyRepositoryHidesCreateButtonsInJournalAndBlog`
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO`
  - 整套测试通过：`thatDayTests 25/25`，`thatDayUITests 13/13`
  - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_17-31-57-+0800.xcresult`

## 2026-04-17 17:59

- Calendar 页面重排并对齐新的头部交互：
  - 月历放到上方，统计卡片放到下方
  - 头部左侧改为 `Month Year` + 小箭头，右侧提供上一个月 / 下一个月按钮
  - `Today` 移到顶部工具栏，保留 `Settings`
- Calendar 统计改成真实内容统计：
  - `Journaled Days` 显示 Journal 篇数
  - `Blogs` 显示 Blog 篇数
  - `Written` 统计全部 Journal + Blog 的总字数

## 2026-04-17 22:29

- 调整 Journal 展示：
  - 去掉年份分组标题，改成直接展示文章卡片
  - Journal 卡片上的日期改为只显示年份
  - Journal 标题改为可选，空标题时卡片和详情页不再强行显示占位标题
- 编辑页补充图片删除能力：
  - 图片预览下方新增 `Delete Image`
  - 保存时支持移除已有插图
  - 仓库快照保存后会自动清理已失去引用的本地图片文件
- 新增 / 更新测试：
  - 单元测试新增 `testSavingJournalEntryAllowsEmptyTitle`
  - 单元测试新增 `testRemovingImageFromEntryClearsReferenceAndDeletesStoredFile`
  - UI 测试新增 `testCreateJournalEntryWithoutTitle`
  - 原 `Journal` 跨年分组测试同步改成扁平排序断言
- `README.md` 已同步更新本次用户可见行为
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO`
  - 整套测试通过：`thatDayTests 33/33`，`thatDayUITests + LaunchTests 19/19`
  - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_22-24-20-+0800.xcresult`
  - 字数统计改用 `NLTokenizer` 做分词，缺省回退到按空白 / 标点过滤
- Blog 补上标签能力：
  - 文章模型新增 `blogTag`
  - 仓库快照新增仓库级 `blogTags`，默认标签为 `Reading / Watching / Game / Trip / note`
  - Blog 列表顶部新增 segmented control 标签筛选，支持 `All`
  - Blog 卡片、详情页在日期后显示标签；编辑页可选择标签；新建 Blog 默认落到 `note`
- Settings 新增 Blog 标签管理：
  - 支持新增、排序、删除标签
  - 删除已使用标签时，会弹出重分配对话框，要求先把旧标签文章迁移到另一个标签
  - 标签配置跟随本地持久化、共享快照和 ZIP 导入导出一起保存
- `README.md` 已同步更新：
  - 补充 Calendar 新布局和统计语义
  - 补充 Blog 标签显示、筛选和 Settings 管理说明
  - 更新当前测试覆盖和最近一次完整验证记录
- 新增 / 更新测试：
  - 单元测试新增 `testBlogEntriesDefaultToNoteTagAndWrittenStatisticsCountAllEntries`
  - 单元测试新增 `testDeletingBlogTagReassignsEntriesAndPersists`
  - UI 测试新增 `testBlogTagFilterShowsOnlyMatchingPosts`
  - 同步修正日历、设置页和无图详情布局相关 UI 断言
- 验证记录：
  - `xcodebuild build -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324'`
    - 构建通过
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `27/27` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_17-50-12-+0800.xcresult`
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests`
    - UI 测试 `14/14` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_17-56-15-+0800.xcresult`

## 2026-04-17 18:12

- 收紧 Calendar 页面视觉：
  - 月份年份标题改成单行显示，字号下调到只略大于日期数字，避免在窄屏上换行
  - 月历卡片内部间距进一步收紧，让内容更贴近卡片边框
- 修复 Blog 顶部标签筛选条布局 bug：
  - 移除原先基于 `UISegmentedControl` 的实现，避免筛选条被错误拉成巨大圆形
  - 改成 SwiftUI 原生的横向可滚动圆角矩形标签条
  - 标签过多时支持左右滑动，英文标签保持完整显示，不再被截断
- 更新 UI 测试：
  - `testBlogTagFilterShowsOnlyMatchingPosts` 改为使用新的标签条可访问性标识
- 验证记录：
  - `xcodebuild build -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324'`
    - 构建通过
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testCalendarMonthPickerAndTodayReturnToCurrentMonth -only-testing:thatDayUITests/thatDayUITests/testBlogTagFilterShowsOnlyMatchingPosts`
    - UI 测试 `2/2` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_18-10-59-+0800.xcresult`

## 2026-04-17 18:21

- 调整 Calendar 统计区：
  - 移除 `Journaled / Blogs / Written` 三张统计卡片里的图标
  - `Written` 在字数超过 `1000` 后改为 `1.1K` 这一类缩写格式，不再在五位数时直接铺满数字
- 在三张统计卡片下方新增 Blog 标签统计区：
  - 标签保持仓库里的原始写法，不做全大写转换
  - 每个标签显示对应 Blog 文章数量
  - 点按标签统计后会切换到 `Blog` tab，并直接带上对应标签筛选
- 状态与测试补充：
  - Blog 标签筛选状态上提到 `AppStore`，让 `Calendar` 和 `Blog` 共用同一份标签选择
  - 新增单元测试覆盖字数缩写和标签跳转状态
  - 新增 UI 测试覆盖从 `Calendar` 标签统计跳转到 `Blog` 标签筛选
- `README.md` 已同步更新：
  - 补充 Calendar 标签统计入口
  - 补充 `Written` 的缩写显示规则

## 2026-04-17 18:26

- 补充测试收口：
  - `Calendar` 标签统计的 UI 测试在横屏下需要先下滑到统计区，因此为该用例补上滚动步骤
- 验证记录：
  - `xcodebuild clean test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `29/29` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Run-thatDay-2026.04.17_18-23-29-+0800.xcresult`
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testBlogTagFilterShowsOnlyMatchingPosts -only-testing:thatDayUITests/thatDayUITests/testCalendarTagStatisticOpensBlogWithMatchingFilter`
    - UI 测试 `2/2` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_18-25-35-+0800.xcresult`

## 2026-04-17 18:35

- 调整 Settings 的仓库与标签管理布局：
  - `Repository Status` 里的 `Current Repository` 改成可直接切换的选择入口
  - 移除重复的仓库状态说明文案，不再显示 `Current repository: ... Access: ...`
  - `Blog Tags` 区块前移到仓库状态后面
  - `Advanced` 里删除 `Current Repository` 设置，只保留启动默认仓库和清空仓库
- 修复 Blog 标签管理交互：
  - 标签行支持直接拖动排序，排序结果会持久化到当前仓库
  - 左滑删除改成先弹确认，不再出现标签先消失又回来的跳动
  - 删除已使用标签时，改为使用居中的系统确认框来选择迁移目标，不再使用气泡式对话框
- `README.md` 已同步更新：
  - 补充 `Repository Status` 里的当前仓库切换入口
  - 补充 Blog 标签拖动排序和新的删除确认方式
- 新增 / 更新测试：
  - 单元测试新增 `testMovingBlogTagRelativeToAnotherTagPersists`
  - UI 测试更新 `testSettingsSheetOpensFromJournal`，校验新的仓库选择入口和标签区位置
- 验证记录：
  - `xcodebuild build -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324'`
    - 构建通过
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/thatDayTests/testDeletingBlogTagReassignsEntriesAndPersists -only-testing:thatDayTests/thatDayTests/testMovingBlogTagRelativeToAnotherTagPersists -only-testing:thatDayUITests/thatDayUITests/testSettingsSheetOpensFromJournal`
    - 定向测试 `3/3` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_18-34-10-+0800.xcresult`

## 2026-04-17 18:42

- 调整 Calendar 布局细节：
  - 继续收紧月历卡片横向内边距，让日期数字更贴近卡片边缘
  - 月份标题左边缘改为和下方星期列首项对齐
  - 三张统计卡片压缩上下留白，减少无效垂直空间
  - 标签统计改成按内容宽度自适应并自动换行，不再使用固定宽度列
- `README.md` 已同步更新：
  - 补充 Calendar 月份标题对齐、统计卡片留白和标签宽度规则
- 新增 / 更新测试：
  - 新增 UI 测试 `testCalendarTagStatisticsUseContentWidth`
- 验证记录：
  - `xcodebuild build -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324'`
    - 构建通过
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testCalendarMonthPickerAndTodayReturnToCurrentMonth -only-testing:thatDayUITests/thatDayUITests/testCalendarTagStatisticOpensBlogWithMatchingFilter -only-testing:thatDayUITests/thatDayUITests/testCalendarTagStatisticsUseContentWidth`
    - 测试 bundle 在模拟器内加载失败，错误为 `Trying to load an unsigned library`
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_18-42-03-+0800.xcresult`

## 2026-04-17 18:48

- 修复 Settings 页 Blog 标签排序交互：
  - 标签列表改为使用系统原生重排，长按拖起后其余标签会实时让位，放手后立即完成排序并持久化到当前仓库
  - 标签行补充稳定的可访问性标识，便于 UI 测试直接定位并执行拖拽
- `README.md` 已同步更新：
  - 补充 Blog 标签长按拖动时会实时让位、放手后完成排序
- 新增 / 更新测试：
  - 新增 UI 测试 `testSettingsBlogTagsReorderWithLongPressDrag`
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/thatDayTests/testMovingBlogTagRelativeToAnotherTagPersists -only-testing:thatDayUITests/thatDayUITests/testSettingsSheetOpensFromJournal -only-testing:thatDayUITests/thatDayUITests/testSettingsBlogTagsReorderWithLongPressDrag`
    - 定向测试 `3/3` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_18-47-59-+0800.xcresult`

## 2026-04-17 19:06

- 删除新安装应用里的 `Welcome to thatDay` 引导页：
  - 本地仓库首次启动不再预置示例 Journal，默认以空仓库进入 `Journal`
  - 首装时会立即持久化空快照，避免后续重新加载时把欢迎页写回来
  - 预览 / 异常回退路径也统一改为空数据，避免再次出现同一条欢迎内容
- `README.md` 已同步更新：
  - 补充首次进入时默认显示空仓库与空状态，不再出现 `Welcome to thatDay`
- 新增 / 更新测试：
  - 新增单元测试 `testFreshInstallStartsWithEmptyLocalRepository`
  - 新增 UI 测试 `testFreshInstallShowsEmptyJournalInsteadOfWelcomeEntry`
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `30/30` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_19-04-44-+0800.xcresult`
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testFreshInstallShowsEmptyJournalInsteadOfWelcomeEntry -only-testing:thatDayUITests/thatDayUITests/testSearchRequiresQueryBeforeShowingResults`
    - 定向 UI 测试 `2/2` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_19-05-25-+0800.xcresult`

## 2026-04-17 22:30

- 调整 Journal 展示：
  - 去掉年份分组标题，改成直接展示文章卡片
  - Journal 卡片上的日期改为只显示年份
  - Journal 标题改为可选，空标题时卡片和详情页不再强行显示占位标题
- 编辑页补充图片删除能力：
  - 图片预览下方新增 `Delete Image`
  - 保存时支持移除已有插图
  - 仓库快照保存后会自动清理已失去引用的本地图片文件
- 新增 / 更新测试：
  - 单元测试新增 `testSavingJournalEntryAllowsEmptyTitle`
  - 单元测试新增 `testRemovingImageFromEntryClearsReferenceAndDeletesStoredFile`
  - UI 测试新增 `testCreateJournalEntryWithoutTitle`
  - 原 `Journal` 跨年分组测试同步改成扁平排序断言
- `README.md` 已同步更新本次用户可见行为
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO`
  - 整套测试通过：`thatDayTests 33/33`，`thatDayUITests + LaunchTests 19/19`
  - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_22-24-20-+0800.xcresult`

## 2026-04-17 22:44

- Blog 卡片新增图片布局能力：
  - 保留现有横版封面卡片
  - 新增竖版封面卡片，带图文章可切换为左侧竖图、右侧标题 / 两行摘要 / 日期标签布局
  - 旧仓库数据缺少布局字段时，默认回退到横版，保持兼容
- Blog 编辑页新增 `Landscape / Portrait` segmented control，用来在两种带图卡片布局之间二选一切换
- 文章模型和保存链路新增 `blogImageLayout` 持久化字段，并同步接入详情页编辑流
- `README.md` 已同步更新：
  - 补充 Blog 横版 / 竖版卡片布局说明
  - 补充编辑页图片布局切换选项
  - 补充 `EntryRecord` 和 `repository.json` 会保存 Blog 图片卡片布局
- 新增 / 更新测试：
  - 单元测试新增 `testSavingBlogEntryPersistsSelectedImageLayout`
  - 单元测试新增 `testLoadingLegacyBlogEntryDefaultsImageLayoutToLandscape`
  - UI 测试新增 `testBlogEditorPersistsImageLayoutSelection`
  - UI 测试新增 `testPortraitBlogCardUsesSideBySideLayout`
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `35/35` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_22-41-52-+0800.xcresult`
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testBlogEditorPersistsImageLayoutSelection -only-testing:thatDayUITests/thatDayUITests/testPortraitBlogCardUsesSideBySideLayout`
    - 定向 UI 测试 `2/2` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_22-43-22-+0800.xcresult`

## 2026-04-17 22:58

- 微调竖版 Blog 展示：
  - 竖版文章卡片右侧摘要从 `2` 行放宽到 `4` 行
  - 竖版文章详情页头图改为完整显示，不再裁剪
  - 补充详情页竖版头图的可访问性标识，便于 UI 测试稳定定位
- `README.md` 已同步更新：
  - 将竖版 Blog 卡片描述改为 `四行摘要`
  - 补充竖版 Blog 详情页题图完整显示规则
- 新增 / 更新测试：
  - UI 测试新增 `testPortraitBlogDetailShowsFullCoverWithoutCropping`
  - UI 测试里的竖版种子图片改为真实竖图，避免用方图误判布局
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testBlogEditorPersistsImageLayoutSelection -only-testing:thatDayUITests/thatDayUITests/testPortraitBlogCardUsesSideBySideLayout -only-testing:thatDayUITests/thatDayUITests/testPortraitBlogDetailShowsFullCoverWithoutCropping`
    - 定向 UI 测试 `3/3` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_22-57-02-+0800.xcresult`

## 2026-04-17 23:05

- 调整 Journal 卡片日期展示：
  - 原先只显示年份
  - 现在改为显示 `星期, 年份`，例如 `Thursday, 2026`
- `README.md` 已同步更新：
  - 首页能力说明里的 Journal 卡片日期描述改成 `星期 + 年份`
  - `Journal` 章节补充新的卡片日期示例
- 新增 / 更新测试：
  - 单元测试新增 `testJournalCardDateIncludesWeekdayBeforeYear`

## 2026-04-17 23:10

- 继续收紧竖版 Blog 详情页头图展示：
  - 保持题图全宽展示，不裁左右
  - 为竖图详情头图增加最大高度限制，避免占满首屏
  - 当题图高度超过上限时，改为居中裁掉上下超出的部分
- `README.md` 已同步更新竖版详情页头图规则说明
- 更新测试：
  - 将 UI 测试改为 `testPortraitBlogDetailCapsCoverHeightWithoutCroppingWidth`

## 2026-04-17 23:11

- 补充 Journal 卡片日期展示的验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/thatDayTests/testJournalCardDateIncludesWeekdayBeforeYear`
    - 定向单元测试 `1/1` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_23-05-59-+0800.xcresult`

## 2026-04-17 23:14

- 收口竖版 Blog 详情页头图高度限制实现：
  - 竖版头图改为挂在固定最大高度容器内渲染，避免继续占满手机首屏
  - 仍保持横向全宽展示；超出上限的部分继续通过居中裁切消化
  - 为详情页头图补了一个透明可访问定位层，让 UI 测试读取到实际显示框，而不是内部图片原始尺寸
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testPortraitBlogDetailCapsCoverHeightWithoutCroppingWidth`
    - 定向 UI 测试 `1/1` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_23-14-25-+0800.xcresult`

## 2026-04-20 20:05

- 修复 Xcode / Swift 6 测试编译里的 actor 隔离错误：
  - 在 app target 默认 `MainActor` 隔离开启的前提下，把纯数据模型、本地仓库存储、归档服务显式标记为 `nonisolated`
  - 让 `String` / `Calendar` / `URL` / `Data` 等纯辅助成员可以从非主 actor 的测试与文件 IO 代码里直接调用
  - 保留依赖 `AppLanguage` 日期 formatter 的 `EntryRecord` 日期文案属性在 `@MainActor`，避免把 UI 格式化逻辑扩散到跨线程共享
  - 为 `testJournalCardDateIncludesWeekdayBeforeYear` 补上 `@MainActor`，与其被测属性的隔离边界保持一致
- `README.md` 无需更新：本次未改动用户可见行为、设置项、测试入口或运行方式
- 验证记录：
  - `xcodebuild build-for-testing -project thatDay.xcodeproj -scheme thatDay -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -only-testing:thatDayTests`
    - `TEST BUILD SUCCEEDED`
  - 尝试直接执行 `xcodebuild test` 时，Xcode 在本机设备探测阶段持续输出 `mobile.notification_proxy` / `The device is passcode protected` 环境日志，因此本次以 `build-for-testing` 确认编译修复

## 2026-04-20 20:08

- 修复归档 round-trip 单测的 `/tmp` 写权限问题：
  - `testRepositoryArchiveRoundTripRestoresImagesForTmpSymlinkPaths` 原先直接写入 `/tmp/thatDay-archive-...`
  - 在 Xcode 测试宿主里，这个绝对路径会被沙箱拒绝，导致用例在夹具准备阶段失败，而不是业务逻辑失败
  - 现改为在测试可写临时目录内创建一个名为 `tmp` 的符号链接目录，并继续通过该符号链接路径完成 source / destination 仓库 round-trip
  - 保留了用例原本要验证的“symlink 路径下导出导入后图片仍可恢复”语义
- `README.md` 无需更新：本次仅修正测试夹具，不涉及用户可见行为、设置项、测试入口或运行方式
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/thatDayTests/testRepositoryArchiveRoundTripRestoresImagesForTmpSymlinkPaths`
    - 定向单元测试 `1/1` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.20_20-07-32-+0800.xcresult`

## 2026-04-20 20:13

- 修复真机 UI 测试启动时被通知权限 / 系统中断打断的问题：
  - UI 测试启动统一追加 `THATDAY_UI_TEST_MODE=1`
  - app 在该模式下跳过 `registerForRemoteNotifications()`
  - app 在该模式下将应用角标更新注入为 no-op，避免启动阶段触发通知相关系统交互
  - 这样 UI 测试不再依赖人工处理系统权限弹窗，真机和模拟器启动行为保持稳定
- `README.md` 无需更新：本次未改变用户可见行为，也未改变手工运行测试的入口或步骤
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testCalendarTagStatisticOpensBlogWithMatchingFilter`
    - 定向 UI 测试 `1/1` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.20_20-12-07-+0800.xcresult`

## 2026-04-20 20:18

- 修复真机 seeded UI 测试的数据沙箱问题：
  - 原先 UI tests 先在测试进程里写临时仓库，再把绝对路径通过 `THATDAY_STORAGE_ROOT` 传给 app
  - 这在模拟器上可用，但真机上测试 runner 和 app 属于不同沙箱，app 读取该路径会触发 permission 错误，并弹出 `Notice` alert 打断测试
  - 现改为由 app 读取 `THATDAY_UI_TEST_SEED` 后，在自己的沙箱内直接写入测试仓库数据
  - `THATDAY_STORAGE_ROOT` 也改为支持相对路径，UI tests 现在传的是 app 沙箱内的唯一目录名，而不是测试进程的绝对临时路径
  - 同时补了 UI test 弹窗兜底处理器，避免后续出现阻塞性 alert 时整条链路直接中断
- `README.md` 无需更新：本次没有改用户可见功能，也没有改变手工运行测试的命令入口
- 验证记录：
  - `xcodebuild build-for-testing -project thatDay.xcodeproj -scheme thatDay -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -only-testing:thatDayUITests`
    - `TEST BUILD SUCCEEDED`
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testCalendarTagStatisticOpensBlogWithMatchingFilter`
    - 定向 UI 测试 `1/1` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.20_20-17-35-+0800.xcresult`

## 2026-04-20 20:20

- 修复单元测试里的未使用返回值问题：
  - `thatDayTests.testRepositoryArchiveRoundTripRestoresSnapshot` 调用 `storeImage(data:suggestedID:)` 时，本意只是写入测试图片文件
  - 现改为显式使用 `_ =` 忽略返回的图片引用，消除 Swift 编译器对未使用结果的报错
- `README.md` 无需更新：本次仅修正测试代码，不涉及用户可见行为、设置项、测试入口或运行方式

## 2026-04-20 20:34

- 将当前 worktree 中的 Journal 保存竞态修复同步到原仓库新分支：
  - `AppStore` 为共享仓库保存流程补上本地变更代次、进行中状态和延后刷新补偿，避免保存未完成时被较旧的前台 / 推送刷新结果覆盖
  - 新建页与详情编辑页的 `Save` 按钮在点击瞬间切到 `Saving...`，缩小重复点击导致重复提交的窗口
- 同步回归测试与文档：
  - 单元测试新增 `testRefreshingSharedRepositoryDuringSaveKeepsNewJournalEntryVisibleAndPersisted`
  - `README.md` 补充共享仓库保存期间的刷新保护说明
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/thatDayTests/testRefreshingSharedRepositoryDuringSaveKeepsNewJournalEntryVisibleAndPersisted -only-testing:thatDayTests/thatDayTests/testSavingJournalEntryAllowsEmptyTitle -only-testing:thatDayTests/thatDayTests/testManualRefreshUpdatesSharedRepositoryAndMaterializesImages`
    - 待执行

## 2026-04-20 20:32

- 补记原仓库新分支上的验证结果：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/thatDayTests/testRefreshingSharedRepositoryDuringSaveKeepsNewJournalEntryVisibleAndPersisted -only-testing:thatDayTests/thatDayTests/testSavingJournalEntryAllowsEmptyTitle -only-testing:thatDayTests/thatDayTests/testManualRefreshUpdatesSharedRepositoryAndMaterializesImages`
    - 定向测试 `3/3` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.20_20-31-50-+0800.xcresult`
  - 运行期间仍有 Xcode 连接已接真机时常见的 `mobile.notification_proxy` / `The device is passcode protected` 噪声日志，但不影响 simulator 上的测试结果

## 2026-04-20 20:42

- 清理仓库中的 `.DS_Store` 追踪：
  - 根目录、`thatDay/` 和 `thatDay/Assets.xcassets/` 下已被 git 跟踪的 `.DS_Store` 已从索引移除，保留本地 Finder 元数据文件
  - 根级 `.gitignore` 增加 `.DS_Store`，避免后续再次把这类系统文件提交进仓库
- `README.md` 无需更新：本次仅调整版本控制忽略规则，不涉及用户可见行为、设置项、测试入口或运行方式
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/thatDayTests/testRefreshingSharedRepositoryDuringSaveKeepsNewJournalEntryVisibleAndPersisted -only-testing:thatDayTests/thatDayTests/testSavingJournalEntryAllowsEmptyTitle -only-testing:thatDayTests/thatDayTests/testManualRefreshUpdatesSharedRepositoryAndMaterializesImages`
    - 定向测试 `3/3` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.20_20-41-52-+0800.xcresult`
  - 运行期间仍有 Xcode 连接已接真机时常见的 `mobile.notification_proxy` / `The device is passcode protected` 噪声日志，但不影响 simulator 上的测试结果

## 2026-04-20 21:09

- 按 feature 拆分单元测试，移除原先 1579 行的 `thatDayTests.swift`，改为：
  - `JournalTests.swift`
  - `BlogTagTests.swift`
  - `RoutingTests.swift`
  - `SharingTests.swift`
  - `ArchiveTests.swift`
  - `BiometricTests.swift`
  - `StorageTests.swift`
  - `AppStoreTestSupport.swift`
- 补齐 `AppStore` 公开 API 和失败路径覆盖：
  - 新增 `deleteEntry(_:)`、`addBlogTag(named:)`、`moveBlogTags(fromOffsets:toOffset:)`
  - 新增 `handleNotificationRoute(_:)`、`routeToEntry(_:)`、`consumeEntryOpenRequest(for:)`
  - 新增 `setDefaultRepository(_:)`、`setSharedUpdateNotificationEnabled(_:)`、`setBiometricLockEnabled(_:)` 的 setter 持久化路径
  - 新增 `acceptShare(metadata:)`、`exportCurrentRepository()`、`previousMonth()`、`nextMonth()`、`goToJournal(for:)`
  - 新增 `unlockIfNeeded()` 的认证失败和用户取消分支
- 补强边界值和 mock 能力：
  - 字数统计新增 `0`、`999`、`1000` 边界用例，保留 `1100 -> 1.1K`
  - 搜索新增大小写、重音、首尾空白和跨多个 blog tag 的匹配用例
  - `MockCloudRepositoryService` 现在追踪 `loadSnapshot`、`ensureRepositorySubscription`、URL share 接受和 metadata share 接受调用
  - `MockBiometricAuthenticator` 现在支持按次注入成功 / 失败结果
- `README.md` 无需更新：本次仅调整测试组织和测试覆盖，不涉及用户可见行为、设置项、测试入口或运行方式
- 验证记录：
  - `xcodebuild test -scheme thatDay -destination 'id=8CC688D1-06E8-4A1D-BC56-8AE8A52BA492' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `57/57` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.20_21-08-26-+0800.xcresult`

## 2026-04-20 21:21

- Search 页搜索输入框改为 iOS 原生 `UISearchBar`：
  - 保留原有统一检索 `Journal / Blog` 的逻辑
  - 输入关键词时，右侧会出现系统自带的清除按钮，可一键清空当前内容
  - 保留 `searchField` 无障碍标识，兼容现有 UI 自动化定位
- Search UI 测试补充清除按钮回归覆盖：
  - 新增 `testSearchClearButtonRemovesQueryAndHidesResults`
  - 原有 Search 相关 UI tests 改为兼容 `SearchField`
- `README.md` 已更新：补充 Search 页原生搜索栏和系统清除按钮的行为说明
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testSearchRequiresQueryBeforeShowingResults -only-testing:thatDayUITests/thatDayUITests/testCreateBlogPostAppearsInSearch -only-testing:thatDayUITests/thatDayUITests/testSearchClearButtonRemovesQueryAndHidesResults`
    - 定向 UI 测试 `3/3` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.20_21-19-39-+0800.xcresult`

## 2026-04-20 21:29

- 设置页 `Notifications` 区域新增推送范围设置：
  - 可在 `Journal / Blog / All` 三个选项里选择共享仓库更新提醒的推送范围
  - 每次切换范围都会先弹确认框，确认后才持久化到偏好设置
  - 提醒范围会直接作用于共享仓库更新的本地通知和应用角标判定，被排除的更新类型不再触发提醒
- 偏好和兼容性补充：
  - `AppPreferences` 新增 `sharedUpdateNotificationScope`
  - 读取旧版 `preferences.json` 时，如果缺少该字段，会自动回退到 `All`
- 测试与文档同步：
  - `SharingTests` 新增推送范围持久化和过滤 badge 的回归用例
  - `StorageTests` 新增旧版偏好文件迁移兼容用例
  - `README.md` 已更新：补充通知范围设置和确认交互说明
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/SharingTests -only-testing:thatDayTests/StorageTests`
    - 定向单元测试 `22/22` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.20_21-29-06-+0800.xcresult`

## 2026-04-20 21:44

- 共享仓库通知规则补成“仓库级优先，本地级兜底”：
  - `CloudKit Sharing` 区域新增 `Repository Push Updates`，由仓库主人统一设置当前仓库允许推送 `Journal / Blog / All`
  - 当主人把当前仓库设为 `Journal` 或 `Blog` 时，所有成员都强制按该规则收推送，本地 `Personal Push Updates` 对该仓库不再生效
  - 只有主人把当前仓库设为 `All` 时，成员自己的 `Personal Push Updates` 才会重新接管当前仓库的推送范围
  - 当前仓库最终生效的范围会在 `Notifications` 区域显示为 `Effective in This Repository`
- 数据层与共享同步补充：
  - `RepositorySnapshot` 新增 `sharedUpdateNotificationScope`，并随本地仓库保存、CloudKit 上传、分享接受和远端刷新一起同步
  - 旧版仓库快照缺少该字段时会自动回退到 `All`
  - 共享邀请按钮限制为仓库主人可见，避免共享成员在 `CloudKit Sharing` 区域看到自己无权完成的分享入口
- 测试与文档同步：
  - `SharingTests` 新增仓库级通知范围持久化、非主人禁止修改、主人规则覆盖本地偏好的回归用例
  - `StorageTests` 新增旧版仓库快照兼容用例
  - `README.md` 已更新：补充 `Repository Push Updates` 与 `Personal Push Updates` 的优先级说明
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/SharingTests -only-testing:thatDayTests/StorageTests`
    - 定向单元测试 `26/26` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.20_21-44-04-+0800.xcresult`

## 2026-04-20 22:01

- `Calendar` 的 `Written` 统计卡片更新数字缩写规则：
  - 超过 `999` 后统一改为三位有效数字加单位缩写，例如 `1.00K`、`10.0K`、`100K`、`1.00M`
  - 当四舍五入后的值跨过当前单位上限时，会自动进位到下一个单位，例如 `999.5K -> 1.00M`
- 统计卡片在窄屏设备上改为优先缩放数字并保持单行，避免 `Written` 数值被折成两行
- 测试与文档同步：
  - `JournalTests` 更新并补充字数缩写边界用例
  - `README.md` 已更新：补充新的三位有效数字规则和窄屏单行显示说明

## 2026-04-20 22:04

- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -derivedDataPath /tmp/thatDay-journal-2204 -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/JournalTests`
    - 定向单元测试 `18/18` 通过
    - `xcresult`: `/tmp/thatDay-journal-2204/Logs/Test/Test-thatDay-2026.04.20_22-03-22-+0800.xcresult`

## 2026-04-21 21:09

- 应用新增简体中文支持：
  - UI 文案、日期展示、系统权限提示和主要错误 / 提示信息现支持英文与简体中文，并默认跟随系统语言
  - `Journal / Calendar / Search / Blog / Settings` 的动态标题、统计文案、按钮文案与通知提示统一走本地化输出
- 本地化基础设施补齐：
  - 新增 `thatDay/Support/L10n.swift`，统一处理字符串查找、格式化、内置 Blog 标签显示和测试语言覆盖
  - `thatDay/Support/AppLanguage.swift` 不再固定 `en_US`，日期标题改为按当前语言输出；英文保持 `Thursday, 2026` 风格，简体中文改为 `2026年 星期四`
  - 新增 `thatDay/zh-Hans.lproj/Localizable.strings` 与 `thatDay/zh-Hans.lproj/InfoPlist.strings`
- Blog 标签显示规则更新：
  - 内置标签 `Reading / Watching / Game / Trip / note` 会随界面语言本地化显示
  - 自定义标签仍保持用户原始写法，不会被翻译或重写
- 测试与文档同步：
  - `README.md` 已更新：补充英文 / 简体中文双语支持、日期展示变化与测试语言说明
  - 单元测试和大多数 UI 测试默认固定英文环境，避免本机系统语言影响断言
  - UI 测试新增简体中文界面回归用例，覆盖空态文案、tab 标题与日期头部显示
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO`
    - 完整测试通过；单元测试 `66/66` 通过，UI 测试 `28` 次执行全部通过
    - `xcresult`: `/tmp/thatDay-full-20260421-2/Logs/Test/Test-thatDay-2026.04.21_21-03-39-+0800.xcresult`

## 2026-04-21 22:21

- 新增根目录 `LICENSE`，采用自定义 `thatDay Attribution for Commercial Use License 1.0`
- 许可范围按当前项目诉求定义为：允许自由使用、修改、分发和商业使用，但商业使用必须注明原项目 `thatDay` 与仓库地址
- `README.md` 已追加许可说明，并明确这是自定义协议，GitHub 可能不会按标准 SPDX/OSI 许可证自动识别
- 本次未运行测试：仅新增许可证与文档说明，未改动应用代码、配置或测试入口

## 2026-04-22 21:11

- 共享仓库自动刷新策略调整：
  - 启动时不再先显示全局 `Processing...` 再做共享同步；现在会先读取本地缓存，若开启了生物识别则先完成解锁，再静默执行启动后的共享同步
  - 前台自动刷新新增 `30` 分钟阈值，不再每次回到前台都拉取共享仓库
  - 推送触发和前台触发的自动刷新失败不再对当前共享仓库直接弹 `alert`；只有手动下拉刷新失败时才提示用户
  - 切换到已经有本地缓存的共享仓库时，先展示本地快照并静默补拉远端；只有用户主动切到本地没有缓存的共享仓库时，才继续使用阻塞式加载
- 代码结构同步调整：
  - `thatDay/App/AppStore.swift` 新增前台自动刷新节流、解锁后延迟执行的共享同步任务，以及共享仓库切换时“本地缓存优先”的加载策略
  - `thatDay/thatDayApp.swift` 去掉外层无条件的前台刷新调用，改由 `AppStore` 统一决定何时自动刷新
- 测试与文档同步：
  - `thatDayTests/SharingTests.swift` 新增前台刷新阈值、自动刷新静默失败、手动刷新报错和缓存共享仓库切换的回归用例
  - `README.md` 已更新：补充“启动先解锁后静默同步”和“前台超过 30 分钟才自动刷新”的行为说明
- 验证记录：
  - `xcodebuild test -project /Users/wangyu/code/thatDay/thatDay.xcodeproj -scheme thatDay -configuration Debug -derivedDataPath /tmp/thatDay-refresh-20260422 -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/SharingTests -only-testing:thatDayTests/BiometricTests`
    - 定向单元测试 `26/26` 通过
    - `xcresult`: `/tmp/thatDay-refresh-20260422/Logs/Test/Test-thatDay-2026.04.22_21-09-34-+0800.xcresult`

## 2026-04-24 07:20

- CloudKit 共享刷新改为限流友好的链路：
  - 手动下拉只刷新当前正在查看的共享仓库，不再一次扫描所有共享仓库
  - 共享刷新会合并进行中的自动请求，避免启动、前台、推送和手动刷新叠加成重复请求
  - 刷新先读取 `updatedAt` / `entryCount` metadata，未变化时跳过完整 payload 下载
  - 捕获 CloudKit `retry-after` 后记录冷却时间；冷却期间自动同步跳过，手动刷新显示下次可重试时间
- CloudKit 图片同步拆分为独立资产记录：
  - `RepositoryRoot.payload` 不再内嵌图片数据，只保存正文快照 JSON
  - 本地图片保存到 `RepositoryImageAsset`，使用 `reference`、`contentHash`、`payload` 字段
  - 上传前按内容哈希跳过未变化图片，并按批次处理图片记录，降低大 payload 和重复上传触发限流的风险
  - 修复 CloudKit asset 临时文件在异步保存期间的生命周期保持
- 测试与文档同步：
  - `README.md` 已更新：补充 retry-after 冷却、metadata 优先刷新、独立图片资产和本次完整验证结果
  - `zh-Hans` 本地化新增 CloudKit 临时限流提示
  - `SharingTests` 新增当前仓库手动刷新、metadata 跳过完整下载、retry-after 冷却回归用例
  - `RoutingTests` 和测试 mock 更新为 metadata 优先链路
  - UI 测试的 Blog 标签重排改为测试模式专用确定性入口，避免长按拖拽在全量测试中偶发失败；正式运行不显示该入口
- 验证记录：
  - 定向测试：`xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testSettingsBlogTagsReorderPersists`
    - UI 测试 `1/1` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.24_07-12-38-+0800.xcresult`
  - 完整测试：`xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO`
    - 完整测试通过；单元测试 `73/73` 通过，UI 测试 `28` 次执行全部通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.24_07-14-51-+0800.xcresult`

## 2026-04-24 14:33

- Journal 列表区域新增左右滑动切日：
  - 左滑进入后一天，右滑回到前一天
  - 复用统一水平滑动判定，短距离或明显纵向拖动不会触发切换
- Blog 列表区域新增左右滑动切换当前展示标签：
  - 左滑进入下一个标签，右滑回到上一个标签
  - 切换范围包含 `All` 和当前仓库所有 Blog 标签，并在首尾保持当前选择
- Search 原生搜索栏修复中文输入法组合态：
  - 拼音处于 marked text 期间不再把 `UISearchBar` 内容同步到绑定状态
  - SwiftUI 更新期间也不会把旧绑定值回写到正在组合输入的搜索栏，避免输入 `wang` 后被提前提交为英文
- 测试与文档同步：
  - `JournalTests` 新增 Journal 滑动切日前后一天、短距离 / 纵向拖动忽略、搜索栏 marked text 保护用例
  - `BlogTagTests` 新增 Blog 标签滑动切换用例
  - `README.md` 已更新：补充 Journal / Blog 滑动快捷方式和 Search 中文输入法保护说明
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `77/77` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.24_14-30-28-+0800.xcresult`

## 2026-04-24 14:43

- 取消 Journal 列表区域左右滑动切日功能：
  - 删除 `JournalView` 上的日期切换拖拽手势
  - 保留顶部 `Previous / Next` 按钮切换日期，避免和列表上下滚动体验冲突
- 删除 Journal 滑动切日相关测试：
  - 移除 `testJournalHorizontalSwipeMovesToNextAndPreviousDay`
  - 移除 Journal 测试文件里为该手势补充的短距离 / 纵向拖动判定用例
- `README.md` 已同步撤掉 Journal 滑动切日说明，保留 Blog 标签滑动和 Search 中文输入法修复说明
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `75/75` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.24_14-35-42-+0800.xcresult`

## 2026-04-24 14:52

- 取消 Blog 列表区域左右滑动切换展示标签功能：
  - 删除 `BlogView` 上的标签切换拖拽手势
  - 删除 `AppStore.moveSelectedBlogTag(by:)`
  - 删除不再使用的 `HorizontalSwipeDirection` 工具
- 删除 Blog 滑动切换标签相关测试：
  - 移除 `testBlogTagHorizontalSwipeMovesAcrossFilterOptions`
- `README.md` 已同步撤掉 Blog 列表滑动切换标签说明，并收紧交互原则表述；Blog 标签切换继续通过顶部标签条完成
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests`
    - 单元测试 `74/74` 通过
    - `xcresult`: `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.24_14-48-07-+0800.xcresult`

## 2026-04-28 10:16

- Journal 页面切日改为 `UIPageViewController` 系统分页：
  - 内容区左滑进入后一天，右滑回到前一天，保留顶部 `Previous / Next` 按钮
  - 每个日期页使用独立 SwiftUI hosted `List`，由 `UIPageViewController` 处理水平翻页手势、垂直滚动冲突和系统滚动转场
  - 顶部按钮、日期选择和手势切换共用同一套按天翻页状态，快速切换时缓存待应用日期，避免动画中途状态错乱
- `AppStore` 补充 Journal 分页需要的日期接口：
  - 支持按显式日期读取 Journal entries，避免预加载前后页时改动当前选中日期
  - 统一按日历日边界计算前一天 / 后一天
- 测试与文档同步：
  - `JournalTests` 新增显式页面日期读取和跨日日期计算用例
  - `thatDayUITests` 新增 Journal `UIPageViewController` 左右滑动切日用例，以及 seeded 多条 Journal 的翻页性能用例
  - `thatDayApp` 新增 `journal-performance` UI 测试 seed
  - `README.md` 已更新：补充 Journal 内容区系统级左右翻页和性能测试覆盖
- 验证记录：
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -derivedDataPath /tmp/thatDay-pageview-1 -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/JournalTests/testJournalEntriesForExplicitPageDateDoNotMutateSelectedDate -only-testing:thatDayTests/JournalTests/testJournalDateByAddingUsesCalendarDayBoundaries`
    - 定向单元测试 `2/2` 通过
    - `xcresult`: `/tmp/thatDay-pageview-1/Logs/Test/Test-thatDay-2026.04.28_10-08-32-+0800.xcresult`
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -derivedDataPath /tmp/thatDay-pageview-2 -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayUITests/thatDayUITests/testJournalSwipeSwitchesDatesWithPageViewController -only-testing:thatDayUITests/thatDayUITests/testJournalSwipeAnimationPerformance`
    - 定向 UI 测试 `2/2` 通过
    - 性能用例 `5` 次往返滑动平均 Clock `1.523s`、CPU `0.334s`、Memory Peak Physical 约 `61.3MB`
    - `xcresult`: `/tmp/thatDay-pageview-2/Logs/Test/Test-thatDay-2026.04.28_10-12-13-+0800.xcresult`
  - `xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -derivedDataPath /tmp/thatDay-pageview-3 -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO -only-testing:thatDayTests/JournalTests`
    - `JournalTests` `21/21` 通过
    - `xcresult`: `/tmp/thatDay-pageview-3/Logs/Test/Test-thatDay-2026.04.28_10-13-59-+0800.xcresult`
