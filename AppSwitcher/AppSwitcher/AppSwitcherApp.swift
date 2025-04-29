//
//  AppSwitcherApp.swift
//  AppSwitcher
//
//  Created by lui0x584s on 28/4/25.
//

import SwiftUI

@main
struct AppSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppSwitcherAppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("AppSwitcher", systemImage: "command") {
            Button("Settings...") {
                appDelegate.showSettings()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

class AppSwitcherAppDelegate: NSObject, NSApplicationDelegate {
    var switcherWindowController: SwitcherWindowController?
    var settingsWindowController: NSWindowController?
    private var isRunning = false
    
    var hotkey: Hotkey = {
        if let data = UserDefaults.standard.data(forKey: "hotkey"), let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            return hk
        } else {
            return .default
        }
    }()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if another instance is already running
        if isRunning {
            // If already running, activate the existing instance
            if let window = NSApplication.shared.windows.first(where: { $0.styleMask.contains(.borderless) }) {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            NSApp.terminate(nil)
            return
        }
        
        isRunning = true
        showSwitcher()
        setupHotkey()
        NotificationCenter.default.addObserver(forName: .hotkeyChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reloadHotkey()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        isRunning = false
    }
    
    func showSettings() {
        let settingsView = SettingsRootView(onClose: {
            self.settingsWindowController?.close()
        })
        let hosting = NSHostingController(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.contentViewController = hosting
        settingsWindowController = NSWindowController(window: window)
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func showSwitcher() {
        if switcherWindowController == nil {
            switcherWindowController = SwitcherWindowController()
        }
        // Invalidate the app cache to ensure we get fresh data
        AppCache.shared.invalidateCache()
        switcherWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func setupHotkey() {
        HotkeyManager.shared.setHotkey(hotkey) { [weak self] in
            guard let self = self else { return }
            self.showSwitcher()
        }
    }
    
    func reloadHotkey() {
        if let data = UserDefaults.standard.data(forKey: "hotkey"), let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.hotkey = hk
        } else {
            self.hotkey = .default
        }
        setupHotkey()
    }
}

struct SettingsRootView: View {
    var onClose: () -> Void
    @State private var selectedImage: NSImage? = UserDefaults.standard.data(forKey: "leftImage").flatMap { NSImage(data: $0) } ?? NSImage(named: "NSPhoto")
    @State private var hotkey: Hotkey = {
        if let data = UserDefaults.standard.data(forKey: "hotkey"), let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            return hk
        } else {
            return .default
        }
    }()
    var body: some View {
        VStack {
            SettingsView(selectedImage: $selectedImage, hotkey: $hotkey)
            HStack {
                Spacer()
                Button("Close") { onClose() }
            }
            .padding([.bottom, .trailing])
        }
        .frame(width: 700, height: 500)
    }
}

// MARK: - SwitcherWindowController
import AppKit
import SwiftUI
class SwitcherWindowController: NSWindowController {
    init() {
        let contentView = ContentView()
        let hosting = NSHostingController(rootView: contentView)
        let window = DraggableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 408),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.setFrameCentered(size: NSSize(width: 640, height: 408))
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.masksToBounds = true
        window.contentView?.layer?.cornerRadius = 12
        window.contentViewController = hosting
        window.makeFirstResponder(hosting.view)
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class DraggableWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.isMovableByWindowBackground = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    private var isDragging = false
    private var initialLocation: NSPoint?
    
    override func mouseDown(with event: NSEvent) {
        // Get the location of the click in window coordinates
        let location = event.locationInWindow
        
        // Convert to view coordinates
        if let contentView = self.contentView {
            let viewLocation = contentView.convert(location, from: nil)
            
            // Check if the click is on a text field or other interactive view
            let hitView = contentView.hitTest(viewLocation)
            if hitView is NSTextField || hitView is NSTextView {
                // Let the text field handle the event
                super.mouseDown(with: event)
            } else {
                // Start window dragging
                isDragging = true
                initialLocation = location
                self.performDrag(with: event)
            }
        } else {
            // Fallback to window dragging if no content view
            self.performDrag(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        initialLocation = nil
        super.mouseUp(with: event)
    }
}

extension NSWindow {
    func setFrameCentered(size: NSSize) {
        if let screen = NSScreen.main {
            let rect = NSRect(
                x: (screen.frame.width - size.width) / 2,
                y: (screen.frame.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            setFrame(rect, display: true)
        }
    }
}
