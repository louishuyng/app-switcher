//
//  ContentView.swift
//  AppSwitcher
//
//  Created by lui0x584s on 28/4/25.
//

import SwiftUI
import AppKit
import ApplicationServices
import UniformTypeIdentifiers
import Carbon

struct AppInfo: Identifiable {
    let id = UUID()
    let name: String
    let icon: NSImage
    let bundleIdentifier: String
    var lastUsed: Date?
    var isRunning: Bool = false
    var activationCount: Int = 0
}

// Struct to represent app usage data
struct AppUsageData: Codable {
    let date: Date
    let count: Int
}

// Global app usage tracker
class AppUsageTracker {
    static let shared = AppUsageTracker()
    private var appUsage: [String: AppUsageData] = [:]
    private let fileName = "app_usage.json"
    
    private init() {
        // Load saved data
        if let data = loadData() {
            appUsage = data
        }
        
        // Observe app activation events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appActivated),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    private func getAppSupportDirectory() -> URL? {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("Failed to get Application Support directory")
            return nil
        }
        
        let bundleID = Bundle.main.bundleIdentifier ?? "com.appswitcher"
        let appDirectory = appSupportURL.appendingPathComponent(bundleID)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: appDirectory.path) {
            do {
                try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            } catch {
                print("Failed to create app support directory: \(error)")
                return nil
            }
        }
        
        return appDirectory
    }
    
    private func getDataFileURL() -> URL? {
        guard let fileURL = getAppSupportDirectory()?.appendingPathComponent(fileName) else {
            print("Failed to get data file URL")
            return nil
        }
        return fileURL
    }
    
    private func loadData() -> [String: AppUsageData]? {
        guard let fileURL = getDataFileURL() else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([String: AppUsageData].self, from: data)
        } catch {
            print("Failed to load app usage data: \(error)")
            // Return empty dictionary instead of nil to prevent crashes
            return [:]
        }
    }
    
    private func saveData() {
        guard let fileURL = getDataFileURL() else { return }
        
        do {
            let data = try JSONEncoder().encode(appUsage)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Failed to save app usage data: \(error)")
        }
    }
    
    @objc private func appActivated(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let bundleId = app.bundleIdentifier {
            updateUsage(for: bundleId)
        }
    }
    
    func updateUsage(for bundleId: String) {
        let now = Date()
        if let existing = appUsage[bundleId] {
            appUsage[bundleId] = AppUsageData(date: now, count: existing.count + 1)
        } else {
            appUsage[bundleId] = AppUsageData(date: now, count: 1)
        }
        saveData()
    }
    
    func getUsage(for bundleId: String) -> (date: Date?, count: Int) {
        if let usage = appUsage[bundleId] {
            return (usage.date, usage.count)
        }
        return (nil, 0)
    }
}

// Add app cache
class AppCache {
    static let shared = AppCache()
    private var cachedApps: [AppInfo]?
    private var lastUpdateTime: Date?
    private let updateInterval: TimeInterval = 60 // Update cache every minute
    
    func getApps() -> [AppInfo] {
        let now = Date()
        if let cached = cachedApps,
           let lastUpdate = lastUpdateTime,
           now.timeIntervalSince(lastUpdate) < updateInterval {
            return cached
        }
        
        let newApps = getInstalledApps()
        cachedApps = newApps
        lastUpdateTime = now
        return newApps
    }
    
    func invalidateCache() {
        cachedApps = nil
        lastUpdateTime = nil
    }
}

func getInstalledApps() -> [AppInfo] {
    let appsURL = URL(fileURLWithPath: "/Applications")
    let fileManager = FileManager.default
    guard let contents = try? fileManager.contentsOfDirectory(at: appsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
        return []
    }
    
    var apps: [AppInfo] = []
    let currentAppBundleId = Bundle.main.bundleIdentifier ?? ""
    let runningApps = NSWorkspace.shared.runningApplications
    
    for url in contents where url.pathExtension == "app" {
        let bundle = Bundle(url: url)
        let bundleId = bundle?.bundleIdentifier ?? ""
        
        // Skip AppSwitcher itself
        if bundleId == currentAppBundleId {
            continue
        }
        
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                   bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                   url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 28, height: 28)
        
        // Check if the app is currently running
        let isRunning = runningApps.contains { $0.bundleIdentifier == bundleId }
        
        // Get usage data from tracker
        let usage = AppUsageTracker.shared.getUsage(for: bundleId)
        
        apps.append(AppInfo(
            name: name,
            icon: icon,
            bundleIdentifier: bundleId,
            lastUsed: usage.date,
            isRunning: isRunning,
            activationCount: usage.count
        ))
    }
    
    // Sort by last used date, then running status, then activation count, then alphabetically
    return apps.sorted { (app1, app2) -> Bool in
        // First, sort by last used date (most recent first)
        if let date1 = app1.lastUsed, let date2 = app2.lastUsed {
            return date1 > date2
        } else if app1.lastUsed != nil {
            return true
        } else if app2.lastUsed != nil {
            return false
        }
        
        // Then by running status
        if app1.isRunning && !app2.isRunning {
            return true
        } else if !app1.isRunning && app2.isRunning {
            return false
        }
        
        // Then by activation count
        if app1.activationCount != app2.activationCount {
            return app1.activationCount > app2.activationCount
        }
        
        // Finally alphabetically
        return app1.name.localizedCaseInsensitiveCompare(app2.name) == .orderedAscending
    }
}

