import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        let contentView = ContentView().environmentObject(appState)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ZvecLegalKnowledge")
        window.title = "Zvec Legal Knowledge"
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func closeWindowAction(_ sender: Any?) {
        window.orderOut(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // === App Menu ===
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "关于 Zvec Legal Knowledge", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "偏好设置...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(prefsItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 Zvec Legal Knowledge", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")

        let hideOthersItem = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 Zvec Legal Knowledge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // === File Menu ===
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu

        let importItem = NSMenuItem(title: "导入文档...", action: #selector(openImport), keyEquivalent: "i")
        importItem.target = self
        fileMenu.addItem(importItem)

        let newKBItem = NSMenuItem(title: "新建知识库...", action: #selector(newKnowledgeBase), keyEquivalent: "n")
        newKBItem.target = self
        fileMenu.addItem(newKBItem)

        fileMenu.addItem(NSMenuItem.separator())
        let closeItem = NSMenuItem(title: "关闭", action: #selector(closeWindowAction(_:)), keyEquivalent: "w")
        closeItem.target = self
        fileMenu.addItem(closeItem)

        // === Edit Menu ===
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // === View Menu ===
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "显示")
        viewMenuItem.submenu = viewMenu

        let zoomInItem = NSMenuItem(title: "放大", action: #selector(zoomIn), keyEquivalent: "+")
        zoomInItem.target = self
        viewMenu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: "缩小", action: #selector(zoomOut), keyEquivalent: "-")
        zoomOutItem.target = self
        viewMenu.addItem(zoomOutItem)

        let actualSizeItem = NSMenuItem(title: "实际大小", action: #selector(actualSize), keyEquivalent: "0")
        actualSizeItem.target = self
        viewMenu.addItem(actualSizeItem)

        viewMenu.addItem(NSMenuItem.separator())

        let fullScreenItem = NSMenuItem(title: "进入全屏幕", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = NSEvent.ModifierFlags([.command, .control])
        viewMenu.addItem(fullScreenItem)

        // === Window Menu ===
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu

        let minimizeItem = NSMenuItem(title: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(minimizeItem)

        let zoomMenuItem = NSMenuItem(title: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(zoomMenuItem)

        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "将窗口移到屏幕最前面", action: #selector(bringWindowToFront), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openPreferences() {
        window.makeKeyAndOrderFront(nil)
        appState.jumpToTab(2)
    }

    @objc private func openImport() {
        window.makeKeyAndOrderFront(nil)
        appState.jumpToTab(0)
        appState.shouldShowFilePicker = true
    }

    @objc private func newKnowledgeBase() {
        window.makeKeyAndOrderFront(nil)
        appState.jumpToTab(0)
    }

    @objc private func bringWindowToFront() {
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func zoomIn() {
        appState.zoomLevel = min(appState.zoomLevel + 0.1, 2.0)
    }

    @objc private func zoomOut() {
        appState.zoomLevel = max(appState.zoomLevel - 0.1, 0.5)
    }

    @objc private func actualSize() {
        appState.zoomLevel = 1.0
    }
}
