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
- 默认跟随系统时区，也可在设置中固定使用北京时间
- 在不把界面做复杂的前提下，补齐生物识别解锁（Face ID / Touch ID）、共享通知、图片插入和 Blog 标签管理

## 1. 设计方式

### 1.1 需求先于实现

这个项目先回答“用户到底要怎么回看和管理内容”，再决定页面、数据结构、CloudKit 和测试怎么写。

如果某个实现细节不能直接帮助“写日记、看旧文、查内容、共享仓库、保住数据边界”，它就不应该优先进入当前版本。

### 1.2 用户动作优先于手势技巧

最近一轮交互调整的核心原则很明确：

- 阅读和编辑分开
- 关键动作用按钮表达
- 高频浏览动作保留明确控件；当系统组件能降低手势冲突时，可补充为快捷入口
- 列表卡片只负责进入详情

所以当前版本去掉了卡片左滑编辑/删除，保留可以预期的显式入口；Journal 切日期保留按钮，同时内容区支持 `UIPageViewController` 左右翻页；Blog 切标签保留顶部标签条，同时内容区支持 `UIPageViewController` 左右翻页。

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
| 想统一查 Journal 和 Blog | `Search` 使用 iOS 原生搜索栏对两类内容统一检索，空查询不返回结果；输入时可一键清空关键词 |
| 一台设备上可能有多座仓库 | 支持本地仓库、共享仓库、默认仓库切换和最近打开排序 |
| 想备份、迁移或恢复数据 | 支持当前仓库导出 ZIP、导入 ZIP、清空当前仓库 |
| 跨时区使用时需要稳定的日期归属 | 文章时间戳始终以 ISO 8601 / UTC 绝对时间保存；日期显示、Journal 归属和 Calendar 打点默认跟随系统时区，也可固定为北京时间，选择会持久保存 |
| 共享仓库变化后想及时知道 | CloudKit 静默推送会直接在系统给出的后台时段内定位发生变化的 zone、拉取新快照，并在真正完成后向 iOS 汇报结果；另有持久化 change token / 待处理 zone 收件箱、应用启动 / 回到前台追赶和低频 `BGAppRefreshTask` 增量兜底。可见提醒权限与同步本身已经解耦：关闭提醒不会关闭后台同步。订阅注册使用 production 已验证的 stable 配置并执行 save-only 自愈：升级、订阅缺失或配置异常时会补建并读回验证，绝不会在替代订阅确认前删除工作订阅；private / shared database 每轮最多各校验一次，成功后七天内不重复请求。只读成员始终只执行下行同步，不创建、恢复或调度上传；owner / editor 的编辑先本地落盘，待上传状态会跨进程保留并自动补传。账户身份未确认时会先隔离所有云端读写但立即展示本地缓存，确认仍是同一 iCloud 用户后才恢复；上传使用服务端 change tag 防止覆盖别人刚写好的内容，遇到并发更新会按持久化基线做无损三方合并；CloudKit 返回 retry-after 时会持久化冷却时间，避免连续请求 |
| 共享仓库里的图片也要跟着走 | 共享快照会同步正文和本地图片，图片在 CloudKit 中独立保存；根快照记录每张图的 SHA-256，文字修改不会重新读写未变化图片，新增 / 替换 / 删除图片则与根记录原子提交。拉取只复用哈希一致的本地缓存，并兼容旧版同名图片被原地替换的情况 |
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
- 当前 UI 文案、日期展示和系统权限提示支持英文与简体中文，默认跟随系统语言

### 2.3 目前必须说清楚的边界

下面这些行为不是 bug，而是当前版本刻意保持清楚的边界：

- 共享成员如果是只读权限，不能新建、编辑、删除、导入或清空；`Journal / Blog` 页面也不会显示右下角新增按钮
- 只读共享仓库不会进入上传、冲突合并或自动补传状态。升级前如果曾遗留错误的 pending / conflict 标记，应用会清除活动上传状态并继续拉取 owner 的最新内容；如果磁盘上确有待上传快照，则先把完整快照和图片移入本机的非活动恢复副本，不会静默上传或直接删除
- 导入 ZIP 会覆盖当前仓库内容，不是增量合并
- 插入图片统一转成 JPEG 并压到 `100KB` 以下；如果原图有透明区域，最终会以白底保存
- CloudKit 共享、订阅和分享链接接受，依赖设备登录 iCloud 且容器配置正确
- 首次把共享能力带到 TestFlight / App Store 对应的 CloudKit production 环境时，必须先把 development schema 部署到 production；当前项目至少需要 `RepositoryRoot` 和 `RepositoryImageAsset` 记录类型，否则生成邀请或同步图片时可能报 `Cannot create new type ... in production schema`
- iOS 的静默后台推送和 `BGAppRefreshTask` 都是系统按电量、使用习惯、网络和后台刷新设置调度的 best-effort 机制，不是实时任务调度器；用户主动从多任务界面强制退出应用后，系统不会再通过静默推送唤醒它，直到用户重新打开。应用能保证的是持久化记录进度并在下一次获准运行时追到最新内容，不能保证每一次 CloudKit 变化都对应一条独立、即时到达的通知
- 如果本地待上传内容与另一台设备的新版本发生并发冲突，普通共享编辑会用待上传文件中保存的共同基线做方向明确的三方合并：远端版本保留原条目 UUID，同一条目被双方分别修改时把本地版本保留为确定性的冲突副本，互不相关的新增和编辑直接合并，删除只在另一端仍未修改时生效；旧版 outbox 缺少共同基线时采用保守无损 union。合并后仍以最新服务端 change tag 原子保存，不会静默覆盖另一端内容。首次分享和 encrypted-data-reset 继续走各自的严格恢复路径，不参与普通合并
- 如果共享被撤销或 CloudKit zone 被普通删除，设备会保留最后一次成功同步的只读缓存，并把仓库状态显示为 `Unavailable · Cached Read-Only`，不再反复请求已经不存在的 zone；如果 CloudKit 报告 `purged`，应用会按 Apple 语义删除该 zone 的本地缓存
- 仓库根目录里虽然保留了 `lumina/` 前端原型目录，但当前 iOS App 的正式实现不依赖它

