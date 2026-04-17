# thatDay

`thatDay` 是一个面向 iPhone 的日记应用。

它要解决的不是“多写几篇文章”这么简单，而是把同一天历年的 Journal 放在一起回看，同时把不适合放进 Journal 的内容单独沉淀成 Blog，再把搜索、共享、导入导出和设备侧安全都放进同一条稳定主线里。

当前版本聚焦这些事：

- 打开应用先看到今天，以及这一天历年的 Journal
- 在 Calendar 里看月历、切月份和写作统计
- 用 Blog 单独保存不进入 Journal / Calendar 的长文，并按标签筛选
- 用统一搜索同时找 Journal 和 Blog
- 把本地仓库、共享仓库、默认仓库切换说清楚
- 支持导入 ZIP、导出 ZIP、清空当前仓库
- 在不把界面做复杂的前提下，补齐生物识别解锁（Face ID / Touch ID）、共享通知、图片插入和 Blog 标签管理

## 1. 设计方式

### 1.1 需求先于实现

这个项目先回答“用户到底要怎么回看和管理内容”，再决定页面、数据结构、CloudKit 和测试怎么写。

如果某个实现细节不能直接帮助“写日记、看旧文、查内容、共享仓库、保住数据边界”，它就不应该优先进入当前版本。

### 1.2 用户动作优先于手势技巧

最近一轮交互调整的核心原则很明确：

- 阅读和编辑分开
- 关键动作用按钮表达
- 列表卡片只负责进入详情

所以当前版本去掉了卡片左滑编辑/删除，也不再依赖模糊的切日手势，而是把主要操作改成可以预期的显式入口。

### 1.3 仓库边界优先

这个项目现在已经不是“一个本地 JSON 文件”的规模了。

一台设备上可以同时存在：

- 本地仓库
- 自己发起共享后的云端仓库
- 别人共享给自己的仓库

所以架构上必须始终回答清楚三件事：

1. 当前正在操作哪一座仓库
2. 这座仓库当前有没有写权限
3. 切换、导入、清空、通知跳转时会影响哪一座仓库

### 1.4 变更可追踪

本仓库要求所有会修改仓库文件的交付都追加写入 `log.md`，不能覆盖历史。

如果改动影响用户可见行为、设置项、测试入口或运行方式，还必须同步更新 `README.md`。这不是形式要求，而是为了避免后来继续迭代时，代码变了但说明文档和历史记录都对不上。

### 1.5 简单优先

当前版本不追求“大而全”的笔记系统。

它只保留最必要的动作：

1. 看今天
2. 看往年今天
3. 写 Journal / Blog
4. 搜索
5. 切换仓库
6. 共享、导入、导出、清空

## 2. 需求完成情况

### 2.1 当前版本在回答哪些需求

| 需求 | 当前版本的回答 |
| --- | --- |
| 想看同一天历年的记录 | `Journal` 按“同月同日”聚合文章，直接展示卡片列表；卡片日期显示星期和年份 |
| 不是所有内容都适合进入 Journal | 提供独立 `Blog` 列表，Blog 不进入 `Journal / Calendar`，但会进入搜索 |
| 想给 Blog 分类型并按类型查看 | Blog 支持标签显示和顶部标签筛选，标签可在 `Settings` 里增删、长按拖动排序；拖动时列表会实时让位，放手后完成排序 |
| 想在 Calendar 一眼看到这个月写了多少 | `Calendar` 上方显示月历，下方显示 `Journaled Days / Blogs / Written` 三张统计卡片，并补充 Blog 标签统计入口 |
| 想统一查 Journal 和 Blog | `Search` 对两类内容统一检索，空查询不返回结果 |
| 一台设备上可能有多座仓库 | 支持本地仓库、共享仓库、默认仓库切换和最近打开排序 |
| 想备份、迁移或恢复数据 | 支持当前仓库导出 ZIP、导入 ZIP、清空当前仓库 |
| 共享仓库变化后想及时知道 | 支持 CloudKit 共享、Journal / Blog 下拉刷新、应用启动和回到前台自动拉取、远端刷新、本地通知、应用角标和通知点击跳转 |
| 共享仓库里的图片也要跟着走 | 共享快照会同时携带正文和本地图片，拉取后自动恢复到当前设备缓存 |
| 插图不能无限膨胀 | 选图后会自动压缩并保证单张图片保存到 `100KB` 以下 |

### 2.2 现在主线是否已经打通