// MARK: - Hotkey Model
struct Hotkey: Codable, Equatable {
    var key: String // e.g. "space"
    var modifiers: [String] // e.g. ["control", "option"]
    static let `default` = Hotkey(key: "space", modifiers: ["control", "option"])
    var displayString: String {
        let mod = modifiers.map { $0.capitalized }.joined(separator: "+")
        return mod.isEmpty ? key.capitalized : mod + "+" + key.capitalized
    }
}

// MARK: - SearchModel
class SearchModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchFieldFocused: Bool = false
    
    init() {
        // Add observer for clear search notification
        NotificationCenter.default.addObserver(self, selector: #selector(clearSearch), name: .clearSearch, object: nil)
    }
    
    @objc private func clearSearch() {
        searchText = ""
    }
}

// MARK: - AppNavigationManager
class AppNavigationManager: ObservableObject {
    @Published var selectedAppId: UUID? = nil
    private var apps: [AppInfo] = []
    private var lastSelectedIndex: Int? = nil
    
    func setApps(_ newApps: [AppInfo]) {
        apps = newApps
        // Always select first item when setting new apps
        if !apps.isEmpty {
            selectIndex(0)
        } else {
            selectedAppId = nil
            lastSelectedIndex = nil
        }
    }
    
    func selectApp(_ app: AppInfo) {
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            selectIndex(index)
        }
    }
    
    func moveUp() {
        guard !apps.isEmpty else { return }
        
        if let currentIndex = lastSelectedIndex {
            let prevIndex = max(currentIndex - 1, 0)
            selectIndex(prevIndex)
        } else {
            selectIndex(apps.count - 1)
        }
    }
    
    func moveDown() {
        guard !apps.isEmpty else { return }
        
        if let currentIndex = lastSelectedIndex {
            let nextIndex = min(currentIndex + 1, apps.count - 1)
            selectIndex(nextIndex)
        } else {
            selectIndex(0)
        }
    }
    
    private func selectIndex(_ index: Int) {
        guard index >= 0 && index < apps.count else { return }
        selectedAppId = apps[index].id
        lastSelectedIndex = index
    }
    
    func getSelectedApp() -> AppInfo? {
        return apps.first { $0.id == selectedAppId }
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // S  ingle instance behavior is now handled by AppSwitcherAppDelegate
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup is handled by AppSwitcherAppDelegate
    }
}

