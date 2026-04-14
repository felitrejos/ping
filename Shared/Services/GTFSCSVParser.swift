import Foundation

enum GTFSCSVParser {
    static func parse(text: String) throws -> [[String: String]] {
        let rows = tokenize(text: normalizeLineEndings(in: text))
        guard let headerRow = rows.first else {
            return []
        }

        let headers = headerRow.map(normalizeHeader)
        return rows.dropFirst().compactMap { row in
            guard row.contains(where: { !$0.isEmpty }) else {
                return nil
            }

            var dictionary: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                dictionary[header] = index < row.count ? row[index] : ""
            }
            return dictionary
        }
    }

    private static func tokenize(text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if isInsideQuotes {
                if character == "\"" {
                    let nextIndex = index + 1
                    if nextIndex < characters.count, characters[nextIndex] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        isInsideQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    isInsideQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""

                    let nextIndex = index + 1
                    if nextIndex < characters.count, characters[nextIndex] == "\n" {
                        // Consume LF in CRLF.
                        index += 1
                    }
                default:
                    field.append(character)
                }
            }
            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    private static func normalizeHeader(_ value: String) -> String {
        var header = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if header.unicodeScalars.first == "\u{FEFF}" {
            header = String(header.dropFirst())
        }
        return header
    }

    private static func normalizeLineEndings(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
