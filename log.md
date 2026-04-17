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