// MARK: - ContentView
struct ContentView: View {
    @State private var selectedImage: NSImage? = UserDefaults.standard.data(forKey: "leftImage").flatMap { NSImage(data: $0) } ?? NSImage(named: "NSPhoto")
    @State private var isSelectedImageGIF: Bool = false
    @State private var showingImagePicker = false
    @State private var apps: [AppInfo] = []
    @State private var showingSettings = false
    @State private var hotkey: Hotkey = {
        if let data = UserDefaults.standard.data(forKey: "hotkey"), let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            return hk
        } else {
            return .default
        }
    }()
    @StateObject private var searchModel = SearchModel()
    @StateObject private var navigationManager = AppNavigationManager()
    @State private var isScrolling = false
    @State private var outsideClickMonitor: Any? = nil
    @State private var keyDownMonitor: Any? = nil
    @State private var isImagePickerActive = false
    @State private var isWindowVisible = false
    @State private var scrollProxy: ScrollViewProxy? = nil
    
    var filteredApps: [AppInfo] {
        if searchModel.searchText.isEmpty { return apps }
        // Use more efficient search
        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchModel.searchText)
        }
    }
    
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Left: Image
                ZStack {
                    if let image = selectedImage {
                        if isSelectedImageGIF {
                            AnimatedImageView(image: image)
                                .frame(width: 300, height: 408)
                                .clipped()
                        } else {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 300, height: 408)
                                .clipped()
                        }
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 300, height: 408)
                            .overlay(Text("No Image").foregroundColor(.secondary))
                    }
                }
                .frame(width: 300, height: 408)
                .clipped()
                
                // Right: App List
                ZStack {
                    Color(red: 0.13, green: 0.15, blue: 0.20)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            SearchInput(
                                text: $searchModel.searchText,
                                isFocused: $searchModel.searchFieldFocused,
                                onCommand: { showingSettings = true },
                                onEscape: closeSwitcher,
                                onUpArrow: { navigationManager.moveUp() },
                                onDownArrow: { navigationManager.moveDown() },
                                onReturn: {
                                    if let app = navigationManager.getSelectedApp() {
                                        openApp(app)
                                    }
                                }
                            )
                            .frame(height: 48)
                            .padding(.leading, 16)
                        }
                        appList
                    }
                }
                .frame(width: 340, height: 408)
            }
            .frame(width: 640, height: 408)
        }
        .frame(width: 640, height: 408)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            // Use cached apps
            apps = AppCache.shared.getApps()
            loadSelectedImage()
            checkIfSelectedImageIsGIF()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchModel.searchFieldFocused = true
                navigationManager.setApps(filteredApps)
            }
            
            // Register for image change notification
            NotificationCenter.default.addObserver(forName: .imageChanged, object: nil, queue: .main) { _ in
                if let data = UserDefaults.standard.data(forKey: "leftImage") {
                    let newImage = NSImage(data: data)
                    if newImage != nil {
                        self.selectedImage = newImage
                        checkIfSelectedImageIsGIF()
                    }
                }
            }
            
            // Register for key event notifications
            NotificationCenter.default.addObserver(forName: .moveUp, object: nil, queue: .main) { _ in
                navigationManager.moveUp()
            }
            
            NotificationCenter.default.addObserver(forName: .moveDown, object: nil, queue: .main) { _ in
                navigationManager.moveDown()
            }
            
            NotificationCenter.default.addObserver(forName: .openSelectedApp, object: nil, queue: .main) { _ in
                if let app = navigationManager.getSelectedApp() {
                    openApp(app)
                }
            }
            
            // Add global monitor for mouse down events
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                if let window = NSApplication.shared.windows.first(where: { $0.styleMask.contains(.borderless) }) {
                    let mouseLocation = NSEvent.mouseLocation
                    let windowFrame = window.frame
                    
                    // Close if clicking outside the window and neither settings nor image picker is active
                    if !windowFrame.contains(mouseLocation) && !isImagePickerActive && !showingSettings {
                        closeSwitcher()
                    }
                }
            }
        }
        .onChange(of: searchModel.searchText) { _, _ in
            navigationManager.setApps(filteredApps)
        }
        .onChange(of: selectedImage) { _, _ in
            checkIfSelectedImageIsGIF()
        }
        .onChange(of: isWindowVisible) { _, newValue in
            if newValue {
                // Window became visible, reset state
                resetState()
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage, isPresented: $showingImagePicker)
                .onAppear {
                    isImagePickerActive = true
                }
                .onDisappear {
                    isImagePickerActive = false
                }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(selectedImage: $selectedImage, hotkey: $hotkey)
        }
        .onExitCommand(perform: closeSwitcher)
        .onDisappear {
            if let monitor = outsideClickMonitor {
                NSEvent.removeMonitor(monitor)
                outsideClickMonitor = nil
            }
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
                keyDownMonitor = nil
            }
        }
    }
    
    private var appList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredApps) { app in
                        AppRow(app: app, isSelected: navigationManager.selectedAppId == app.id) {
                            openApp(app)
                        }
                        .id(app.id)
                        // Add view recycling
                        .onAppear {
                            // Preload next few items
                            if let index = filteredApps.firstIndex(where: { $0.id == app.id }),
                               index < filteredApps.count - 5 {
                                let nextApps = filteredApps[index+1...min(index+5, filteredApps.count-1)]
                                for nextApp in nextApps {
                                    _ = nextApp.icon // Preload icons
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: navigationManager.selectedAppId) { _, newValue in
                if let id = newValue {
                    withAnimation(.none) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onAppear {
                scrollProxy = proxy
            }
        }
    }
    
    func openApp(_ app: AppInfo) {
        let workspace = NSWorkspace.shared
        // Update usage data before opening the app
        AppUsageTracker.shared.updateUsage(for: app.bundleIdentifier)
        
        // Use bundle identifier directly instead of searching through /Applications
        if let url = workspace.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            workspace.open(url)
            // Invalidate cache and refresh the list
            AppCache.shared.invalidateCache()
            refreshApps()
            closeSwitcher()
        }
    }
    
    private func refreshApps() {
        // Get fresh apps from cache
        apps = AppCache.shared.getApps()
        
        // Sort apps by last used date, then running status, then activation count
        apps.sort { (app1, app2) -> Bool in
            // First, sort by last used date (most recent first)
            if let date1 = app1.lastUsed, let date2 = app2.lastUsed {
                return date1 > date2
            } else if app1.lastUsed != nil {
                return true
            } else if app2.lastUsed != nil {
                return false
            }
            
            // Then by running status
            if app1.isRunning && !app2.isRunning {
                return true
            } else if !app1.isRunning && app2.isRunning {
                return false
            }
            
            // Then by activation count
            if app1.activationCount != app2.activationCount {
                return app1.activationCount > app2.activationCount
            }
            
            // Finally alphabetically
            return app1.name.localizedCaseInsensitiveCompare(app2.name) == .orderedAscending
        }
        
        // Update navigation manager with new apps
        navigationManager.setApps(apps)
        
        // Reset selection state
        navigationManager.selectedAppId = nil
        
        // Select first app if available
        if let firstApp = apps.first {
            navigationManager.selectApp(firstApp)
            // Scroll to top
            withAnimation(.none) {
                scrollProxy?.scrollTo(firstApp.id, anchor: .top)
            }
        }
    }
    
    func closeSwitcher() {
        // Use userInteractive QoS for UI updates
        DispatchQueue.main.async(qos: .userInteractive) {
            NSApplication.shared.windows.forEach { window in
                if window.styleMask.contains(.borderless) {
                    if window.isVisible {
                        window.orderOut(nil)
                    }
                    HotkeyManager.shared.setSwitcherVisible(false)
                    self.isWindowVisible = false
                    // Clear the search input when hiding
                    NotificationCenter.default.post(name: .clearSearch, object: nil)
                }
            }
            NSApp.hide(nil)
        }
    }
    
    private func checkIfSelectedImageIsGIF() {
        guard let image = selectedImage else {
            isSelectedImageGIF = false
            return
        }
        
        // Check if the image has multiple representations (like a GIF)
        if image.representations.count > 1 {
            isSelectedImageGIF = true
            return
        }
        
        // Check if the image data is a GIF
        if let data = UserDefaults.standard.data(forKey: "leftImage"),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let type = CGImageSourceGetType(source) as String?,
           type == UTType.gif.identifier {
            isSelectedImageGIF = true
            return
        }
        
        isSelectedImageGIF = false
    }
    
    private func loadSelectedImage() {
        if let data = UserDefaults.standard.data(forKey: "leftImage") {
            // Use cached image if available
            if let cachedImage = ImageCache.shared.getImage(for: "leftImage") {
                self.selectedImage = cachedImage
            } else if let newImage = NSImage(data: data) {
                self.selectedImage = newImage
                // Cache the image
                ImageCache.shared.getImage(for: "leftImage")
            }
            checkIfSelectedImageIsGIF()
        }
    }
    
    func resetState() {
        // Invalidate cache and get fresh apps
        AppCache.shared.invalidateCache()
        apps = AppCache.shared.getApps()
        // Reset navigation to first app
        navigationManager.setApps(apps)
        // Clear search
        searchModel.searchText = ""
        // Scroll to top
        if let firstApp = apps.first {
            withAnimation(.none) {
                scrollProxy?.scrollTo(firstApp.id, anchor: .top)
            }
        }
    }
    
    // Add public method to handle state updates
    func updateState() {
        // Invalidate cache and get fresh apps
        AppCache.shared.invalidateCache()
        apps = AppCache.shared.getApps()
        
        // Sort apps by last used date, then running status, then activation count
        apps.sort { (app1, app2) -> Bool in
            // First, sort by last used date (most recent first)
            if let date1 = app1.lastUsed, let date2 = app2.lastUsed {
                return date1 > date2
            } else if app1.lastUsed != nil {
                return true
            } else if app2.lastUsed != nil {
                return false
            }
            
            // Then by running status
            if app1.isRunning && !app2.isRunning {
                return true
            } else if !app1.isRunning && app2.isRunning {
                return false
            }
            
            // Then by activation count
            if app1.activationCount != app2.activationCount {
                return app1.activationCount > app2.activationCount
            }
            
            // Finally alphabetically
            return app1.name.localizedCaseInsensitiveCompare(app2.name) == .orderedAscending
        }
        
        // Reset navigation to first app
        navigationManager.setApps(apps)
        // Clear search
        searchModel.searchText = ""
        // Reset selection to first app
        if let firstApp = apps.first {
            navigationManager.selectApp(firstApp)
            // Scroll to top
            withAnimation(.none) {
                scrollProxy?.scrollTo(firstApp.id, anchor: .top)
            }
        } else {
            navigationManager.selectedAppId = nil
        }
    }
}

// MARK: - KeyEventHandlingView
struct KeyEventHandlingView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    @State private var isSettingsVisible = false
    @State private var isImagePickerActive = false
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlingView()
        view.onKeyDown = onKeyDown
        view.isSettingsVisible = isSettingsVisible
        view.isImagePickerActive = isImagePickerActive
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyHandlingView {
            view.onKeyDown = onKeyDown
            view.isSettingsVisible = isSettingsVisible
            view.isImagePickerActive = isImagePickerActive
        }
    }
    
    class KeyHandlingView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?
        var isSettingsVisible: Bool = false
        var isImagePickerActive: Bool = false
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            // If settings or image picker is active, don't handle the key event
            if isSettingsVisible || isImagePickerActive {
                super.keyDown(with: event)
                return
            }
            
            // 1. First check for hotkey combination
            let currentHotkey = HotkeyManager.shared.getCurrentHotkey()
            let expectedModifiers = HotkeyManager.shared.expectedModifierFlags(for: currentHotkey ?? .default)
            let modifiersMatch = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == expectedModifiers
            let keyMatch = event.keyCode == HotkeyManager.shared.keyCode(for: currentHotkey?.key ?? "space")
            
            if modifiersMatch && keyMatch {
                // Hotkey detected - toggle app visibility
                if let window = NSApplication.shared.windows.first(where: { $0.styleMask.contains(.borderless) }) {
                    if window.isVisible {
                        window.orderOut(nil)
                        HotkeyManager.shared.setSwitcherVisible(false)
                        NotificationCenter.default.post(name: .clearSearch, object: nil)
                    } else {
                        window.makeKeyAndOrderFront(nil)
                        HotkeyManager.shared.setSwitcherVisible(true)
                        NotificationCenter.default.post(name: .clearSearch, object: nil)
                    }
                }
                return
            }
            
            // 2. Only handle other keys if the app is visible
            if let window = NSApplication.shared.windows.first(where: { $0.styleMask.contains(.borderless) }),
               window.isVisible {
                switch Int(event.keyCode) {
                case kVK_DownArrow:
                    // Move to next app in list
                    NotificationCenter.default.post(name: .moveDown, object: nil)
                    return
                case kVK_UpArrow:
                    // Move to previous app in list
                    NotificationCenter.default.post(name: .moveUp, object: nil)
                    return
                case kVK_Return:
                    // Open selected app
                    NotificationCenter.default.post(name: .openSelectedApp, object: nil)
                    return
                default:
                    // For all other keys, close the app
                    window.orderOut(nil)
                    HotkeyManager.shared.setSwitcherVisible(false)
                    NotificationCenter.default.post(name: .clearSearch, object: nil)
                }
            }
        }
        
        override func becomeFirstResponder() -> Bool {
            return true
        }
        
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            return true
        }
    }
}