当前版本主线已经打通，而且是闭环的：

- Journal / Blog 都支持新建、阅读、编辑、删除
- Search 可以搜到 Journal / Blog
- Calendar 可以定位日期、切月份、回到今天，并看到本月统计
- Blog 可以按标签显示和筛选
- Settings 可以发起共享、接受共享、切换仓库、设置默认仓库和管理 Blog 标签
- ZIP 导入导出和清空当前仓库都已经进入设置页
- 生物识别锁定和共享仓库更新提醒已经有真实入口
- 图片从相册插入后会先压缩，再进入保存链路
- 当前 UI 文案、日期展示和系统权限提示统一使用英文

### 2.3 目前必须说清楚的边界

下面这些行为不是 bug，而是当前版本刻意保持清楚的边界：

- 共享成员如果是只读权限，不能新建、编辑、删除、导入或清空；`Journal / Blog` 页面也不会显示右下角新增按钮
- 导入 ZIP 会覆盖当前仓库内容，不是增量合并
- 插入图片统一转成 JPEG 并压到 `100KB` 以下；如果原图有透明区域，最终会以白底保存
- CloudKit 共享、订阅和分享链接接受，依赖设备登录 iCloud 且容器配置正确
- 首次把共享能力带到 TestFlight / App Store 对应的 CloudKit production 环境时，必须先把 development schema 部署到 production；当前项目至少需要 `RepositoryRoot` 记录类型，否则生成邀请时会报 `Cannot create new type RepositoryRoot in production schema`
- 仓库根目录里虽然保留了 `lumina/` 前端原型目录，但当前 iOS App 的正式实现不依赖它

## 3. 用户接口

### 3.1 首次进入与全局结构

- 应用主体是一个四个 tab 的 `TabView`：`Journal / Calendar / Search / Blog`
- 新安装应用不会再预置 `Welcome to thatDay` 引导页；本地仓库默认以空内容进入 `Journal`，当天没有内容时直接显示空状态
- 全局层统一承载忙碌态、生物识别锁层、编辑器 sheet、设置页 sheet 和错误 alert
- 当前 UI 文案、日期标题、月份/星期名称和系统权限提示默认统一使用英文
- 如果启用了生物识别解锁，应用打开或从后台回到前台时会先要求验证
- 应用启动和每次回到前台时，都会自动拉取已接入共享仓库的最新快照
- 如果共享仓库在应用未打开期间收到远端更新，应用角标会置为 `1`；只要应用进入前台，角标就会立刻清零

### 3.2 Journal

- 默认展示今天
- 顶部中间日期按钮可一键回到今天
- 左右两侧提供 `Previous / Next` 小按钮切换日期
- 左上角进入 `Calendar`
- 右上角进入 `Settings`
- 可编辑仓库右下角有 `+` 新建 Journal；只读仓库不显示该按钮
- 文章按“同月同日”聚合，直接展示文章卡片，不再额外显示年份分组标题
- Journal 卡片日期显示 `星期, 年份`，例如 `Thursday, 2026`，不再重复显示月日
- 列表支持下拉刷新；如果当前正在看共享仓库，会立即重新拉取最新内容

### 3.3 Calendar

- 使用自定义月视图网格
- 日历位于上方，统计卡片位于下方
- 左侧月份年份按钮会以单行显示当前 `Month Year`，字号只略大于日期数字，避免在窄屏上换行；它的左边缘会和下方星期列首项对齐，点开后可用滚轮切换月份
- 右侧提供上一个月 / 下一个月按钮
- 顶部工具栏提供 `Today` 回到今天和 `Settings`
- 有 Journal 的日期会显示打点
- `Journaled Days` 卡片统计 Journal 篇数，`Blogs` 卡片统计 Blog 篇数，`Written` 卡片统计全部 Journal + Blog 的总字数
- `Written` 在超过 `1000` 字后会显示为 `1.1K` 这一类缩写格式
- 三张统计卡片会压缩上下留白，避免统计文字被过大的垂直内边距稀释
- 三张统计卡片下方会显示当前仓库所有 Blog 标签及文章数，标签保持原始写法；标签宽度按内容自适应并自动换行，点按后会直接跳到 `Blog` 对应标签筛选结果
- 选中某一天后返回对应 Journal 上下文
- 日历卡片内边距比上一版更紧，月历数字会更贴近卡片边框

### 3.4 Search

