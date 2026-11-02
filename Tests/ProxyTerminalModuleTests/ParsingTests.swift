import Foundation
import Testing
@testable import ProxyTerminalModule

@Suite struct IPAddressTests {
    @Test func validatesAndNormalizes() {
        #expect(IPAddress.normalized(" 1.2.3.4\n") == "1.2.3.4")
        #expect(IPAddress.normalized("2001:0DB8:0000:0000:0000:0000:0000:0001") == "2001:db8::1")
        #expect(IPAddress.normalized("1.2.3") == nil)
        #expect(IPAddress.normalized("256.1.1.1") == nil)
        #expect(IPAddress.normalized("ip.sb") == nil)
        #expect(IPAddress.normalized("") == nil)
    }

    @Test func comparesByNormalizedForm() {
        #expect(IPAddress.same("2001:db8::1", "2001:DB8:0:0:0:0:0:1"))
        #expect(IPAddress.same("1.2.3.4", " 1.2.3.4 "))
        #expect(!IPAddress.same("1.2.3.4", "1.2.3.5"))
        #expect(!IPAddress.same("1.2.3.4", ""))
    }

    @Test func findsFirstAddressInText() {
        #expect(IPAddress.firstAddress(in: "\n103.227.165.121 \n") == "103.227.165.121")
        #expect(IPAddress.firstAddress(in: "your ip: (2001:db8::1)") == "2001:db8::1")
        #expect(IPAddress.firstAddress(in: "curl: (7) Failed to connect to 127.0.0.1 port 7892") == "127.0.0.1")
        #expect(IPAddress.firstAddress(in: "nothing here") == nil)
    }
}

@Suite struct PaneOutputParserTests {
    let commands = PaneCommands(token: 123_457)

    /// 与 2026-11-02 在真机 iTerm2 里读到的屏幕文字同样的形状
    func screen(result: String, finished: Bool = true) -> String {
        var lines = [
            "Last login: Mon Nov  2 09:12:08 on ttys000",
            commands.enterFolder("/Users/me/my", title: "my"),
            commands.checkIP,
            " me@mac  ~  \(commands.enterFolder("/Users/me/my", title: "my"))",
            " me@mac  ~/my  proxy; curl -s --max-time 10 ip.sb; echo; echo \"MYKIT-END-$((61728+61729))\"",
        ]
        if finished {
            lines += [result, "", "MYKIT-END-123457", " me@mac  ~/my  "]
        }
        return lines.joined(separator: "\n")
    }

    @Test func checkCommandPrintsMarkerOnlyAfterRunning() {
        #expect(commands.checkIP.contains("$((61728+61729))"))
        #expect(!commands.checkIP.contains(commands.marker))
        #expect(61728 + 61729 == commands.token)
    }

    @Test func pendingUntilMarkerAppears() {
        #expect(PaneOutputParser.parse(screen(result: "", finished: false), commands: commands) == .pending)
    }

    @Test func readsAddressBetweenCommandAndMarker() {
        #expect(PaneOutputParser.parse(screen(result: "103.227.165.121"), commands: commands) == .address("103.227.165.121"))
    }

    @Test func noAddressWhenCurlPrintsNothing() {
        #expect(PaneOutputParser.parse(screen(result: ""), commands: commands) == .noAddress)
    }

    @Test func markerFromAnotherRunIsIgnored() {
        let other = PaneCommands(token: 222_222)
        #expect(PaneOutputParser.parse(screen(result: "1.2.3.4"), commands: other) == .pending)
    }

    @Test func folderPathIsShellQuoted() {
        #expect(commands.enterFolder("/a/it's here", title: "it's here")
            == #"export DISABLE_AUTO_TITLE=true; printf '\033]0;%s\007' 'it'\''s here'; cd -- '/a/it'\''s here'"#)
    }
}

@Suite struct PaneLayoutTests {
    @Test func rowsHoldAtMostTwo() {
        #expect(PaneLayout.rows(count: 0) == [])
        #expect(PaneLayout.rows(count: 1) == [1])
        #expect(PaneLayout.rows(count: 2) == [2])
        #expect(PaneLayout.rows(count: 3) == [2, 1])
        #expect(PaneLayout.rows(count: 4) == [2, 2])
        #expect(PaneLayout.rows(count: 9) == [2, 2, 2, 2, 1])
        for count in 1...9 {
            #expect(PaneLayout.rows(count: count).reduce(0, +) == count)
        }
    }

    @Test func titlesAreFolderNamesWithNumbersForDuplicates() {
        let titles = PaneLayout.titles(forFolders: ["/Users/me/work/api", "/Users/me/my", "/x/api", "/Users/me/work/api"])
        #expect(titles == ["api", "my", "api (2)", "api (3)"])
        #expect(PaneLayout.titles(forFolders: ["/"]) == ["/"])
    }
}

@Suite struct ITermScriptsTests {
    @Test func quotesAppleScriptStrings() {
        #expect(ITermScripts.quoted(#"a "b" \c"#) == #""a \"b\" \\c""#)
    }

    @Test func openScriptSplitsEveryPaneAndReturnsAllIDs() {
        for count in 1...9 {
            let panes = (0..<count).map { PaneSpec(title: "t\($0)", lines: ["echo \($0)"]) }
            let script = ITermScripts.open(panes: panes)
            // 每块除了第一块都由一次切分产生，且只产生一次
            for index in 1..<max(count, 1) {
                #expect(script.components(separatedBy: "set p\(index) to (split").count == 2, "count=\(count) pane=\(index)")
            }
            #expect(script.components(separatedBy: "with default profile)").count - 1 == count)
            #expect(script.contains("(id of p\(count - 1))"))
            #expect(!script.contains("(id of p\(count))"))
        }
    }

    @Test func fourPanesMakeTwoByTwo() {
        let panes = (0..<4).map { PaneSpec(title: "t\($0)", lines: []) }
        let script = ITermScripts.open(panes: panes)
        #expect(script.contains("tell p0 to set p2 to (split horizontally"))
        #expect(script.contains("tell p0 to set p1 to (split vertically"))
        #expect(script.contains("tell p2 to set p3 to (split vertically"))
    }

    @Test func parsesContentsRecords() {
        let output = "A\u{1F}my (claude)\u{1F}line1\nline2\u{1E}B\u{1F}\u{1F}\u{1E}"
        #expect(ITermScripts.parseContents(output) == [
            "A": PaneSnapshot(name: "my (claude)", text: "line1\nline2"),
            "B": PaneSnapshot(name: "", text: ""),
        ])
    }

    @Test func applyScriptOnlyTintsFailedPanes() {
        let script = ITermScripts.apply([
            PaneUpdate(sessionID: "A", title: "my ✅ 1.2.3.4", markFailed: false),
            PaneUpdate(sessionID: "B", title: "api ❌ 超时", markFailed: true),
            PaneUpdate(sessionID: "C", title: "web ✅ 1.2.3.4", markFailed: false, typeText: "claude"),
        ], windowID: 7)
        #expect(script.components(separatedBy: "write text").count == 2)
        #expect(script.contains(#"if sid is "C" then\#nset name of s to "web ✅ 1.2.3.4"\#ntell s to write text "claude""#))
        #expect(script.contains("window id 7"))
        #expect(script.components(separatedBy: "set background color").count == 2)
        #expect(script.contains(#"if sid is "B" then"#))
    }
}