## 3. 用户接口

### 3.1 首次进入与全局结构

- 应用主体是一个四个 tab 的 `TabView`：`Journal / Calendar / Search / Blog`
- 新安装应用不会再预置 `Welcome to thatDay` 引导页；本地仓库默认以空内容进入 `Journal`，当天没有内容时直接显示空状态
- 全局层统一承载忙碌态、生物识别锁层、编辑器 sheet、设置页 sheet 和错误 alert
- 当前 UI 文案、日期标题、月份/星期名称和系统权限提示支持英文与简体中文，默认跟随系统语言
- 日期显示、文章按天归类和编辑器日期选择默认跟随系统时区；可在设置页底部切换为北京时间，应用会一直保留上次选择
- 如果启用了生物识别解锁，应用打开或从后台回到前台时会先要求验证；Face ID / Touch ID 失败或被锁定时可回退到系统锁屏密码；启动时会先显示验证，再在解锁成功后静默同步共享仓库
- 应用启动时会先从本地 catalog / cache 立即恢复界面，再确认当前 CloudKit 用户身份；身份仍相同时才恢复待上传和远端追赶，暂时不可用时保留缓存与 outbox 并按退避时间重试，确认换成其他 iCloud 用户时继续隔离写入并提示用户，避免把旧账号的待上传日记传到新账号
- 从没有保存账户身份的旧版本升级到 `1.2.11` 时，只要本机已有云仓库或待上传内容，就会出现一次 `Confirm iCloud Account`：只有用户明确确认当前仍是原账号、且稳定用户标识成功写入 `preferences.json` 后，CloudKit 读写才会解锁；选择 `Keep Sync Paused` 不会删除缓存或 outbox
- 账户确认后会立即检查已接入共享仓库的最新快照；刷新先比较 CloudKit 服务端 `recordChangeTag`，旧数据没有该字段时才回退到 `updatedAt` / `entryCount`，因此不会再因两台设备时钟偏差漏掉内容变化
- 回到前台会在距离上次成功同步超过 `30` 秒时追赶一次；短时间反复切换前后台会被去抖，避免制造无意义 CloudKit 请求
- iOS 在后台交付 CloudKit 静默推送时，应用会直接完成同步并按真实结果返回 `newData / noData / failed`；如果检测到可见内容变化且用户开启了提醒，会显示本地通知并把角标置为 `1`。应用进入前台后角标立刻清零
- `1.2.10` 会强制重新验证并修复 `1.2.9` 的 CloudKit 订阅迁移状态：共享成员恢复 production 已验证的全 shared database 订阅，仓库所有者恢复逐 zone 订阅；修复只保存和读回验证，不删除任何现存订阅。APNs 注册会在应用再次激活时重试，订阅、推送处理、上传和本地提醒失败会写入统一的 `CloudSync` 系统日志
- 新增、编辑和删除文章都会进入共享更新提醒判断；删除通知会打开对应仓库，而不会尝试跳到已经不存在的文章

### 3.2 Journal

- 默认展示今天
- 顶部中间日期按钮可一键回到今天
- 左右两侧提供 `Previous / Next` 小按钮切换日期
- 内容区支持左右滑动按天翻页，使用 UIKit 的 `UIPageViewController` 系统滚动转场；垂直列表滚动仍保留给当天内容
- 左上角进入 `Calendar`
- 右上角进入 `Settings`
- 可编辑仓库右下角有 `+` 新建 Journal；只读仓库不显示该按钮
- 文章按“同月同日”聚合，直接展示文章卡片，不再额外显示年份分组标题
- Journal 卡片日期会随语言本地化显示：英文为 `Thursday, 2026`，简体中文为 `2026年 星期四`，不再重复显示月日
- 列表支持下拉刷新；如果当前正在看共享仓库，会检查当前仓库是否有最新内容；如果 CloudKit 要求稍后重试，会显示下次可重试时间

### 3.3 Calendar