// Add new notification names for key events
extension Notification.Name {
    static let moveUp = Notification.Name("moveUp")
    static let moveDown = Notification.Name("moveDown")
    static let openSelectedApp = Notification.Name("openSelectedApp")
}

// MARK: - FocusableTextField
struct FocusableTextField: NSViewRepresentable {
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        init(_ parent: FocusableTextField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle Esc key
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape?()
                return true
            }
            // Detect Cmd + ,
            if let event = NSApp.currentEvent,
               event.modifierFlags.contains(.command),
               event.characters == "," {
                parent.onCommand?()
                return true
            }
            // Handle arrow keys
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onUpArrow?()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onDownArrow?()
                return true
            }
            // Handle return key
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onReturn?()
                return true
            }
            return false
        }
    }
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    var onCommand: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    var onUpArrow: (() -> Void)? = nil
    var onDownArrow: (() -> Void)? = nil
    var onReturn: (() -> Void)? = nil
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.font = NSFont.systemFont(ofSize: 24, weight: .medium)
        textField.focusRingType = .none
        textField.textColor = NSColor(named: "TextColor")
        return textField
    }
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if isFirstResponder, nsView.window?.firstResponder != nsView {
            nsView.becomeFirstResponder()
            // Place cursor at the end
            if let editor = nsView.currentEditor() {
                let length = nsView.stringValue.count
                editor.selectedRange = NSRange(location: length, length: 0)
            }
        }
        nsView.textColor = NSColor(named: "TextColor")
    }
}

