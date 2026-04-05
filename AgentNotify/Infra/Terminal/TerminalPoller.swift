import Foundation

struct TerminalPoller {
    let runner: AppleScriptRunning
    let parser = TerminalSnapshotParser()

    func poll() throws -> [TerminalTabSnapshot] {
        let script = """
        const terminal = Application("Terminal");
        const rows = [];

        terminal.windows().forEach((window) => {
            window.tabs().forEach((tab, index) => {
                rows.push({
                    windowID: Number(window.id()),
                    tabIndex: index + 1,
                    tty: String(tab.tty() || ""),
                    processes: Array.from(tab.processes() || [], (process) => String(process)),
                    busy: Boolean(tab.busy()),
                    visibleText: String(tab.contents() || "")
                });
            });
        });

        JSON.stringify(rows);
        """

        return try parser.parse(runner.run(script, language: .javaScript))
    }
}