- 使用自定义月视图网格
- 日历位于上方，统计卡片位于下方
- 左侧月份年份按钮会以单行显示当前本地化后的月份和年份，英文环境示例为 `April 2026`；字号只略大于日期数字，避免在窄屏上换行；它的左边缘会和下方星期列首项对齐，点开后可用滚轮切换月份
- 右侧提供上一个月 / 下一个月按钮
- 顶部工具栏提供 `Today` 回到今天和 `Settings`
- 有 Journal 的日期会显示打点
- `Journaled Days` 卡片统计 Journal 篇数，`Blogs` 卡片统计 Blog 篇数，`Written` 卡片统计全部 Journal + Blog 的总字数
- `Written` 在超过 `999` 字后会显示为固定三位有效数字加单位缩写，例如 `1.00K`、`10.0K`、`100K`、`1.00M`；窄屏设备上数字会自动缩放并保持单行
- 三张统计卡片会压缩上下留白，避免统计文字被过大的垂直内边距稀释
- 三张统计卡片下方会显示当前仓库所有 Blog 标签及文章数；内置标签会随界面语言本地化显示，自定义标签保持原始写法；标签宽度按内容自适应并自动换行，点按后会直接跳到 `Blog` 对应标签筛选结果
- 选中某一天后返回对应 Journal 上下文
- 日历卡片内边距比上一版更紧，月历数字会更贴近卡片边框

### 3.4 Search

- 搜索框使用 iOS 原生搜索栏；输入内容后右侧会出现系统清除按钮，可一键清空当前关键词
- 搜索框会保留中文输入法的拼音组合态，不会在输入 `wang` 这类拼音后被绑定回写提前提交
- 搜索框为空时不展示任何结果
- 输入后统一搜索 Journal 和 Blog
- 搜索结果直接进入文章详情页

### 3.5 Blog

- 可编辑仓库使用和 Journal 一样的右下角 `+`；只读仓库不显示该按钮
- 列表顶部提供可横向滑动的圆角矩形标签条，支持当前语言下的“全部”入口和当前仓库所有 Blog 标签；内置标签会随界面语言本地化显示，自定义标签保持原始写法；标签较多时可以左右滑动，长标签不会被截断
- 内容区支持左右滑动按标签翻页，使用 UIKit 的 `UIPageViewController` 系统滚动转场；垂直列表滚动仍保留给当前标签内容
- 文章按时间倒序排列
- 带图 Blog 卡片默认保留横版封面布局，也支持按文章切换为左侧竖图、右侧标题 / 四行摘要 / 日期标签的竖版布局
- 每篇 Blog 会在日期后显示当前标签
- Blog 文章不会进入 Journal / Calendar，但会被 Search 检索
- 列表支持下拉刷新；如果当前正在看共享仓库，会检查当前仓库是否有最新内容；如果 CloudKit 要求稍后重试，会显示下次可重试时间

### 3.6 文章阅读与编辑

- 列表卡片只负责进入详情页
- 详情页默认是阅读模式，不再混合编辑控件
- 右上角 `编辑` 进入编辑模式
- 编辑模式顶部固定为 `取消 / 保存`
- 删除入口只在编辑模式里显示
- Journal / Blog 标题和正文至少需要填写一项；只写标题或只写正文都可以保存，两者同时为空时不会保存
- 没有标题时，列表卡片和详情页都不会强行补一个占位标题
- Blog 编辑页会提供标签选择器，新建 Blog 默认落到 `note`
- Blog 编辑页会提供 `Landscape / Portrait` segmented control，用来切换带图卡片的横版 / 竖版封面布局
- 竖版 Blog 在详情页会保持题图全宽显示，并限制最大高度；超过上限时会从顶部和底部等量裁剪
- Blog 详情页和列表卡片都会在日期后显示标签
- 插图入口只有相册选图，不再支持图片链接输入
- 选图后会立刻压缩，预览和最终落盘都使用压缩后的图片
- 编辑页的图片预览下方会显示 `Delete Image`，可直接移除当前插图
- 点 `Save` 时会先完成本地保存并关闭编辑器；如果当前仓库连接了 CloudKit，云端上传会在后台继续执行，不再把保存按钮卡在网络上传上

### 3.7 Settings

设置页当前承担的是完整的仓库管理界面，而不只是一些零散开关：

