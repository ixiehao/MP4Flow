import AppKit
import ApplicationServices

func fail(_ reason: String) -> Never {
    FileHandle.standardError.write(Data((reason + "\n").utf8))
    exit(1)
}
func require<T>(_ label: String, seconds: TimeInterval = 25, _ search: () -> T?) -> T {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    repeat {
        if let result = search() { return result }
        Thread.sleep(forTimeInterval: 0.15)
    } while ProcessInfo.processInfo.systemUptime < deadline
    fail("Missing " + label)
}
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
func role(_ element: AXUIElement) -> String { attribute(element, "AXRole") as? String ?? "" }
func matches(_ element: AXUIElement, _ title: String) -> Bool {
    ["AXTitle", "AXDescription", "AXValue"].contains { attribute(element, $0) as? String == title }
}
func nodes(_ root: AXUIElement, depth: Int = 11) -> [AXUIElement] {
    guard depth > 0 else { return [] }
    let children = attribute(root, "AXChildren") as? [AXUIElement] ?? []
    return children.flatMap { [$0] + nodes($0, depth: depth - 1) }
}
func press(_ element: AXUIElement, _ label: String) {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard result == .success else { fail("Couldn't press \(label): \(result.rawValue)") }
}
func button(_ owner: AXUIElement, _ title: String) -> AXUIElement {
    require(title) {
        nodes(owner).first { role($0) == "AXButton" && matches($0, title) && attribute($0, "AXEnabled") as? Bool == true }
    }
}
func captureWindow(_ element: AXUIElement, ownedBy pid: pid_t, to output: String) throws {
    guard let pos = attribute(element, "AXPosition"), let size = attribute(element, "AXSize") else { fail("No geometry for capture") }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(pos, to: AXValue.self), .cgPoint, &origin),
          AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent),
          extent.width > 300, extent.height > 150 else { fail("Invalid capture geometry") }
    let choices = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let candidates = choices.compactMap { item -> (Int, CGFloat)? in
        guard item[kCGWindowOwnerPID as String] as? pid_t == pid,
              let id = item[kCGWindowNumber as String] as? Int,
              let bounds = item[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        let distance = abs(rect.width - extent.width) + abs(rect.height - extent.height)
            + abs(rect.minX - origin.x) + abs(rect.minY - origin.y)
        return distance <= 64 ? (id, distance) : nil
    }
    guard let window = candidates.min(by: { $0.1 < $1.1 }) else { fail("No on-screen window matching the QA application's geometry") }
    print("Capturing owned window \(window.0) at \(extent)")
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l", String(window.0), output]
    try capture.run()
    capture.waitUntilExit()
    guard capture.terminationStatus == 0, let image = NSImage(contentsOfFile: output), image.size.width > 300 else {
        fail("Window capture unavailable")
    }
}

print("AXIsProcessTrusted=\(AXIsProcessTrusted()), CGPreflightScreenCaptureAccess=\(CGPreflightScreenCaptureAccess())")
guard AXIsProcessTrusted() else { fail("The isolated macOS runner does not grant Accessibility to the tutorial driver") }
let args = CommandLine.arguments
if args.dropFirst().first == "preflight" { exit(0) }
let (app, bundle, code, task, output) = (args[1], args[2], args[3], args[4], args[5])
let catalogs = URL(fileURLWithPath: app).appendingPathComponent("Contents/Resources/\(code).lproj/Localizable.strings")
let data = try Data(contentsOf: catalogs)
let labels = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
let running = require("re-signed release bundle") { NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first }
let root = AXUIElementCreateApplication(running.processIdentifier)
let workspace = require("MP4Flow main window") {
    (attribute(root, "AXWindows") as? [AXUIElement] ?? []).first { matches($0, "MP4Flow") }
}
let start: () -> Void = {
    press(button(workspace, labels["开始转换"]!), labels["开始转换"]!)
    let _: AXUIElement = require(labels["已完成"]!, seconds: 75) {
        nodes(workspace).first { role($0) == "AXStaticText" && matches($0, labels["已完成"]!) }
    }
}
if task == "convert" {
    start()
    Thread.sleep(forTimeInterval: 0.5)
    try captureWindow(workspace, ownedBy: running.processIdentifier, to: output)
} else {
    let action = labels[task == "trim" ? "剪辑" : "导出设置"]!
    press(button(workspace, action), action)
    let sheet = require("editor sheet") { nodes(workspace, depth: 3).first { role($0) == "AXSheet" } }
    let apply = labels[task == "trim" ? "确认剪辑" : "应用设置"]!
    _ = button(sheet, apply)
    Thread.sleep(forTimeInterval: 1.2)
    try captureWindow(sheet, ownedBy: running.processIdentifier, to: output)
    press(button(sheet, apply), apply)
    start()
}
_ = running.terminate()
let _: Bool = require("QA copy to terminate") { running.isTerminated ? true : nil }
