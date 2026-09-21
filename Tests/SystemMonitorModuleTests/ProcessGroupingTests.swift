import Testing
@testable import SystemMonitorModule

@Suite struct ProcessGroupingTests {
    @Test func processInsideAnAppBelongsToThatApp() {
        let group = ProcessGrouping.group(forPath: "/Applications/WeChat.app/Contents/MacOS/WeChat")
        #expect(group == AppGroup(key: "/Applications/WeChat.app", fallbackName: "WeChat", bundlePath: "/Applications/WeChat.app"))
    }

    @Test func helperInsideNestedAppBelongsToTheOutermostApp() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/129/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        let group = ProcessGrouping.group(forPath: helper)
        #expect(group?.key == "/Applications/Google Chrome.app")
        #expect(group?.fallbackName == "Google Chrome")
        #expect(group?.bundlePath == "/Applications/Google Chrome.app")
    }

    @Test func helperAndMainProcessShareOneGroup() {
        let main = ProcessGrouping.group(forPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        let helper = ProcessGrouping.group(forPath: "/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper")
        #expect(main == helper)
    }

    @Test func processOutsideAnyAppIsGroupedByExecutableName() {
        let group = ProcessGrouping.group(forPath: "/usr/local/bin/node")
        #expect(group == AppGroup(key: "node", fallbackName: "node", bundlePath: nil))
    }

    @Test func sameExecutableNameInDifferentFoldersIsOneGroup() {
        #expect(ProcessGrouping.group(forPath: "/opt/a/java") == ProcessGrouping.group(forPath: "/opt/b/java"))
    }

    @Test func emptyPathHasNoGroup() {
        #expect(ProcessGrouping.group(forPath: "") == nil)
    }
}