- 搜索框为空时不展示任何结果
- 输入后统一搜索 Journal 和 Blog
- 搜索结果直接进入文章详情页

### 3.5 Blog

- 可编辑仓库使用和 Journal 一样的右下角 `+`；只读仓库不显示该按钮
- 列表顶部提供可横向滑动的圆角矩形标签条，支持 `All` 和当前仓库所有 Blog 标签；标签较多时可以左右滑动，英文标签不会被截断
- 文章按时间倒序排列
- 带图 Blog 卡片默认保留横版封面布局，也支持按文章切换为左侧竖图、右侧标题 / 四行摘要 / 日期标签的竖版布局
- 每篇 Blog 会在日期后显示当前标签
- Blog 文章不会进入 Journal / Calendar，但会被 Search 检索
- 列表支持下拉刷新；如果当前正在看共享仓库，会立即重新拉取最新内容

### 3.6 文章阅读与编辑

- 列表卡片只负责进入详情页
- 详情页默认是阅读模式，不再混合编辑控件
- 右上角 `编辑` 进入编辑模式
- 编辑模式顶部固定为 `取消 / 保存`
- 删除入口只在编辑模式里显示
- Journal 标题改为可选；没有标题时，列表卡片和详情页都不会强行补一个占位标题
- Blog 编辑页会提供标签选择器，新建 Blog 默认落到 `note`
- Blog 编辑页会提供 `Landscape / Portrait` segmented control，用来切换带图卡片的横版 / 竖版封面布局
- 竖版 Blog 在详情页会保持题图全宽显示，并限制最大高度；超过上限时会从顶部和底部等量裁剪
- Blog 详情页和列表卡片都会在日期后显示标签
- 插图入口只有相册选图，不再支持图片链接输入
- 选图后会立刻压缩，预览和最终落盘都使用压缩后的图片
- 编辑页的图片预览下方会显示 `Delete Image`，可直接移除当前插图

### 3.7 Settings

设置页当前承担的是完整的仓库管理界面，而不只是一些零散开关：

1. 在 `Repository Status` 里切换当前仓库，并查看当前权限
2. 选择共享邀请权限并生成 CloudKit 邀请
3. 接受别人发来的 iCloud 共享链接
4. 开关“共享仓库更新提醒”（本地通知 + 应用角标）
5. 开关生物识别解锁（Face ID / Touch ID）
6. 管理 Blog 标签：新增、长按拖动排序、删除；拖动时列表会实时让位，放手后完成排序；删除已使用标签时会在居中确认框里选择旧文章迁移到哪个标签
7. 导出当前仓库 ZIP
8. 导入 ZIP 到当前仓库
9. 指定启动时默认打开哪座仓库
10. 清空当前仓库内容

## 4. 架构层

### 4.1 工程概况

- 平台：iPhone / iOS
- 界面框架：SwiftUI
- 状态模型：`@Observable AppStore`
- 云能力：CloudKit
- 本地通知：`UserNotifications`
- 生物识别：`LocalAuthentication`
- Scheme：`thatDay`
- Bundle ID：`yu.thatDay`
- iCloud 容器：`iCloud.yu.thatDay`
- 应用显示名：`日记本`
- 商店素材资源：`thatDay/Assets.xcassets/AppStore.imageset`、`thatDay/Assets.xcassets/PlayStore.imageset`

### 4.2 状态中心

`thatDay/App/AppStore.swift` 是当前应用的状态中心。

它负责统一处理：

- 当前选中的 tab、日期、月份、搜索词
- 当前打开的是哪座仓库
- 当前仓库的文章数组、Blog 标签、统计数据和权限
- 编辑器 session、设置页、共享页、导出结果、导入导出进度
- 生物识别锁定状态
- 通知跳转和共享接入后的路由刷新

这意味着 UI 层大多只消费状态和触发意图，仓库切换、持久化、共享刷新等复杂逻辑都集中留在 `AppStore`。

### 4.3 数据模型

当前主要模型分成四层：

- 文章层：`EntryRecord`、`EntryDraft`
- 仓库快照层：`RepositorySnapshot`
- 仓库身份层：`RepositoryDescriptor`、`RepositoryReference`
- 偏好层：`AppPreferences`

其中最重要的边界是：

- `EntryRecord` 只表达内容本身；Blog 文章可带 `blogTag` 和图片卡片布局
- `RepositorySnapshot` 表达一座仓库当前的全部文章，以及这座仓库自己的 Blog 标签顺序
- `RepositoryDescriptor` 表达这座仓库在 CloudKit 里的身份和权限
- `RepositoryReference` 表达“这台设备知道哪些仓库、显示名是什么、最近何时打开”

