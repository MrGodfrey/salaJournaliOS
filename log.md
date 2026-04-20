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