1. 在 `Repository Status` 里切换当前仓库，并查看当前权限
2. 选择共享邀请权限、生成 CloudKit 邀请，并在 `CloudKit Sharing` 里设置仓库级 `Repository Push Updates`
3. 接受别人发来的 iCloud 共享链接
4. 开关“共享仓库更新提醒”（只控制可见的本地通知 + 应用角标），并设置个人 `Personal Push Updates` 默认值；后台同步始终保持开启。只有当仓库主人把当前仓库的 `Repository Push Updates` 设为 `All` 时，这个个人提醒设置才会对该仓库生效；切换范围时会先弹确认框
5. 开关生物识别解锁（Face ID / Touch ID，失败时可回退到系统锁屏密码）
6. 管理 Blog 标签：新增、长按拖动排序、删除；拖动时列表会实时让位，放手后完成排序；删除已使用标签时会在居中确认框里选择旧文章迁移到哪个标签
7. 导出当前仓库 ZIP
8. 导入 ZIP 到当前仓库
9. 指定启动时默认打开哪座仓库
10. 清空当前仓库内容
11. 在页面底部的 `Date & Time` 中选择“跟随系统”或“北京时间”；新安装和旧版升级均默认跟随系统，修改后持久保存

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
- 应用显示名：`Kala Journal`
- 当前代码 / 待发布版本：`1.2.11 (4)`
- 当前 App Store 已发布版本：`1.2.10 (3)`
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
- `EntryRecord` 中的 `happenedAt` / `createdAt` / `updatedAt` 都是与时区无关的 `Date` 绝对时间点，落盘时编码为 ISO 8601 UTC（例如 `2026-04-16T09:00:00Z`）；应用所选时区只决定显示日期和“属于哪一天”，不改写原始时间戳
- `RepositorySnapshot` 表达一座仓库当前的全部文章，以及这座仓库自己的 Blog 标签顺序
- `RepositoryDescriptor` 表达这座仓库在 CloudKit 里的身份和权限
- `RepositoryReference` 表达“这台设备知道哪些仓库、显示名是什么、最近何时打开”

### 4.4 本地存储布局

当前本地数据已经从单仓库目录演进为“仓库库 + 偏好 + 多仓库目录”结构：

```text
Application Support/thatDay/
  preferences.json
  repositories.json
  cloudkit-change-tokens/
    private-database-change-token.data
    shared-database-change-token.data
    private-pending-zone-ids.json
    shared-pending-zone-ids.json
    private-pending-deleted-zone-ids.json
    shared-pending-deleted-zone-ids.json
  repositories/
    local/
      descriptor.json
      repository.json
      pending-cloud-upload.json
      images/
        <uuid>.jpg
    shared-.../
      descriptor.json
      repository.json
      pending-cloud-upload.json
      read-only-upload-recovery/
        pending-cloud-upload-<operation-id>.json
        cached-repository-<legacy-id>/
      images/
        <uuid>.jpg
```

这套结构由 `RepositoryLibraryStore` 管理，它还负责把旧版“根目录单仓库”数据自动迁移到 `repositories/local/`。

`pending-cloud-upload.json` 会在 CloudKit owner / editor 仓库存在待提交内容或待完成回执时出现；viewer 永远不会拥有活动 outbox。本地仓库第一次发起共享时，也会先以 `prepareShare` 模式写入同一份 durable outbox。当前 v3 格式除待上传快照、图片和 operation chain 外，还保存不内嵌图片的共同基线快照、精确时间位模式、内容摘要与图片哈希清单，用于重启后的三方合并和完整性校验；旧版 v2 的 ISO 8601 日期、legacy SHA-256 摘要和无基线格式会兼容读取，并在下一代写入时迁移。成功提交并把服务端基线写回 catalog 后会移除；`encryptedDataReset` 恢复回执会保留到对应删除事件已确认，避免确认失败后重复重建。旧版本在 viewer 仓库留下的 outbox 或只有 catalog 标记的待上传缓存，会先转入 `read-only-upload-recovery/` 再解除下行阻塞；该目录不参与自动上传，但会随手动 ZIP 导出一起保留。

`preferences.json` 保存设备端的应用时区选择、最近一次成功云同步时间、CloudKit retry-after 截止时间和上一次确认的 CloudKit 用户记录标识；旧版偏好缺少普通字段时使用兼容默认值，缺少账户标识且已有云数据时则 fail-closed 等待一次明确确认。它不属于仓库快照，因此不会通过 CloudKit 强制其他共享成员使用同一时区。

`repository.json` 现在除了文章数组，也会保存仓库级 Blog 标签配置，以及每篇 Blog 的图片卡片布局，因此标签顺序、增删结果、文章标签和横版 / 竖版显示方式都会跟随本地持久化、共享快照和 ZIP 导入导出一起移动。

### 4.5 多仓库与共享权限

当前权限模型分为四种：

- `local`
- `owner`
- `editor`
- `viewer`

它们不只是展示文案，而是直接决定：

- 是否允许编辑
- 是否允许创建、恢复、调度和执行 outbound upload
- 使用 private 还是 shared CloudKit database
- 是否能发起共享
- 是否能导入 / 清空 / 删除内容

`RepositoryReference` 进一步补上了设备侧关心的信息，例如显示名、最近打开时间、服务端 record change tag、订阅配置校验时间、持久化的待上传时间 / 代际 / 上传基线、purge 清理 tombstone，以及并发冲突或云端 zone 不可用状态。

### 4.6 云端同步、通知与路由

这部分现在是完整链路，不再只是“能生成分享链接”：