// Search input with no border, no radius, and a prefix icon, using FocusableTextField
struct SearchInput: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    var onCommand: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    var onUpArrow: (() -> Void)? = nil
    var onDownArrow: (() -> Void)? = nil
    var onReturn: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(Color(nsColor: NSColor(named: "TextColor")!))
            FocusableTextField(
                text: $text,
                isFirstResponder: $isFocused,
                onCommand: onCommand,
                onEscape: onEscape,
                onUpArrow: onUpArrow,
                onDownArrow: onDownArrow,
                onReturn: onReturn
            )
            .frame(height: 32)
            .foregroundColor(Color(nsColor: NSColor(named: "TextColor")!))
        }
        .padding(.horizontal, 0)
        .background(Color.clear)
    }
}

// MARK: - AppRow
struct AppRow: View {
    let app: AppInfo
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(nsImage: app.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
                
                Text(app.name)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundColor(Color(nsColor: NSColor(named: "TextColor")!))
                
                Spacer()
                
                if app.isRunning {
                    Circle()
                        .fill(Color(hex: "#92B580"))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color(hex: "#181818") : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Helper to use hex color
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - SettingsView
struct SettingsView: View {
    @Binding var selectedImage: NSImage?
    @Binding var hotkey: Hotkey
    @State private var showingImagePicker = false
    @State private var listeningForHotkey = false
    @State private var hotkeyConflict: String? = nil
    @State private var pendingHotkey: Hotkey? = nil
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var timer: Timer? = nil
    @State private var showingPermissionAlert = false
    @State private var previousAccessibilityState = AXIsProcessTrusted()
    @Environment(\.dismiss) private var dismiss
    
    private func quitAndReopen() {
        // Close all windows
        NSApplication.shared.windows.forEach { $0.close() }
        
        // Get app path and schedule relaunch
        let appPath = Bundle.main.bundlePath
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSWorkspace.shared.launchApplication(appPath)
        }
        
        // Force quit the current instance
        NSApplication.shared.terminate(nil)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.title)
                    .bold()
                Divider()
                HStack {
                    Text("Left Image:")
                    Spacer()
                    if let image = selectedImage {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .cornerRadius(8)
                    }
                    Button("Change") { showingImagePicker = true }
                }
                HStack {
                    Text("Hotkey:")
                    Spacer()
                    Text((pendingHotkey ?? hotkey).displayString)
                    Button(listeningForHotkey ? "Press new hotkey..." : "Set Hotkey") {
                        listeningForHotkey = true
                        hotkeyConflict = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Reset") {
                        hotkey = .default
                        if let data = try? JSONEncoder().encode(hotkey) {
                            UserDefaults.standard.set(data, forKey: "hotkey")
                        }
                        pendingHotkey = nil
                    }
                }
                if let conflict = hotkeyConflict {
                    Text(conflict)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
                if let pending = pendingHotkey, pending != hotkey, hotkeyConflict == nil {
                    HStack {
                        Text("Confirm new hotkey?")
                        Spacer()
                        Button("Confirm") {
                            hotkey = pending
                            if let data = try? JSONEncoder().encode(hotkey) {
                                UserDefaults.standard.set(data, forKey: "hotkey")
                            }
                            // Update HotkeyManager immediately
                            HotkeyManager.shared.setHotkey(hotkey) {
                                if let window = NSApplication.shared.windows.first(where: { $0.styleMask.contains(.borderless) }) {
                                    window.orderOut(nil)
                                }
                            }
                            // Post notification to reload hotkey in AppDelegate
                            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                            pendingHotkey = nil
                        }
                    }
                }
                Text("To set a new hotkey, click 'Set Hotkey' and press your desired combination. Avoid system-reserved shortcuts.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                Divider()
                HStack {
                    Text("Accessibility Permission:")
                    Spacer()
                    if accessibilityGranted {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Granted").foregroundColor(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        Text("Not Granted").foregroundColor(.red)
                    }
                    Button("Open Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                }
                .padding(.top, 8)
                .alert("Permission Required", isPresented: $showingPermissionAlert) {
                    Button("Quit & Reopen") {
                        quitAndReopen()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("To take effect, please quit and reopen the app.")
                }
                if !accessibilityGranted {
                    Button("Reveal in Finder") {
                        if let path = Bundle.main.bundlePath as String? {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    }
                    .padding(.bottom, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How to grant Accessibility permission:")
                            .font(.subheadline).bold()
                        Text("1. Click 'Open Settings' to open the Accessibility pane.")
                        Text("2. Click the '+' button in the list.")
                        Text("3. Click 'Reveal in Finder' to open the running app's location.")
                        Text("4. Drag the app from Finder into the Accessibility list.")
                        Text("5. Check the box to grant permission.")
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                }
                Spacer()
            }
            .padding(32)
            .frame(minWidth: 700, minHeight: 500)
        }
        .onAppear {
            HotkeyManager.shared.setSettingsVisible(true)
            accessibilityGranted = AXIsProcessTrusted()
            previousAccessibilityState = accessibilityGranted
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                let granted = AXIsProcessTrusted()
                if granted != accessibilityGranted {
                    accessibilityGranted = granted
                    // Only show alert if permissions were just granted (changed from false to true)
                    if granted && !previousAccessibilityState {
                        showingPermissionAlert = true
                    }
                    previousAccessibilityState = granted
                }
            }
        }
        .onDisappear {
            HotkeyManager.shared.setSettingsVisible(false)
            timer?.invalidate()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage, isPresented: $showingImagePicker)
                .onDisappear {
                    if let image = selectedImage {
                        // Save the image data based on its type
                        if let data = UserDefaults.standard.data(forKey: "leftImage"),
                           let source = CGImageSourceCreateWithData(data as CFData, nil),
                           let type = CGImageSourceGetType(source) as String?,
                           type == UTType.gif.identifier {
                            // If it's a GIF, we already have the correct data saved
                            NotificationCenter.default.post(name: .imageChanged, object: nil)
                        } else {
                            // For other image types, save as TIFF
                            if let tiffData = image.tiffRepresentation {
                                UserDefaults.standard.set(tiffData, forKey: "leftImage")
                                NotificationCenter.default.post(name: .imageChanged, object: nil)
                            }
                        }
                    }
                }
        }
        .background(HotkeyPickerOverlay(listening: $listeningForHotkey, hotkey: $hotkey, hotkeyConflict: $hotkeyConflict, pendingHotkey: $pendingHotkey))
    }
}

// MARK: - HotkeyPickerOverlay
struct HotkeyPickerOverlay: NSViewRepresentable {
    @Binding var listening: Bool
    @Binding var hotkey: Hotkey
    @Binding var hotkeyConflict: String?
    @Binding var pendingHotkey: Hotkey?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.parent = self
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        if listening {
            context.coordinator.startListening()
        } else {
            context.coordinator.stopListening()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject {
        var parent: HotkeyPickerOverlay
        var monitor: Any?
        
        init(parent: HotkeyPickerOverlay) {
            self.parent = parent
        }
        
        func startListening() {
            stopListening()
            
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                
                // Ignore keys without modifiers
                let hasModifiers = event.modifierFlags.contains(.command) ||
                                   event.modifierFlags.contains(.control) ||
                                   event.modifierFlags.contains(.option) ||
                                   event.modifierFlags.contains(.shift)
                
                if !hasModifiers {
                    // Require at least one modifier key
                    return event
                }
                
                // Get the key string and modifiers
                let key = self.keyString(for: event)
                let mods = self.modifierStrings(for: event)
                
                // Create new hotkey
                let newHotkey = Hotkey(key: key, modifiers: mods)
                
                // Check for conflicts
                if let conflict = self.checkConflict(hotkey: newHotkey) {
                    DispatchQueue.main.async {
                        self.parent.hotkeyConflict = conflict
                        self.parent.listening = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.parent.pendingHotkey = newHotkey
                        self.parent.hotkeyConflict = nil
                        self.parent.listening = false
                    }
                }
                
                return nil
            }
        }
        
        func stopListening() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
        
        func keyString(for event: NSEvent) -> String {
            switch event.keyCode {
            case 49: return "space"
            case 36: return "return"
            case 51: return "delete"
            case 53: return "escape"
            case 43: return ","
            case 126: return "up"
            case 125: return "down"
            case 123: return "left"
            case 124: return "right"
            case 48: return "tab"
            case 117: return "delete"
            case 122: return "f1"
            case 120: return "f2"
            case 99: return "f3"
            case 118: return "f4"
            case 96: return "f5"
            case 97: return "f6"
            case 98: return "f7"
            case 100: return "f8"
            case 101: return "f9"
            case 109: return "f10"
            case 103: return "f11"
            case 111: return "f12"
            default:
                if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                    return chars.lowercased()
                }
                return "unknown"
            }
        }
        
        func modifierStrings(for event: NSEvent) -> [String] {
            var mods: [String] = []
            if event.modifierFlags.contains(.control) { mods.append("control") }
            if event.modifierFlags.contains(.command) { mods.append("command") }
            if event.modifierFlags.contains(.option) { mods.append("option") }
            if event.modifierFlags.contains(.shift) { mods.append("shift") }
            return mods
        }
        
        func checkConflict(hotkey: Hotkey) -> String? {
            // TODO: Check for conflicts with system shortcuts
            return nil
        }
    }
}

// MARK: - HotkeyManager
class HotkeyManager {
    static let shared = HotkeyManager()
    private var monitor: Any?
    private var callback: (() -> Void)?
    private var currentHotkey: Hotkey?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isSwitcherVisible: Bool = false
    private var isSettingsVisible: Bool = false
    private var window: NSWindow? {
        return NSApplication.shared.windows.first(where: { $0.styleMask.contains(.borderless) })
    }
    
    func getCurrentHotkey() -> Hotkey? {
        return currentHotkey
    }
    
    func setHotkey(_ hotkey: Hotkey, action: @escaping () -> Void) {
        // Remove existing monitor if any
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        
        // Remove existing event tap if any
        if let eventTap = eventTap {
            CFRunLoopSourceInvalidate(runLoopSource)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
            self.runLoopSource = nil
        }
        
        // Store the current hotkey and callback
        currentHotkey = hotkey
        callback = action
        
        // Create a new global monitor for the hotkey with highest priority
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] event in
            self?.handleKeyEvent(event)
        })
        
        // Set up event tap for more reliable global hotkey detection
        setupEventTap()
        
        // Ensure the event tap is enabled
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let currentHotkey = self.currentHotkey else { return false }
        
        // Check for specific modifier keys
        let hasCommand = event.modifierFlags.contains(.command)
        let hasControl = event.modifierFlags.contains(.control)
        let hasOption = event.modifierFlags.contains(.option)
        let hasShift = event.modifierFlags.contains(.shift)
        
        // Check if modifiers match the hotkey
        var modifiersMatch = true
        for modifier in currentHotkey.modifiers {
            switch modifier.lowercased() {
            case "command":
                if !hasCommand { modifiersMatch = false }
            case "control":
                if !hasControl { modifiersMatch = false }
            case "option":
                if !hasOption { modifiersMatch = false }
            case "shift":
                if !hasShift { modifiersMatch = false }
            default:
                break
            }
        }
        
        // For key down events, also check the key code
        if event.type == .keyDown {
            let keyMatch = event.keyCode == self.keyCode(for: currentHotkey.key)
            if modifiersMatch && keyMatch {
                // Use userInteractive QoS for UI updates
                DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                    guard let self = self else { return }
                    
                    // If settings is visible, only allow hiding the app
                    if self.isSettingsVisible {
                        if self.isSwitcherVisible {
                            self.hideSwitcher()
                            NSApp.hide(nil)
                        }
                        return
                    }
                    
                    // Toggle the switcher state
                    if self.isSwitcherVisible {
                        self.hideSwitcher()
                        NSApp.hide(nil)
                    } else {
                        self.showSwitcher()
                    }
                }
                return true
            }
        }
        return false
    }
    
    private func showSwitcher() {
        guard let window = self.window else { return }
        isSwitcherVisible = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Reset state and update app list
        if let contentView = window.contentView as? NSHostingView<ContentView> {
            contentView.rootView.updateState()
        }
        
        callback?()
        NotificationCenter.default.post(name: .clearSearch, object: nil)
    }
    
    private func hideSwitcher() {
        guard let window = self.window else { return }
        isSwitcherVisible = false
        
        // Only order out if the window is actually visible
        if window.isVisible {
            window.orderOut(nil)
        }
        
        // Ensure we're not trying to make any window key
        NSApp.hide(nil)
        NotificationCenter.default.post(name: .clearSearch, object: nil)
    }
    
    func setSwitcherVisible(_ visible: Bool) {
        if visible {
            showSwitcher()
        } else {
            hideSwitcher()
        }
    }
    
    func setSettingsVisible(_ visible: Bool) {
        isSettingsVisible = visible
    }
    
    private func setupEventTap() {
        // Create event tap
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let hotkeyManager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                if let nsEvent = NSEvent(cgEvent: event) {
                    let eventHandled = hotkeyManager.handleKeyEvent(nsEvent)
                    if eventHandled {
                        // If handleKeyEvent returns true, consume the event
                        return nil
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        if let eventTap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        }
    }
    
    func expectedModifierFlags(for hotkey: Hotkey) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        
        for modifier in hotkey.modifiers {
            switch modifier.lowercased() {
            case "control": flags.insert(.control)
            case "command": flags.insert(.command)
            case "option": flags.insert(.option)
            case "shift": flags.insert(.shift)
            default: break
            }
        }
        
        return flags
    }
    
    func keyCode(for key: String) -> UInt16 {
        switch key.lowercased() {
        case "space": return 49
        case ",": return 43
        case "a": return 0
        case "b": return 11
        case "c": return 8
        case "d": return 2
        case "e": return 14
        case "f": return 3
        case "g": return 5
        case "h": return 4
        case "i": return 34
        case "j": return 38
        case "k": return 40
        case "l": return 37
        case "m": return 46
        case "n": return 45
        case "o": return 31
        case "p": return 35
        case "q": return 12
        case "r": return 15
        case "s": return 1
        case "t": return 17
        case "u": return 32
        case "v": return 9
        case "w": return 13
        case "x": return 7
        case "y": return 16
        case "z": return 6
        case "0": return 29
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        case "return": return 36
        case "tab": return 48
        case "delete": return 51
        case "escape": return 53
        case "up": return 126
        case "down": return 125
        case "left": return 123
        case "right": return 124
        default: return 0
        }
    }
}