### 4.4 本地存储布局

当前本地数据已经从单仓库目录演进为“仓库库 + 偏好 + 多仓库目录”结构：

```text
Application Support/thatDay/
  preferences.json
  repositories.json
  repositories/
    local/
      descriptor.json
      repository.json
      images/
        <uuid>.jpg
    shared-.../
      descriptor.json
      repository.json
      images/
        <uuid>.jpg
```

这套结构由 `RepositoryLibraryStore` 管理，它还负责把旧版“根目录单仓库”数据自动迁移到 `repositories/local/`。

`repository.json` 现在除了文章数组，也会保存仓库级 Blog 标签配置，以及每篇 Blog 的图片卡片布局，因此标签顺序、增删结果、文章标签和横版 / 竖版显示方式都会跟随本地持久化、共享快照和 ZIP 导入导出一起移动。

### 4.5 多仓库与共享权限

当前权限模型分为四种：

- `local`
- `owner`
- `editor`
- `viewer`

它们不只是展示文案，而是直接决定：

- 是否允许编辑
- 使用 private 还是 shared CloudKit database
- 是否能发起共享
- 是否能导入 / 清空 / 删除内容

`RepositoryReference` 进一步补上了设备侧关心的信息，例如显示名、最近打开时间、最近一次已知快照更新时间。

### 4.6 云端同步、通知与路由

这部分现在是完整链路，不再只是“能生成分享链接”：

- `CloudRepositoryService` 负责把整仓库快照保存到 CloudKit 的 `CKRecordZone`
- 云端快照当前固定落在该 zone 里的 `RepositoryRoot` 记录，字段包括 `updatedAt`、`entryCount` 和 `payload`
- `thatDayApp.swift` 负责接住 scene/app 生命周期、远端推送和共享接受事件
- `AppEventBridge.swift` 里的 `RepositoryRemoteChangeCenter` / `NotificationRouteCenter` 负责把系统事件桥接回 `AppStore`
- `AppStore` 负责在前台刷新共享仓库、比对快照差异、生成本地通知和应用角标，以及在点击通知后切换到对应仓库和文章
- 共享所有者仍使用 `CKRecordZoneSubscription`；共享成员改用 `CKDatabaseSubscription` 监听 shared database，避免 shared database 不支持 zone subscription 的 CloudKit 报错
- Journal / Blog 的手动下拉刷新和应用回到前台时的自动刷新，都复用同一条共享仓库拉取链路
- 角标不再跟“是否读过某篇文章”绑定，只要共享更新发生在应用未打开期间就标 `1`，应用进入前台后立即清零

### 4.7 图片插入与压缩链路

图片链路现在已经明确固定下来：

`PhotosPicker` -> `EntryImageCompressor` -> `LocalRepositoryStore.storeImage(...)` -> `images/<uuid>.jpg`

关键规则如下：

- 图片从相册选中后先做压缩
- 压缩结果直接用于编辑页预览
- 保存时仍经过同一压缩器兜底，避免后续别的调用方绕过规则
- 最终落盘格式统一为 JPEG
- 单张图片目标上限固定为 `100KB`
- 当前设备展示仓库内图片时，直接从本地 `file://` 路径读取，不再把仓库图片交给 `AsyncImage` 异步拉取，避免导入覆盖同名文件后当前设备误保留失败态
- 导入、换图和共享刷新后，会显式刷新当前设备上的本地图片视图，避免“文件已经换了，但同一路径视图还停在旧状态”
- 文章移除插图后，会同步清理仓库内已经失去引用的本地图片文件，避免导出和后续同步继续带上废弃图片
- 同步到 CloudKit 时，会把当前快照引用到的本地图片一起写进共享快照；其他设备拉取后会自动恢复到本地 `images/` 目录

### 4.8 导入导出与迁移

- `RepositoryArchiveService` 负责把当前仓库打包成 ZIP，并从 ZIP 恢复仓库
- 导出包包含 `repository.json`、`descriptor.json` 和 `images/` 文件夹
- 导入时会保留当前仓库描述信息里的权限语义，并覆盖当前仓库内容
- 导入导出的仓库文件路径现在按标准化后的相对路径计算，不再依赖绝对路径字符串替换；即使系统把同一路径写成不同前缀，仓库图片也会回到正确的 `images/` 目录
- 从系统“文件”里选择外部 ZIP 导入时，会先申请并持有该文件的安全作用域读权限，再执行解压，避免选中文件后误报“没有足够权限”
- `RepositoryLibraryStore` 在加载 catalog 前会先尝试执行旧版单仓库迁移