- `CloudRepositoryService` 负责把整仓库快照保存到 CloudKit 的 `CKRecordZone`
- 云端快照根记录固定落在该 zone 里的 `RepositoryRoot` 记录，字段包括 `updatedAt`、`entryCount` 和 `payload`；`payload` 保存不内嵌图片的 JSON，`updatedAt` / `entryCount` 用于轻量判断是否需要下载完整快照
- 本地图片单独保存为 `RepositoryImageAsset` 记录，字段包括 `reference`、`contentHash` 和 `payload`；v4 根快照另保存每个引用的 SHA-256 manifest。文字修改时不会查询、下载或上传数百张未变化图片；只轻量检查新增 / 哈希变化的引用和待删除记录，再把根记录、变化图片和孤儿图片删除放进同一个 `.ifServerRecordUnchanged` 原子事务。旧版根快照没有 manifest 时会走一次兼容校验，旧版曾用相同引用原地替图时也会按哈希重新下载 / 上传，不会永久显示旧缓存
- `thatDayApp.swift` 负责接住 scene/app 生命周期、远端推送、低频后台刷新、iCloud 账号变化和共享接受事件
- `AppEventBridge.swift` 里的 `RepositoryRemoteChangeCenter` / `NotificationRouteCenter` 负责把系统事件桥接回 `AppStore`
- `AppStore` 负责按启动 / 前台 / 推送 / 系统后台恢复 / 手动五类触发刷新共享仓库、比对快照差异、生成本地通知和应用角标，以及在点击通知后切换到对应仓库和文章；手动下拉只检查当前共享仓库
- shared database 使用一份稳定、不过滤记录类型的 `CKDatabaseSubscription`；每座 private owner 仓库使用稳定的逐 zone `CKRecordZoneSubscription`。`1.2.10` 修复时只补建或纠正稳定订阅、保存后按 ID 读回确认，绝不在同一迁移里删除旧订阅，因此即使某次保存失败也不会再次形成“新旧订阅同时不存在”的漏推窗口。订阅状态会在本地记忆并以七天为周期校验；同一轮 private / shared database 各批量盘点一次，发生修复时额外批量读回一次。普通失败在本次进程内不反复重试，CloudKit 返回 retry-after 时则严格等到冷却到期
- `CKAccountChanged` 到达后会先隔离并等待当前账户的下载刷新、reset reconciliation 和所有上传者停稳，再查询账户状态和稳定用户标识；每一次异步读写、分享接受和 transition reset 都携带账户 epoch，旧账户请求晚回时无权覆盖缓存、确认 change token 或重新解除隔离。相同账户恢复时会重置 change token、重新验证订阅并追赶，临时不可用或查询失败时保留全部 outbox 并指数退避，真实换账号时保持隔离
- 账户未确认期间收到的分享链接 / metadata 会先排队，确认后再处理；冷启动时即使系统分享或通知深链任务先于 `ContentView.loadIfNeeded` 执行，也会先加载磁盘 catalog 并完成账户闸门，不会用初始空 catalog 覆盖已有仓库，也不会丢掉通知目标
- 数据库推送到达后先用持久化 `CKServerChangeToken` 读取发生变化的 zone，只刷新这些仓库；新 token 和待处理 zone 会先原子落入本地收件箱，只有仓库快照成功保存后才确认对应 zone，因此下载失败或进程中止不会永久漏掉这次 invalidation
- 三类 zone 删除原因分别处理：普通 `deleted`（包括共享被撤销）保留最后一份缓存并标成不可用只读；`purged` 会先把禁止补传的 tombstone 写入 catalog，再按 Apple 语义幂等删除本地缓存，即使清理中途终止也不会在重启时重建 outbox；`encryptedDataReset` 会让 owner 从持久化 outbox 或完整本地快照重建 private zone，共享参与者则保留无权重建的只读缓存。重建回执及其后续编辑代际会一直保留恢复模式，直到对应 change-token 删除事件确认成功；如果本地快照或其中任何图片缺失，恢复会失败并保留事件等待重试，绝不上传空仓库或不完整快照
- 远端推送回调不再只把事件塞进前台队列并提前返回，而是在 iOS 提供的后台执行窗口里真正完成同步，再把真实结果交回系统
- Journal / Blog 的手动下拉刷新会直接复用共享仓库拉取链路；应用启动会立即追赶，回到前台超过 `30` 秒会追赶，系统另提交最早一小时后的 `BGAppRefreshTask` 作为漏推送兜底；后台任务一开始就尝试提交下一次 successor，系统接受该请求时，即使本次执行中途终止也仍保留后续兜底。后台兜底按 private / shared database change token 增量检查，不逐座仓库轮询，是否接受和何时执行仍由 iOS 决定
- 定向 zone 推送、单仓库手动刷新不会重置“完整前台巡检”的去抖时间；因此某座仓库刚被推送刷新，也不会让另一座漏掉推送的仓库在应用打开时继续等待
- 快照是否变化优先使用 CloudKit 服务端 `recordChangeTag`，不再把客户端 `updatedAt` 当作跨设备权威时钟；这可以覆盖“时间戳和条目数相同但正文已变”的情况
- 如果 CloudKit 返回 retry-after，例如 `requestRateLimited`、`serviceUnavailable` 或嵌套在 partial failure 里的限流错误，应用会把冷却截止时间写入 `preferences.json`；同一批多仓库 / 多订阅处理会立即停止后续请求，冷却期间自动同步和待上传补传都会跳过，后台兜底不会把这次跳过误记成成功刷新。应用在前台时会按这个绝对截止时间安排单个可取消唤醒，到期自动补传和追赶；后台 request 的 earliest date 也不会早于更长的冷却时间，避免重启或多仓库循环绕过限流形成 retry storm
- 共享仓库保存使用本地优先策略：`Save` 会先把完整待上传快照、图片、代际、CloudKit change tag、共同基线快照、内容摘要和唯一 operation ID 原子写入 `pending-cloud-upload.json`，再更新本地缓存与 catalog，CloudKit 上传进入仓库级后台队列；每个新代际会保留尚未确认的 predecessor operation IDs。即使云端已写成功、进程却在本地回执落盘前终止，重启后也能从远端 operation ID 证明这次写入属于自己，继续推进基线而不是产生假冲突
- outbound eligibility 只有一套统一规则：普通上传只允许当前 catalog 中同一 zone 的 owner / editor，首次分享只允许本地仓库，encrypted-data-reset 只允许 owner；排队项和 outbox 中的旧 descriptor 都不能恢复或提升当前权限。editor 每次真正写入前还会读回当前 `CKShare` 权限，若 owner 已降为只读，则在 CloudKit 写操作之前把 outbox 转成恢复副本、切换为 viewer 并恢复下行同步；写入时遇到 `permissionFailure` 也执行同一 fail-closed 流程
- 同一仓库的普通保存、`encryptedDataReset` 重建和分享前保存全部经过同一个单写者队列；连续保存会合并最新代际并串行上传，旧上传完成时不会误清除或覆盖较新的待上传内容
- 替换文章图片会先写入新的不可变文件引用，等包含新图片的 snapshot / outbox durable 后才清理旧图；失败时恢复旧快照和旧图片，避免在 CloudKit 尚未收到变化前原地破坏已提交内容
- 接受可编辑共享时会在首次下载中同时保存服务端 `recordChangeTag`，因此接受后的第一次编辑会直接带正确基线提交，不会因为缺少基线产生假冲突
- 每个待上传代际会记录最后一次已确认的 CloudKit `recordChangeTag`，保存使用 `.ifServerRecordUnchanged`。发生 `serverRecordChanged` 后会把服务端快照与 metadata 原子读回：远端 operation ID 等于当前操作时恢复本地回执，等于 predecessor 时推进基线后重试，属于另一端更新时按共同基线做三方合并，并先持久化 successor outbox 再更新本地 UI 和重试 CAS。同一保存只做有界的立即恢复，连续竞争则至少等待 `60` 秒且不早于 CloudKit retry-after，再由持久化后台机制继续，避免请求风暴
- 当共享仓库正在本地保存或后台上传时，较旧的前台 / 推送刷新结果不会再覆盖当前设备刚写入的快照；新建或编辑后的文章会稳定留在列表里，不会先消失再晚点重新出现
- “可见提醒”与 CloudKit 静默同步相互独立：用户拒绝通知权限或关闭 Settings 中的提醒时，订阅、后台同步和前台追赶仍然工作，只是不显示横幅、声音和角标
- 角标不再跟“是否读过某篇文章”绑定；当后台同步检测到共享内容变化且可见提醒已开启时标 `1`，应用进入前台后立即清零

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
- 同步到 CloudKit 时，会把当前快照引用到的本地图片写进独立图片资产记录；其他设备拉取后会自动恢复到本地 `images/` 目录