// VisualEffectBlur for macOS
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Update ImagePicker to better handle GIFs and dismiss sheet
struct ImagePicker: NSViewControllerRepresentable {
    @Binding var image: NSImage?
    @Binding var isPresented: Bool
    
    func makeCoordinator() -> Coordinator { 
        Coordinator(self) 
    }
    
    func makeNSViewController(context: Context) -> NSViewController {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [
            UTType.png,
            UTType.jpeg,
            UTType.bmp,
            UTType.gif,
            UTType.tiff,
            UTType.image
        ]
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        let viewController = NSViewController()
        
        DispatchQueue.main.async {
            if picker.runModal() == .OK, let url = picker.url {
                loadImage(from: url)
            }
            // Dismiss the sheet after picking or cancelling
            isPresented = false
        }
        
        return viewController
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
    
    private func loadImage(from url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        
        // Special handling for GIFs to preserve animation
        if fileExtension == "gif" {
            if let gifData = try? Data(contentsOf: url) {
                // Create NSImage from GIF data
                let gifImage = NSImage(data: gifData)
                
                // Ensure the image has the correct size
                if let gifImage = gifImage {
                    gifImage.size = NSSize(width: 300, height: 408)
                }
                
                self.image = gifImage
                
                // Save the raw GIF data to preserve animation
                UserDefaults.standard.set(gifData, forKey: "leftImage")
                NotificationCenter.default.post(name: .imageChanged, object: nil)
            }
        } else {
            // For other image types
            if let nsImage = NSImage(contentsOf: url) {
                // Set the correct size
                nsImage.size = NSSize(width: 300, height: 408)
                self.image = nsImage
                
                // Save as TIFF representation for standard images
                if let tiffData = nsImage.tiffRepresentation {
                    UserDefaults.standard.set(tiffData, forKey: "leftImage")
                    NotificationCenter.default.post(name: .imageChanged, object: nil)
                }
            }
        }
    }
    
    class Coordinator: NSObject {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
    }
}

// Notification for hotkey change
extension Notification.Name {
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
    static let imageChanged = Notification.Name("imageChanged")
    static let clearSearch = Notification.Name("clearSearch")
}

#Preview {
    ContentView()
}

