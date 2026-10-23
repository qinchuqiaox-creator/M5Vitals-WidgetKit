import AppKit

// 这是一个「宿主 App」：本身没有任何界面，只负责承载 WidgetKit 扩展。
// 装它之后，系统「编辑小组件」库里才会出现 M5Vitals。
final class HostAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 无窗口、无菜单栏图标 —— 小组件的渲染完全由 chronod 负责
    }
}

@main
struct M5VitalsHostApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = HostAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
