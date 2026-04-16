import Foundation

enum SampleData {
    static func makeEntries() -> [EntryRecord] {
        [
            EntryRecord(
                id: UUID(uuidString: "A0B79942-8340-4CE0-A406-CB0D335FD061")!,
                kind: .journal,
                title: "The Quiet Morning Echoes",
                body: "There was a specific kind of silence this morning. Not the absence of sound, but the presence of peace. I sat by the window and watched the fog roll over the valley.",
                happenedAt: fixtureDate("2026-04-16T08:30:00Z"),
                createdAt: fixtureDate("2026-04-16T08:30:00Z"),
                updatedAt: fixtureDate("2026-04-16T08:30:00Z"),
                imageReference: "https://lh3.googleusercontent.com/aida-public/AB6AXuB3QaQZJwQYn8dOY2NzBe0b2pcBVgXk0ffGBWnjakmRu7efJEa_VhpeqDEeav4amQP627bh0h8oyy80_GSAK9JTN2nlTTtm9asYzuR4p8uWWjWIsw_Fz32f-ar6G41-u88jEE-SFtmuEup2WqtVQVf3BEfUKLR1gKgp8W6ZcOYkxWzvyAv8Z9e3hJdAb-gJnyFcEFJZP0RbtBm1sMQpbxJzlWGy8SCo8fgHJkHTqO_uDnSl7ThWgIFvdVTjP4PW-49lef-kWYenu1E"
            ),
            EntryRecord(
                id: UUID(uuidString: "5F299093-8586-4D84-9B35-64F30B7E8CF8")!,
                kind: .journal,
                title: "Reflections on Stillness",
                body: "Learning to be okay with nothingness. Today I did not reach for my phone for the first hour of waking. It felt like reclaiming my own mind from the digital noise.",
                happenedAt: fixtureDate("2025-04-16T07:45:00Z"),
                createdAt: fixtureDate("2025-04-16T07:45:00Z"),
                updatedAt: fixtureDate("2025-04-16T07:45:00Z")
            ),
            EntryRecord(
                id: UUID(uuidString: "9A9545D7-E05C-462B-881C-2A2782EEA860")!,
                kind: .journal,
                title: "New Project Idea",
                body: "What if the interface felt like physical stationery? Using tonal shifts instead of lines to define spaces. Minimalist but warm.",
                happenedAt: fixtureDate("2024-04-16T10:00:00Z"),
                createdAt: fixtureDate("2024-04-16T10:00:00Z"),
                updatedAt: fixtureDate("2024-04-16T10:00:00Z")
            ),
            EntryRecord(
                id: UUID(uuidString: "9353268D-8E53-49B7-90BF-C8D726F604B5")!,
                kind: .journal,
                title: "Midnight Thoughts",
                body: "Writing in the dark has a different rhythm. The words feel more honest when no one, not even the sun, is watching.",
                happenedAt: fixtureDate("2023-04-16T09:50:00Z"),
                createdAt: fixtureDate("2023-04-16T09:50:00Z"),
                updatedAt: fixtureDate("2023-04-16T09:50:00Z"),
                imageReference: "https://lh3.googleusercontent.com/aida-public/AB6AXuDs0wZok43Hg0cgMta7tH2nG8yRvpousGYjc1gtQ30dfXw5yKLFUx_Os0wOuZJbWzKauVSqJbpAGPWCGi1KzgeY1ZIggU_zTPZZ0EEPfDGKyUcdLfnNTxz2gcctg2lp-U0RErSv01bQzVvg2oM9-SNM3ZmuRP1Y4vj2WMhV5yDpZsr-GiCnzJAUf3ZVOOEtvGAHhbqygfiXm3jvG1oqmsWxH5Wbs8Mv93DXtJn41d9VSdIuqcvgylFeT8QJwSpGZjR0U1AH-lgCHE0"
            ),
            EntryRecord(
                id: UUID(uuidString: "BC48B5B5-3DE6-492B-9C70-7824AFC772AA")!,
                kind: .journal,
                title: "Random Memory",
                body: "Just another day in May.",
                happenedAt: fixtureDate("2026-05-20T12:00:00Z"),
                createdAt: fixtureDate("2026-05-20T12:00:00Z"),
                updatedAt: fixtureDate("2026-05-20T12:00:00Z")
            ),
            EntryRecord(
                id: UUID(uuidString: "CF57B7A6-BE10-4C24-A5D8-282B667A88AC")!,
                kind: .blog,
                title: "The Art of Morning Stillness",
                body: "Discovering the profound impact of intentional silence before the digital world demands our attention.",
                happenedAt: fixtureDate("2023-10-24T09:00:00Z"),
                createdAt: fixtureDate("2023-10-24T09:00:00Z"),
                updatedAt: fixtureDate("2023-10-24T09:00:00Z"),
                imageReference: "https://lh3.googleusercontent.com/aida-public/AB6AXuBh4qhh-M2lQLL6FS2kFGECetLWfoasB9PXdlKHoquZotUdJ-4_6jwb7epx6KycfQkjyCKelqTZcAUAnZrhMO1ONL4-Yhex0Ac1DGCrEhEUtx0ujvYjw-v-62A4ocq19RiwX3EpgFLc8NGLvzslZtDSO53Amvz10g2ONOTP0-lW3hZ9T1eLa99W5CY-lYV5Tgn-KFSHghnvD7je5yV3K0qbhGL5R5DhL7X4BaqLhJhZKrO0877XwIA1Ic8GALk1rptcy4GnOt2Jw-s"
            ),
            EntryRecord(
                id: UUID(uuidString: "92B5347C-1D69-4865-8E8A-97A1DDDF3F45")!,
                kind: .blog,
                title: "Tangible Memories",
                body: "Why the physical act of writing changes how we process our past and visualize our future.",
                happenedAt: fixtureDate("2023-10-22T09:00:00Z"),
                createdAt: fixtureDate("2023-10-22T09:00:00Z"),
                updatedAt: fixtureDate("2023-10-22T09:00:00Z"),
                imageReference: "https://lh3.googleusercontent.com/aida-public/AB6AXuAoFaZXTJyHrHxlcekZczKhqrwkKlw9fHzE0UNa9lkV-D8ni8pcTcm6dGr0d3Xv2io_fKMXNAZ375QYSYyQ9hpgqpk3DwDEgftwK-T0Vq2tCLj7UHU_1JCKaO8bznwgP7_akzhBq4gtdalQchZGtUql-cmmwkbqHcXWRkqWd14Yf9b3zkcdJDCjOLLXxXbr8o2Wr2b4hWewSSPBICVjGh4qeogGIS_evXnnuGm_yc3aacTSCbxKcFCCwXzconRysTyAHMurqNCA_4"
            ),
            EntryRecord(
                id: UUID(uuidString: "4C67CFF4-E6CF-4740-BE2F-58706ACB9213")!,
                kind: .blog,
                title: "Finding Flow in the Mundane",
                body: "Everyday moments carry the weight of legacy. Spotting the extraordinary in the ordinary.",
                happenedAt: fixtureDate("2023-10-19T09:00:00Z"),
                createdAt: fixtureDate("2023-10-19T09:00:00Z"),
                updatedAt: fixtureDate("2023-10-19T09:00:00Z"),
                imageReference: "https://lh3.googleusercontent.com/aida-public/AB6AXuCbD4cyV6ruIzo3uWIO-BxmxcKkd3UtBywa2ACKA3m-34Z65xQ5OeTpi_wUNGB_alkqS8YW_iNaPFpeS2SA1wrcgYZyzRPI_sgiYrHXT3N1QSWfqVhcCDOET1atHI5g02lCYcfWr-wZhkshYBJZCZijCdD4QnQNHFttWHJvAtwA-cS36rZN7Z5sc3l5OyrDUWVdHV3Heou-xEgtmfRbRhO-66NLd2kscxaeWdfkmUzCwFqRlOR9O3CipQVoi4GK07RmEJnkmAgJDwc"
            )
        ]
    }

    private static func fixtureDate(_ rawValue: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue) ?? .now
    }
}