### 4.8 导入导出与迁移

- `RepositoryArchiveService` 负责把当前仓库打包成 ZIP，并从 ZIP 恢复仓库
- 导出包包含 `repository.json`、`descriptor.json`、`images/` 文件夹，以及存在时的 `read-only-upload-recovery/` 本机恢复副本
- 导入时会保留当前仓库描述信息里的权限语义，并覆盖当前仓库内容
- 导入导出的仓库文件路径现在按标准化后的相对路径计算，不再依赖绝对路径字符串替换；即使系统把同一路径写成不同前缀，仓库图片也会回到正确的 `images/` 目录
- 从系统“文件”里选择外部 ZIP 导入时，会先申请并持有该文件的安全作用域读权限，再执行解压，避免选中文件后误报“没有足够权限”
- 覆盖导入会先在仓库同一磁盘卷的相邻目录完整解压并校验快照和所有图片，再通过安全目录替换提交；外置事务标记和备份让应用在替换前后被终止时都能继续恢复。云端仓库还会在 live / staged 两侧先写好带 predecessor 链的下一代 outbox，目录替换后仍由同一仓库级单写者队列上传，避免导入内容已经显示但待上传状态随旧目录丢失
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
- `thatDay/Services/CloudChangeTokenStore.swift`
- `thatDay/Services/CloudUploadOutboxStore.swift`
- `thatDay/Services/RepositoryArchiveService.swift`
- `thatDay/Services/AppEventBridge.swift`
- `thatDay/Support/EntryImageCompressor.swift`

## 5. 运行与测试

### 5.1 运行

可以直接在 Xcode 打开 `thatDay.xcodeproj`，运行 `thatDay` scheme。

如果用命令行构建：

```bash
xcodebuild build -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=64C6D6C5-D361-411C-B2EC-AFC37DC1A55E'
```

