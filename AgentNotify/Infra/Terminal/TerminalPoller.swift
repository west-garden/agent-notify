import Foundation

struct TerminalPoller {
    let runner: AppleScriptRunning
    let parser = TerminalSnapshotParser()

    func poll() throws -> [TerminalTabSnapshot] {
        let script = """
        tell application "Terminal"
            set outputLines to {}
            repeat with w from 1 to count of windows
                set theWindow to window w
                repeat with t from 1 to count of tabs of theWindow
                    set theTab to tab t of theWindow
                    set row to ((id of theWindow as string) & tab & (t as string) & tab & (tty of theTab as string) & tab & (my joinList(processes of theTab, ",")) & tab & (busy of theTab as string) & tab & (contents of theTab as string))
                    copy row to end of outputLines
                end repeat
            end repeat
            return my joinList(outputLines, linefeed)
        end tell
        on joinList(xs, delimiter)
            set AppleScript's text item delimiters to delimiter
            set joined to xs as text
            set AppleScript's text item delimiters to ""
            return joined
        end joinList
        """

        return try parser.parse(runner.run(script))
    }
}
