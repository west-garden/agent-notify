import Foundation

struct TerminalSnapshotParser {
    func parse(_ raw: String) throws -> [TerminalTabSnapshot] {
        raw
            .split(separator: "\n")
            .map(String.init)
            .compactMap { line in
                let columns = line.components(separatedBy: "\t")
                guard columns.count >= 6 else { return nil }
                return TerminalTabSnapshot(
                    windowID: Int(columns[0]) ?? 0,
                    tabIndex: Int(columns[1]) ?? 0,
                    tty: columns[2],
                    processes: columns[3].components(separatedBy: ","),
                    busy: columns[4] == "true",
                    visibleText: columns[5]
                )
            }
    }
}