### 5.2 测试命令

当前机器上可用并已经验证通过的完整测试命令是：

```bash
xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=64C6D6C5-D361-411C-B2EC-AFC37DC1A55E' -parallel-testing-enabled NO
```

这里显式使用 `iPhone 17 Pro` 模拟器，并关闭并行测试，避免额外 simulator clone。

单元测试和大多数 UI 测试会通过 `THATDAY_APP_LANGUAGE=en` 与 `-AppleLanguages (en)` 固定英文环境，避免不同系统语言影响断言；另有一条 UI 用例会显式切到简体中文验证本地化界面。

UI 测试模式会在 Blog Tags 管理区暴露测试专用重排按钮，用于稳定验证标签顺序持久化；正式运行不会显示。

### 5.3 当前测试覆盖

单元测试覆盖：

- Journal 同月同日跨年分组、日期标题、回到今天、显式页面日期读取与跨日日期计算
- Search 空态与 Journal / Blog 混合命中
- Calendar 网格生成与月份切换
- Blog 持久化、默认标签、显式标签页读取、标签页边界、标签删除 / 重排 / 打开筛选
- Journal / Blog 总字数统计与数字缩写
- 共享仓库接受、可编辑共享首次保存的服务端基线、默认仓库启动、手动刷新、服务端 change tag、database change token 定位与持久化待处理 zone 收件箱、CloudKit retry-after 跨启动冷却、后台推送真实 completion、通知路由与图片恢复
- 通知权限关闭时后台同步继续、文章删除提醒、前台 `30` 秒追赶去抖、后台兜底按数据库增量检查、推送只刷新发生变化的 zone
- 共享仓库保存先落完整 outbox、CloudKit 后台上传、进程中断后从 outbox 恢复精确快照、operation / predecessor 幂等链、上传回执恢复、失败上传跨启动和 retry-after 到期补传、重叠上传代际与基线推进、服务端冲突不覆盖，以及根记录与变化 / 删除图片的单次原子提交
- outbox v2 → v3 迁移、共同基线与亚秒时间摘要校验；同条目双改的确定性副本、双方独立新增 / 编辑、删除与修改、同图片引用但字节不同、旧合并结果重放不增殖，以及无基线时的保守无损 union
- viewer 遗留 pending / conflict 且无 outbox、viewer 携带 stale editor outbox、无 catalog 的孤立 outbox、服务端在 preflight 或实际写入阶段把 editor 降为只读；验证权限不被旧 descriptor 提升、活动上传被隔离、恢复副本保留且 owner 的远端更新仍能正常下行
- 首次分享的 G / G+1 在 owner 权限已获得但 catalog 尚未提交时崩溃，以及只读恢复副本经过 ZIP 导出再导入两条路径；验证恢复证明不会被当作越权上传，嵌套的 snapshot、descriptor 和图片也不会在归档回环中丢失
- Cloud payload 把日期规范到整秒时不制造假双改或假删除，并覆盖 1970 年前的负时间戳
- 启动账户确认不阻塞本地缓存、旧版本首次绑定必须明确确认、确认前编辑只落 outbox 不上传、相同账户恢复、真实 A → B 换号持续隔离、账户通知先停读写再查询、查询失败退避重试、旧 refresh / share / reset 晚回失效、冷启动分享与通知先加载 catalog，以及 G / G+1 冲突读取不会覆盖较新本地保存
- 分享前 durable `prepareShare` 上传、分享失败跨启动续传、准备分享上传期间继续编辑的下一代串行补传，以及图片替换的不可变引用 / 回滚 / 延迟清理
- zone 下载失败后不提前确认、后续成功重试，以及普通删除、带持久化 tombstone 的 `purged`、private owner / shared participant 的 `encryptedDataReset` 分支、重复 reset 回执、确认前继续编辑、并发新代际、缺失快照 / 图片拒绝上传、单写者恢复和确认时机
- 生物识别开关与前后台再认证
- ZIP 导入导出回环、权限错误映射、同卷 staging 与安全目录替换、外置事务恢复、导入覆盖后 outbox 保留、pending predecessor 串联与清空仓库
- 图片落盘压缩到 `100KB` 以下；v4 哈希 manifest 的本地缓存命中、300 张未变图片零传输、旧版无 manifest / 同引用替图、历史 orphan record、下载 payload / record / root 哈希不一致拒绝确认

UI 测试覆盖：

- Journal 空态、新建无标题、头部日期回到今天、`Previous / Next` 与 `UIPageViewController` 左右滑动切日
- Journal 翻页性能用例使用 seeded 多条 Journal 往返滑动，记录耗时、CPU、内存以及 XCTest 可用的滚动 / hitch 指标
- Calendar 月份切换、`Today`、标签统计点击跳转与内容宽度
- Blog 新建 / 编辑 / 删除、图片布局持久化、标签筛选、`UIPageViewController` 左右滑动切标签与 Search 联动
- Blog 翻页性能用例使用 seeded 多条 Blog 往返滑动，记录耗时、CPU、内存以及 XCTest 可用的滚动 / hitch 指标
- Blog 详情在无图 / 竖图场景下的布局
- Settings 打开、Blog 标签重排持久化、只读仓库隐藏创建入口
- 简体中文界面文案、tab 标题与日期头部显示
- Launch tests 的不同外观与方向组合

