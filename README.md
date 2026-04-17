# thatDay

`thatDay` 是一个 iOS Journal App。它把同一天历年的 Journal 放在一起查看，同时保留独立的 Blog、统一搜索，以及基于 CloudKit 的仓库分享。

当前版本的重点不是把页面做复杂，而是把每天记录、查看、编辑、检索、共享这条主线做顺。

## 1. 设计方式

### 1.1 需求先于实现

这个项目以 [`需求.md`](/Users/wangyu/code/thatDay/需求.md) 为准，不把原型里的每一个视觉细节机械照搬，而是优先满足真实 iOS 使用里的交互稳定性。

最近一轮调整，重点就是把不稳定的手势去掉，改成明确的按钮和阅读页编辑流。

### 1.2 变更可追踪

结构性改动会追加记录到 [`log.md`](/Users/wangyu/code/thatDay/log.md)，而不是覆盖历史。

README 会同步更新当前交互、测试方式和最近一次完整测试结果，方便后续继续迭代。

### 1.3 简单优先

当前版本只保留最直接的内容流：

1. 打开应用看当天
2. 在 Journal / Calendar 之间切换日期
3. 点开文章阅读
4. 进入编辑模式后保存或删除
5. 搜索 Journal 和 Blog
6. 通过设置页分享仓库

## 2. 当前界面与交互

### 2.1 Journal

- 默认展示当天日期
- 顶部中间日期可点击，随时回到今天
- 日期左右两侧提供小型 `Previous / Next` 切换按钮
- 左上角进入 `Calendar`
- 右上角进入 `Settings`
- 右下角蓝色加号用于新建 Journal
- 按“同月同日”聚合同一天历年的文章

### 2.2 Calendar

- 自定义月视图日历
- 年份和月份都可点击，弹出滚轮式选择器
- 右上角 `NOW` 直接回到今天
- 有 Journal 的日期会打点
- 点击日期后回到对应 Journal

### 2.3 Search

- 搜索框为空时，不显示任何文章结果
- 输入关键词后，统一搜索 `Journal + Blog`
- 搜索结果点击后直接进入文章阅读页

### 2.4 Blog

- 使用和 Journal 一致的右下角蓝色加号
- 文章按时间倒序展示
- Blog 内容不会进入 Journal / Calendar，但会进入 Search

### 2.5 文章卡片

整个应用里的文章卡片现在保持统一：

- 图片
- 标题
- 摘要
- `星期 + 月日年`

卡片本身不再支持左滑操作，也不在右下角放额外操作按钮。
卡片右侧也不显示系统默认的向右箭头，整个区域保持为完整卡片。

### 2.6 文章详情页

- 点击卡片后先进入纯阅读模式
- 右上角 `编辑` 进入编辑模式
- 编辑模式顶部按钮固定为 `取消 / 保存`
- 删除入口放在编辑模式里
- 图片只支持从相册选择，不再支持图片链接输入

## 3. 示例内容

首次打开应用时，只保留一篇引导用测试文章：

- 内容：告诉用户如何使用应用
- 图片：占位图

这样可以避免原来的多篇样例内容干扰真实使用和测试。

## 4. 数据与共享

应用当前使用“本地 JSON 仓库 + CloudKit 共享快照”模型。

### 本地仓库

- `Application Support/thatDay/repository.json`
- `Application Support/thatDay/descriptor.json`
- `Application Support/thatDay/images/`

### CloudKit

- 使用独立 `CKRecordZone` 保存整仓库快照
- 通过 `CKShare(recordZoneID:)` 分享整个仓库
- 分享页支持 `仅查看 / 允许编辑`

CloudKit 分享能力的组织方式参考了 `/Users/wangyu/code/homeLibraryApp/homeLibrary`，并按当前项目规模做了简化。

## 5. 关键文件

