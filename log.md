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
