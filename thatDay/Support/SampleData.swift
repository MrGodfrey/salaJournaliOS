import Foundation

enum SampleData {
    static func makeEntries() -> [EntryRecord] {
        [
            EntryRecord(
                id: UUID(uuidString: "A0B79942-8340-4CE0-A406-CB0D335FD061")!,
                kind: .journal,
                title: "欢迎使用 thatDay",
                body: """
                1. 在 Journal 页面左右滑动，可以快速切换前一天和后一天；点击顶部日期，随时回到今天。

                2. 点左上角日历进入 Calendar。年份和月份都可以点开，用滚轮快速跳到想看的年月；右上角 NOW 会直接回到今天。

                3. 右下角蓝色加号用来新建内容。打开文章后，先是阅读模式；点右上角“编辑”再进入修改，保存、取消和删除都在里面。

                4. 在文章卡片上向左滑，可以直接看到“编辑”和“删除”操作。删除前会再次确认。

                5. Search 会同时搜索 Journal 和 Blog；Blog 里的内容只会留在 Blog 和 Search，不会进入 Journal。

                6. 图片请直接从相册选择，不再需要图片链接。
                """,
                happenedAt: fixtureDate("2026-04-16T09:00:00Z"),
                createdAt: fixtureDate("2026-04-16T09:00:00Z"),
                updatedAt: fixtureDate("2026-04-16T09:00:00Z"),
                imageReference: "https://placehold.co/1200x800/png?text=thatDay"
            )
        ]
    }

    private static func fixtureDate(_ rawValue: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue) ?? .now
    }
}