// --- KEY DOWN HANDLER ---
extension View {
    func onKeyDown(perform: @escaping (NSEvent) -> Void) -> some View {
        self.background(KeyDownHandlingView(perform: perform))
    }
}

struct KeyDownHandlingView: NSViewRepresentable {
    let perform: (NSEvent) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.perform = perform
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    class KeyCatcherView: NSView {
        var perform: ((NSEvent) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            perform?(event)
        }
    }
}

// Helper for custom corner radius
struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft     = RectCorner(rawValue: 1 << 0)
    static let topRight    = RectCorner(rawValue: 1 << 1)
    static let bottomLeft  = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = 12.0
    var corners: RectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - AnimatedImageView
struct AnimatedImageView: NSViewRepresentable {
    var image: NSImage
    var isAnimating: Bool = true
    
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageFrameStyle = .none
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently
        
        // Enable animation for GIFs
        if isAnimating {
            enableAnimation(for: imageView)
        }
        
        return imageView
    }
    
    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = image
        nsView.imageScaling = .scaleAxesIndependently
        nsView.imageFrameStyle = .none
        nsView.imageAlignment = .alignCenter
        
        if isAnimating {
            enableAnimation(for: nsView)
        } else {
            disableAnimation(for: nsView)
        }
    }
    
    private func enableAnimation(for imageView: NSImageView) {
        // Enable animation on NSImageView
        imageView.animates = true
        
        // If the image has multiple representations (like a GIF), ensure animation is enabled
        if image.representations.count > 1 {
            imageView.animates = true
            imageView.imageScaling = .scaleAxesIndependently
        }
    }
    
    private func disableAnimation(for imageView: NSImageView) {
        // Disable animation on NSImageView
        imageView.animates = false
    }
}

