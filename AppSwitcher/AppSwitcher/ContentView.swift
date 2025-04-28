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

struct AppInfo: Identifiable {
    let id = UUID()
    let name: String
    let icon: NSImage
    let description: String?
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

// MARK: - ContentView
struct ContentView: View {
    @State private var selectedImage: NSImage? = UserDefaults.standard.data(forKey: "leftImage").flatMap { NSImage(data: $0) } ?? NSImage(named: "NSPhoto")
    @State private var showingImagePicker = false
    @State private var selectedApp: UUID? = nil
    @State private var hoveredApp: UUID? = nil
    @State private var apps: [AppInfo] = []
    @State private var showingSettings = false
    @State private var hotkey: Hotkey = {
        if let data = UserDefaults.standard.data(forKey: "hotkey"), let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            return hk
        } else {
            return .default
        }
    }()
    @State private var searchText: String = ""
    @State private var searchFieldFocused: Bool = false
    var filteredApps: [AppInfo] {
        if searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    // Helper view for app list
    private func appList(scrollProxy: ScrollViewProxy) -> some View {
        ForEach(filteredApps) { app in
            AppRow(app: app, isHighlighted: hoveredApp == app.id)
                .id(app.id)
                .contentShape(Rectangle())
                .onTapGesture { openApp(app) }
                .onHover { hovering in
                    if hovering {
                        hoveredApp = app.id
                    } else if hoveredApp == app.id {
                        hoveredApp = nil
                    }
                }
        }
    }
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Left: Image, no border, only left radius
                ZStack {
                    if let image = selectedImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 300, height: 408)
                            .clipped()
                            .clipShape(RoundedCorner(radius: 12, corners: [.topLeft, .bottomLeft]))
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 300, height: 408)
                            .clipShape(RoundedCorner(radius: 12, corners: [.topLeft, .bottomLeft]))
                            .overlay(Text("No Image").foregroundColor(.secondary))
                    }
                }
                .frame(width: 300, height: 408)
                // Divider (blue)
                Rectangle()
                    .fill(Color(red: 0.36, green: 0.60, blue: 0.98, opacity: 0.5))
                    .frame(width: 2, height: 408)
                // Right: App List with background (no border, only right radius)
                ZStack {
                    RoundedCorner(radius: 12, corners: [.topRight, .bottomRight])
                        .fill(Color(red: 0.13, green: 0.15, blue: 0.20, opacity: 0.92))
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            SearchInput(text: $searchText, isFocused: $searchFieldFocused)
                                .frame(height: 48)
                                .padding(.top, 0)
                                .padding(.leading, 16)
                                .padding(.trailing, 0)
                        }
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    appList(scrollProxy: scrollProxy)
                                }
                            }
                            .onChange(of: selectedApp) { oldValue, newValue in
                                if let id = newValue {
                                    withAnimation(.none) { scrollProxy.scrollTo(id, anchor: .center) }
                                }
                            }
                            .gesture(DragGesture().onChanged { _ in hoveredApp = nil })
                        }
                    }
                }
                .frame(width: 340, height: 408)
            }
            .frame(width: 640, height: 408)
        }
        .frame(width: 640, height: 408)
        .onAppear {
            apps = getInstalledApps()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { searchFieldFocused = true }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(selectedImage: $selectedImage, hotkey: $hotkey)
        }
        .onExitCommand(perform: closeSwitcher)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showingSettings = true }) {}
                    .keyboardShortcut(",", modifiers: .command)
            }
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
        if let window = NSApplication.shared.windows.first(where: { $0.styleMask.contains(.borderless) }) {
            window.orderOut(nil)
        }
    }
}

// FocusableTextField: NSTextField that can become first responder in borderless window
import SwiftUI
struct FocusableTextField: NSViewRepresentable {
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        init(_ parent: FocusableTextField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
    @Binding var text: String
    @Binding var isFirstResponder: Bool
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
        }
    }
}

// Search input with no border, no radius, and a prefix icon, using FocusableTextField
struct SearchInput: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            FocusableTextField(text: $text, isFirstResponder: $isFocused)
                .frame(height: 32)
        }
        .padding(.horizontal, 0)
        .background(Color.clear)
    }
}

// MARK: - AppRow
struct AppRow: View {
    let app: AppInfo
    let isHighlighted: Bool
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
        .background(isHighlighted ? Color(hex: "#181818") : Color.clear)
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
                            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
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
                let key = self.keyString(for: event)
                let mods = self.modifierStrings(for: event)
                let newHotkey = Hotkey(key: key, modifiers: mods)
                if let conflict = self.checkConflict(hotkey: newHotkey) {
                    self.parent.hotkeyConflict = conflict
                } else {
                    self.parent.pendingHotkey = newHotkey
                    self.parent.hotkeyConflict = nil
                }
                self.parent.listening = false
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
            // Map keyCode to string for common keys
            switch event.keyCode {
            case 49: return "space"
            case 36: return "return"
            case 51: return "delete"
            case 53: return "escape"
            case 43: return ","
            default:
                if let chars = event.charactersIgnoringModifiers, chars.count == 1 {
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
            let systemShortcuts: [Hotkey] = [
                Hotkey(key: "space", modifiers: ["command"]), // Spotlight
                Hotkey(key: "space", modifiers: ["control"]), // Input source (default, but user can override)
                Hotkey(key: "tab", modifiers: ["command"]), // App switcher
                Hotkey(key: "f3", modifiers: []), // Mission Control
                Hotkey(key: "f4", modifiers: []), // Launchpad
                Hotkey(key: ",", modifiers: ["command"]), // Preferences
            ]
            for sys in systemShortcuts {
                if sys == hotkey {
                    return "This hotkey is reserved by macOS. Please choose another."
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
    func setHotkey(_ hotkey: Hotkey, action: @escaping () -> Void) {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        callback = action
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let keyMatch = event.keyCode == self.keyCode(for: hotkey.key)
            let modsMatch = self.modifiersMatch(event: event, hotkey: hotkey)
            if keyMatch && modsMatch {
                action()
            }
        }
    }
    private func keyCode(for key: String) -> UInt16 {
        switch key.lowercased() {
        case "space": return 49
        case ",": return 43
        default: return 0
        }
    }
    private func modifiersMatch(event: NSEvent, hotkey: Hotkey) -> Bool {
        let mods = hotkey.modifiers
        let ctrl = mods.contains("control") ? event.modifierFlags.contains(.control) : !event.modifierFlags.contains(.control)
        let cmd = mods.contains("command") ? event.modifierFlags.contains(.command) : !event.modifierFlags.contains(.command)
        let opt = mods.contains("option") ? event.modifierFlags.contains(.option) : !event.modifierFlags.contains(.option)
        let shift = mods.contains("shift") ? event.modifierFlags.contains(.shift) : !event.modifierFlags.contains(.shift)
        return ctrl && cmd && opt && shift
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

// ImagePicker for macOS
struct ImagePicker: NSViewControllerRepresentable {
    @Binding var image: NSImage?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSViewController(context: Context) -> NSViewController {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [
            UTType.png,
            UTType.jpeg,
            UTType.bmp,
            UTType.gif,
            UTType.tiff
        ]
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        let viewController = NSViewController()
        DispatchQueue.main.async {
            if picker.runModal() == .OK, let url = picker.url, let nsImage = NSImage(contentsOf: url) {
                image = nsImage
            }
        }
        return viewController
    }
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
    class Coordinator: NSObject {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
    }
}

// Notification for hotkey change
extension Notification.Name {
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
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
