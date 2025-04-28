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
    let description: String?
    var isAnimated: Bool = false
}

func getInstalledApps() -> [AppInfo] {
    let appsURL = URL(fileURLWithPath: "/Applications")
    let fileManager = FileManager.default
    guard let contents = try? fileManager.contentsOfDirectory(at: appsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
        return []
    }
    var apps: [AppInfo] = []
    for url in contents where url.pathExtension == "app" {
        let bundle = Bundle(url: url)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                   bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                   url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 28, height: 28)
        apps.append(AppInfo(name: name, icon: icon, description: nil))
    }
    return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    
    var filteredApps: [AppInfo] {
        if searchModel.searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchModel.searchText) }
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
                
                // Right: App List
                ZStack {
                    Color(red: 0.13, green: 0.15, blue: 0.20, opacity: 0.92)
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
        .background(
            KeyEventHandlingView { event in
                switch Int(event.keyCode) {
                case kVK_UpArrow:
                    navigationManager.moveUp()
                    return true
                case kVK_DownArrow:
                    navigationManager.moveDown()
                    return true
                case kVK_Return:
                    if let app = navigationManager.getSelectedApp() {
                        openApp(app)
                    }
                    return true
                default:
                    return false
                }
            }
        )
        .onAppear {
            apps = getInstalledApps()
            checkIfSelectedImageIsGIF()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchModel.searchFieldFocused = true
                navigationManager.setApps(filteredApps)
            }
            
            // Register for image change notification
            NotificationCenter.default.addObserver(forName: .imageChanged, object: nil, queue: .main) { _ in
                self.selectedImage = UserDefaults.standard.data(forKey: "leftImage").flatMap { NSImage(data: $0) }
                checkIfSelectedImageIsGIF()
            }
        }
        .onChange(of: searchModel.searchText) { _, _ in
            navigationManager.setApps(filteredApps)
        }
        .onChange(of: selectedImage) { _, _ in
            checkIfSelectedImageIsGIF()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(selectedImage: $selectedImage, hotkey: $hotkey)
        }
        .onExitCommand(perform: closeSwitcher)
    }
    
    private var appList: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredApps) { app in
                        AppRow(app: app, isSelected: navigationManager.selectedAppId == app.id)
                            .id(app.id)
                    }
                }
            }
            .onChange(of: navigationManager.selectedAppId) { _, newValue in
                if let id = newValue {
                    withAnimation(.none) { scrollProxy.scrollTo(id, anchor: .center) }
                }
            }
            .allowsHitTesting(false)
        }
    }
    
    func openApp(_ app: AppInfo) {
        let workspace = NSWorkspace.shared
        let appsURL = URL(fileURLWithPath: "/Applications")
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: appsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return }
        for url in contents where url.pathExtension == "app" {
            let bundle = Bundle(url: url)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                       bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                       url.deletingPathExtension().lastPathComponent
            if name == app.name {
                workspace.open(url)
                closeSwitcher()
                break
            }
        }
    }
    
    func closeSwitcher() {
        NSApplication.shared.windows.forEach { window in
            if window.styleMask.contains(.borderless) {
                window.orderOut(nil)
            }
        }
    }
    
    private func checkIfSelectedImageIsGIF() {
        if let image = selectedImage {
            // Multiple representations typically indicates an animated image
            if image.representations.count > 1 {
                isSelectedImageGIF = true
                return
            }
            
            // Check if image has CGImage (static images usually do)
            if image.cgImage(forProposedRect: nil, context: nil, hints: nil) == nil {
                // No CGImage might indicate it's an animated format
                isSelectedImageGIF = true
                return
            }
            
            isSelectedImageGIF = false
        } else {
            isSelectedImageGIF = false
        }
    }
}

// MARK: - KeyEventHandlingView
struct KeyEventHandlingView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlingView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyHandlingView {
            view.onKeyDown = onKeyDown
        }
    }
    
    class KeyHandlingView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            if onKeyDown?(event) == true {
                return
            }
            super.keyDown(with: event)
        }
        
        override func becomeFirstResponder() -> Bool {
            return true
        }
    }
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
                .foregroundColor(.gray)
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
        }
        .padding(.horizontal, 0)
        .background(Color.clear)
    }
}