// Add environment values for settings and image picker states
private struct IsSettingsVisibleKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct IsImagePickerActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isSettingsVisible: Bool {
        get { self[IsSettingsVisibleKey.self] }
        set { self[IsSettingsVisibleKey.self] = newValue }
    }
    
    var isImagePickerActive: Bool {
        get { self[IsImagePickerActiveKey.self] }
        set { self[IsImagePickerActiveKey.self] = newValue }
    }
}

// MARK: - NSAppearance Extension
extension NSAppearance {
    public var isDarkMode: Bool {
        if #available(macOS 10.14, *) {
            if self.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }
}

// MARK: - NSView Extension
extension NSView {
    static var darkModeChangeNotification: Notification.Name { 
        return .init(rawValue: "NSAppearance did change") 
    }
}

extension NSAppearance {
    static var isDarkModeKey: String { return "isDarkMode" }
}

// Add image cache
class ImageCache {
    static let shared = ImageCache()
    private var cache: [String: NSImage] = [:]
    
    func getImage(for path: String) -> NSImage? {
        if let cached = cache[path] {
            return cached
        }
        if let image = NSImage(contentsOfFile: path) {
            cache[path] = image
            return image
        }
        return nil
    }
    
    func clear() {
        cache.removeAll()
    }
}