### 4.9 关键文件

- `thatDay/App/AppStore.swift`
- `thatDay/thatDayApp.swift`
- `thatDay/ContentView.swift`
- `thatDay/Features/Journal/JournalView.swift`
- `thatDay/Features/Calendar/CalendarView.swift`
- `thatDay/Features/Search/SearchView.swift`
- `thatDay/Features/Blog/BlogView.swift`
- `thatDay/Features/Shared/EntryDetailView.swift`
- `thatDay/Features/Shared/EntryCardView.swift`
- `thatDay/Features/Settings/SettingsView.swift`
- `thatDay/Services/RepositoryLibraryStore.swift`
- `thatDay/Services/LocalRepositoryStore.swift`
- `thatDay/Services/CloudRepositoryService.swift`
- `thatDay/Services/RepositoryArchiveService.swift`
- `thatDay/Services/AppEventBridge.swift`
- `thatDay/Support/EntryImageCompressor.swift`

## 5. 运行与测试

### 5.1 运行

可以直接在 Xcode 打开 `thatDay.xcodeproj`，运行 `thatDay` scheme。

如果用命令行构建：

```bash
xcodebuild build -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324'
```

### 5.2 测试命令

当前机器上可用并已经验证通过的完整测试命令是：

```bash
xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO
```

这里显式使用 `iPhone 17 Pro` 模拟器，并关闭并行测试，避免额外 simulator clone。

### 5.3 当前测试覆盖

单元测试覆盖：

- Journal 同月同日跨年分组
- Search 空态与 Journal / Blog 混合命中
- Journal 日期切换与回到今天
- Calendar 网格生成
- Blog 持久化、默认标签、标签删除后的重分配
- Journal / Blog 总字数统计
- 共享仓库接受、默认仓库启动、手动刷新与图片恢复
- 共享仓库保存时图片会跟着上传到云端快照
- ZIP 导入导出回环
- 清空仓库
- 图片落盘压缩到 `100KB` 以下

UI 测试覆盖：

- Calendar 月份切换与 `Today`
- Blog 新建后进入 Search
- Blog 标签筛选
- Blog 阅读页编辑与删除
- Journal 头部日期回到今天
- Journal `Previous / Next`
- 无图文章详情布局
- Search 空态
- Settings 打开
- Launch tests 的不同外观与方向组合

### 5.4 最近一次完整验证

- 时间：2026-04-17 17:56 - 17:59（Asia/Shanghai）
- 命令：`xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO`
- 结果：通过
- 单元测试：27 项通过
- UI 测试：14 项通过
- xcresult：`/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_17-56-15-+0800.xcresult`

### 5.5 本次测试里看到但不属于业务失败的问题

- `iPhone 16` 这个 simulator destination 在当前机器上不存在，所以文档里的命令统一改成现有的 `iPhone 17 Pro`
- UI 测试期间会看到 `IDELaunchParametersSnapshot` 和 `UIAccessibilityLoaderWebShared` 的系统级日志警告，但本次完整测试仍然全部通过

## 6. 协作与文档要求

这个仓库的协作规则现在明确写成下面四条，后续继续改功能也要照这个执行：

1. 任何会修改仓库文件的交付，在结束前都必须追加写入 `log.md`
2. `log.md` 只能追加，不能删旧记录、不能覆盖历史
3. 如果改动影响用户可见行为、设置项、测试入口或运行方式，必须同步更新 `README.md`
4. 每次做完一个功能修改，都要顺手检查一次 `log.md` 和 `README.md` 是否已经跟上

## 7. 当前已知问题与后续注意

- 现在的图片压缩策略为了稳定卡住 `100KB` 上限，统一输出 JPEG；如果未来必须保留透明背景，需要单独设计 PNG / HEIC 规则
- CloudKit 共享相关功能在真机和真实 iCloud 环境下才算完整能力，模拟器和本地测试主要验证的是代码路径和 UI
- Settings 里的“导入 ZIP 到当前仓库”当前仍是覆盖导入，不做差异合并；如果以后要支持 merge，需要先重新定义冲突规则