- [`AppStore.swift`](/Users/wangyu/code/thatDay/thatDay/App/AppStore.swift)
- [`JournalView.swift`](/Users/wangyu/code/thatDay/thatDay/Features/Journal/JournalView.swift)
- [`CalendarView.swift`](/Users/wangyu/code/thatDay/thatDay/Features/Calendar/CalendarView.swift)
- [`SearchView.swift`](/Users/wangyu/code/thatDay/thatDay/Features/Search/SearchView.swift)
- [`BlogView.swift`](/Users/wangyu/code/thatDay/thatDay/Features/Blog/BlogView.swift)
- [`EntryDetailView.swift`](/Users/wangyu/code/thatDay/thatDay/Features/Shared/EntryDetailView.swift)
- [`EntryCardView.swift`](/Users/wangyu/code/thatDay/thatDay/Features/Shared/EntryCardView.swift)
- [`SettingsView.swift`](/Users/wangyu/code/thatDay/thatDay/Features/Settings/SettingsView.swift)
- [`LocalRepositoryStore.swift`](/Users/wangyu/code/thatDay/thatDay/Services/LocalRepositoryStore.swift)
- [`CloudRepositoryService.swift`](/Users/wangyu/code/thatDay/thatDay/Services/CloudRepositoryService.swift)

## 6. 运行

```bash
xcodebuild -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' build
```

也可以直接在 Xcode 里打开 [`thatDay.xcodeproj`](/Users/wangyu/code/thatDay/thatDay.xcodeproj) 运行 `thatDay` scheme。

## 7. 测试

推荐使用下面这条命令跑完整测试：

```bash
xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO
```

### 当前覆盖

单元测试：

- Journal 同日跨年分组
- 搜索空态不返回结果
- 搜索命中 Journal / Blog
- Journal 日期前后切换与回到今天
- Calendar 年月切换状态
- 日历网格生成
- Blog 持久化
- 共享链接接入后的仓库切换与只读权限

UI 测试：

- Search 空态
- Calendar 滚轮选月与 `NOW`
- Journal 顶部日期回到今天
- Journal `Previous / Next` 切换日期
- Blog 新建后进入 Search
- Blog 阅读页进入编辑、保存、删除
- Journal 打开 Settings

### 关于“为什么会 clone 很多模拟器”

这是 `xcodebuild test` 默认并行测试导致的行为。Xcode 会为了同时跑不同测试 bundle，临时复制出多个 simulator clone。

如果不想看到这些 clone，直接加上：

```bash
-parallel-testing-enabled NO
```

我本次完整回归就是用这个参数执行的，所以测试只串行占用一个目标模拟器。

另外，[`thatDayUITestsLaunchTests.swift`](/Users/wangyu/code/thatDay/thatDayUITests/thatDayUITestsLaunchTests.swift) 里保留了：

```swift
override class var runsForEachTargetApplicationUIConfiguration: Bool { true }
```

这会让 `testLaunch()` 在不同外观/方向配置下重复执行几次；这是预期行为，不是额外 clone。

### 最近一次完整测试结果

- 命令：`xcodebuild test -project thatDay.xcodeproj -scheme thatDay -configuration Debug -destination 'platform=iOS Simulator,id=989812C6-88E2-4DFD-B4B4-457AD4CF7324' -parallel-testing-enabled NO`
- 结果：成功
- xcresult：
  - `/Users/wangyu/Library/Developer/Xcode/DerivedData/thatDay-gigtydgyvcksabgwinwrbzgkcfvs/Logs/Test/Test-thatDay-2026.04.17_07-48-08-+0800.xcresult`

## 8. CloudKit 配置说明

要在真机或自己的 iCloud 环境里完整使用分享功能，需要确认：

1. Apple Developer 里已为 `yu.thatDay` 开启 iCloud / CloudKit capability
2. CloudKit 容器 `iCloud.yu.thatDay` 已创建
3. 当前签名团队和 bundle id 与 entitlement 保持一致
4. 设备已登录 iCloud

如果只是本地开发和测试，不依赖 CloudKit 的页面与测试已经可以独立运行。