### 5.4 最近一次完整验证

- 时间：2026-07-27 20:57 - 21:05（Europe/London）
- 单元测试命令：`xcodebuild test -quiet -project thatDay.xcodeproj -scheme thatDay -destination 'platform=iOS Simulator,id=64C6D6C5-D361-411C-B2EC-AFC37DC1A55E' -derivedDataPath /private/tmp/thatDay-readonly-fix-unit-final-20260727 -only-testing:thatDayTests`
- UI 测试命令：`xcodebuild test -quiet -project thatDay.xcodeproj -scheme thatDay -destination 'platform=iOS Simulator,id=64C6D6C5-D361-411C-B2EC-AFC37DC1A55E' -derivedDataPath /private/tmp/thatDay-readonly-fix-ui-final-20260727 -only-testing:thatDayUITests`
- 结果：通过
- 单元测试：188 项通过，零失败、零跳过
- UI 测试：32 次执行通过（24 个常规 UI 用例 + 8 个 Launch test 动态参数运行），零失败、零跳过
- 单元测试 xcresult：`/private/tmp/thatDay-readonly-fix-unit-final-20260727/Logs/Test/Test-thatDay-2026.07.27_20-57-10-+0100.xcresult`
- UI 测试 xcresult：`/private/tmp/thatDay-readonly-fix-ui-final-20260727/Logs/Test/Test-thatDay-2026.07.27_20-58-07-+0100.xcresult`
- generic iOS `build-for-testing`（App、单元测试、UI 测试目标）：通过
- `1.2.11 (4)` 无签名 generic iOS Release 构建：通过

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
- Apple 明确把静默推送和后台任务定义为系统调度的低优先级机会；Background App Refresh 被关闭、低电量 / 网络条件不合适或用户强制退出时，后台更新可能延后。实现依据：[Pushing background updates to your app](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)、[Handling notifications and notification-related actions](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:didreceiveremotenotification:fetchcompletionhandler:))、[Using background tasks to update your app](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app)
- CloudKit 推送只表示“可能有变化”，客户端仍需用 database / zone change token 拉取并保存游标；推送可以合并，不能当作逐条事件日志。实现依据：[Remote records](https://developer.apple.com/documentation/cloudkit/remote-records)、[CKDatabaseSubscription](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription)
- CloudKit 没有适合客户端硬编码的统一“每分钟请求上限”，服务会动态节流；应用必须读取 retry-after 并延后。实现依据：[Understanding CloudKit throttles](https://developer.apple.com/documentation/technotes/tn3162-understanding-cloudkit-throttles)、[CKErrorRetryAfterKey](https://developer.apple.com/documentation/cloudkit/ckerrorretryafterkey)
- `CKAccountChanged` 只表示 CloudKit 账号状态发生变化，不能直接等同于用户切换 Apple ID；临时不可用也必须保留本地缓存和待上传内容，等账户身份重新确认。实现依据：[CKAccountChanged](https://developer.apple.com/documentation/cloudkit/ckaccountchangednotification)、[CKAccountStatus.temporarilyUnavailable](https://developer.apple.com/documentation/cloudkit/ckaccountstatus/temporarilyunavailable)
- 并发写入继续依赖 `.ifServerRecordUnchanged`，并在 `serverRecordChanged` 后重新读取服务器记录再判断 operation chain 或执行三方合并，绝不直接覆盖。实现依据：[CKModifyRecordsOperation.SavePolicy](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/savepolicy)、[CKError.serverRecordChanged](https://developer.apple.com/documentation/cloudkit/ckerror/serverrecordchanged)
- 当前 `AppStore` 仍同时承担 UI 状态、仓库 I/O、账户切换、上传、下载、订阅和重试，且权限 / pending 信息跨 catalog、descriptor 与 outbox 保存；本次已经用统一 outbound eligibility 和 durable authorization fence 收紧正确性，但后续同步架构应增量抽成独立 `RepositorySyncEngine` actor，并让 outbox 成为 active pending 的唯一持久事实来源，避免继续在主状态对象里增加双向恢复分支
- Settings 里的“导入 ZIP 到当前仓库”当前仍是覆盖导入，不做差异合并；如果以后要支持 merge，需要先重新定义冲突规则

## 8. 许可协议

- 根目录新增 `LICENSE`，当前仓库使用自定义 `thatDay Attribution for Commercial Use License 1.0`
- 该许可允许个人、学习、研究、修改、分发和商业使用
- 商业使用时，必须在产品说明、About 页、Credits 页或其他对最终用户可见的合理位置注明原项目 `thatDay` 与仓库地址：`https://github.com/MrGodfrey/salaJournaliOS`
- 该许可是按当前项目诉求编写的自定义协议，不属于 GitHub 常见的 SPDX/OSI 标准许可证；仓库页面可能不会像 `MIT`、`Apache-2.0` 这类标准协议那样自动识别
