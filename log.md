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
