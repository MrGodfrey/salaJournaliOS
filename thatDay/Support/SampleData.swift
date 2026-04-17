import Foundation

enum SampleData {
    static func makeEntries() -> [EntryRecord] {
        [
            EntryRecord(
                id: UUID(uuidString: "A0B79942-8340-4CE0-A406-CB0D335FD061")!,
                kind: .journal,
                title: "Welcome to thatDay",
                body: """
                1. In Journal, use the Previous and Next buttons to move between days, and tap the date in the title to jump back to today.

                2. Tap the calendar button in the top-left corner to open Calendar. Year and month both open wheel pickers, and NOW jumps back to today.

                3. The blue plus button in the lower-right corner creates new content. Open any entry to read it first, then tap Edit in the top-right corner to update it.

                4. In read-only shared repositories, create actions are hidden and editing is unavailable.

                5. Search looks through both Journal and Blog. Blog entries stay in Blog and Search, and do not appear in Journal or Calendar.

                6. Pick images directly from Photos. Image URLs are no longer needed.
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
