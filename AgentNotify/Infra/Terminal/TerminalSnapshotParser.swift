import Foundation

struct TerminalSnapshotParser {
    func parse(_ raw: String) throws -> [TerminalTabSnapshot] {
        let data = Data(raw.utf8)
        return try JSONDecoder().decode([TerminalTabSnapshot].self, from: data)
    }
}