// MARK: - AppRow
struct AppRow: View {
    let app: AppInfo
    let isSelected: Bool
    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 28, height: 28)
                .cornerRadius(6)
            Text(app.name)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "#92898B"))
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color(hex: "#181818") : Color.clear)
        .cornerRadius(8)
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
                            pendingHotkey = nil
                        }
                    }
                }
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
                Text("To set a new hotkey, click 'Set Hotkey' and press your desired combination. Avoid system-reserved shortcuts.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(32)
            .frame(minWidth: 700, minHeight: 500)
        }
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                let granted = AXIsProcessTrusted()
                if granted != accessibilityGranted {
                    accessibilityGranted = granted
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage)
                .onDisappear {
                    if let img = selectedImage, let data = img.tiffRepresentation {
                        UserDefaults.standard.set(data, forKey: "leftImage")
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
            // Check for empty keycodes
            if hotkey.key.isEmpty || hotkey.key == "unknown" {
                return "Invalid key detected"
            }
            
            // Require at least one modifier
            if hotkey.modifiers.isEmpty {
                return "At least one modifier key (Command, Option, Control, or Shift) is required"
            }
            
            // Check for system shortcuts
            let systemShortcuts: [(hotkey: Hotkey, description: String)] = [
                (Hotkey(key: "space", modifiers: ["command"]), "Spotlight"),
                (Hotkey(key: "tab", modifiers: ["command"]), "App Switcher"),
                (Hotkey(key: "w", modifiers: ["command"]), "Close Window"),
                (Hotkey(key: "q", modifiers: ["command"]), "Quit Application"),
                (Hotkey(key: "h", modifiers: ["command"]), "Hide Application"),
                (Hotkey(key: "m", modifiers: ["command"]), "Minimize Window"),
                (Hotkey(key: "c", modifiers: ["command"]), "Copy"),
                (Hotkey(key: "v", modifiers: ["command"]), "Paste"),
                (Hotkey(key: "x", modifiers: ["command"]), "Cut"),
                (Hotkey(key: "a", modifiers: ["command"]), "Select All"),
                (Hotkey(key: "z", modifiers: ["command"]), "Undo"),
                (Hotkey(key: "z", modifiers: ["command", "shift"]), "Redo"),
                (Hotkey(key: ",", modifiers: ["command"]), "Preferences"),
                (Hotkey(key: "f", modifiers: ["command"]), "Find"),
                (Hotkey(key: "g", modifiers: ["command"]), "Find Next"),
                (Hotkey(key: "g", modifiers: ["command", "shift"]), "Find Previous"),
                (Hotkey(key: "f", modifiers: ["command", "option"]), "Search in Spotlight"),
                (Hotkey(key: "l", modifiers: ["command"]), "Go to Address Bar"),
                (Hotkey(key: "r", modifiers: ["command"]), "Refresh"),
                (Hotkey(key: "t", modifiers: ["command"]), "New Tab"),
                (Hotkey(key: "n", modifiers: ["command"]), "New Window"),
                (Hotkey(key: "s", modifiers: ["command"]), "Save"),
                (Hotkey(key: "o", modifiers: ["command"]), "Open"),
                (Hotkey(key: "p", modifiers: ["command"]), "Print"),
                (Hotkey(key: "delete", modifiers: ["command"]), "Delete")
            ]
            
            for (shortcutHotkey, description) in systemShortcuts {
                if shortcutHotkey.key == hotkey.key {
                    // Check if all modifiers match
                    let shortcutModifiersSet = Set(shortcutHotkey.modifiers)
                    let hotkeyModifiersSet = Set(hotkey.modifiers)
                    
                    if shortcutModifiersSet == hotkeyModifiersSet {
                        return "This shortcut conflicts with the system shortcut for '\(description)'"
                    }
                }
            }
            
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
    
    func setHotkey(_ hotkey: Hotkey, action: @escaping () -> Void) {
        // Remove existing monitor if any
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        
        // Store the current hotkey and callback
        currentHotkey = hotkey
        callback = action
        
        // Create a new monitor for the hotkey
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let currentHotkey = self.currentHotkey else { return }
            
            // Get the exact modifier flags we expect
            let expectedModifiers = self.expectedModifierFlags(for: currentHotkey)
            
            // Check if the event's modifiers exactly match what we expect
            let modifiersMatch = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == expectedModifiers
            
            if modifiersMatch {
                // Only then check the key code
                let keyMatch = event.keyCode == self.keyCode(for: currentHotkey.key)
                if keyMatch {
                    DispatchQueue.main.async { [weak self] in
                        self?.callback?()
                    }
                }
            }
        }
    }
    
    private func expectedModifierFlags(for hotkey: Hotkey) -> NSEvent.ModifierFlags {
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
    
    private func keyCode(for key: String) -> UInt16 {
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

// MARK: - Update ImagePicker to better handle GIFs
struct ImagePicker: NSViewControllerRepresentable {
    @Binding var image: NSImage?
    
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
                // Load the image based on file type
                loadImage(from: url)
            }
        }
        
        return viewController
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
    
    private func loadImage(from url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        
        // Special handling for GIFs to preserve animation
        if fileExtension == "gif" {
            if let gifData = try? Data(contentsOf: url) {
                let gifImage = NSImage(data: gifData)
                self.image = gifImage
                
                // Save the raw data to preserve animation
                UserDefaults.standard.set(gifData, forKey: "leftImage")
                NotificationCenter.default.post(name: .imageChanged, object: nil)
            }
        } else {
            // For other image types
            if let nsImage = NSImage(contentsOf: url) {
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
        
        // Enable animation for GIFs
        if isAnimating {
            enableAnimation(for: imageView)
        }
        
        return imageView
    }
    
    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = image
        
        if isAnimating {
            enableAnimation(for: nsView)
        } else {
            disableAnimation(for: nsView)
        }
    }
    
    private func enableAnimation(for imageView: NSImageView) {
        // Enable animation on NSImageView
        imageView.animates = true
    }
    
    private func disableAnimation(for imageView: NSImageView) {
        // Disable animation on NSImageView
        imageView.animates = false
    }
}
