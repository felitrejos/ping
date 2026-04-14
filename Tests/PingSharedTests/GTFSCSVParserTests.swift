import Testing
@testable import PingShared

struct GTFSCSVParserTests {
    @Test
    func parseSupportsCarriageReturnLineEndings() throws {
        let text = "id,name\r1,Hospital\r2,Sants\r"
        let rows = try GTFSCSVParser.parse(text: text)

        #expect(rows.count == 2)
        guard rows.count == 2 else {
            return
        }
        #expect(rows[0]["id"] == "1")
        #expect(rows[0]["name"] == "Hospital")
        #expect(rows[1]["id"] == "2")
        #expect(rows[1]["name"] == "Sants")
    }

    @Test
    func parseSupportsCRLFLineEndings() throws {
        let text = "id,name\r\n1,Hospital\r\n2,Sants\r\n"
        let rows = try GTFSCSVParser.parse(text: text)

        #expect(rows.count == 2)
        guard rows.count == 2 else {
            return
        }
        #expect(rows[0]["id"] == "1")
        #expect(rows[0]["name"] == "Hospital")
        #expect(rows[1]["id"] == "2")
        #expect(rows[1]["name"] == "Sants")
    }
}
