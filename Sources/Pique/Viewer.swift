import AppKit
import SwiftUI

/// Detached, resizable camera window that can be pinned above other apps.
final class Viewer: NSObject, ObservableObject, NSWindowDelegate {
    @Published var pinned = UserDefaults.standard.bool(forKey: "pinned") {
        didSet {
            UserDefaults.standard.set(pinned, forKey: "pinned")
            applyPin()
        }
    }
    @Published var showInfo = UserDefaults.standard.object(forKey: "showPrintInfo") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showInfo, forKey: "showPrintInfo") }
    }
    private var window: NSWindow?

    func show(camera: Camera, status: PrinterStatus) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Pique"
            window.contentAspectRatio = NSSize(width: 16, height: 9)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: ViewerView(camera: camera, status: status, viewer: self))
            window.center()
            window.setFrameAutosaveName("viewer")
            self.window = window
        }
        applyPin()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func toggleFullScreen() {
        guard let window else { return }
        if !window.styleMask.contains(.fullScreen) {
            // A pinned (auxiliary) window cannot become a full-screen space itself.
            window.level = .normal
            window.collectionBehavior = [.fullScreenPrimary]
        }
        window.toggleFullScreen(nil)
    }

    func windowDidExitFullScreen(_ notification: Notification) { applyPin() }

    private func applyPin() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.level = pinned ? .floating : .normal
        // Pinned: follow every Space and float over other apps' full-screen windows.
        window.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenPrimary]
    }
}

/// Camera frame with a magnifier bubble that follows the cursor.
/// `overlay` sits between the frame and the loupe, pinned to the bottom of the image.
struct CameraImage: View {
    let image: NSImage
    var overlay: AnyView?
    @StateObject private var hover = Hover()
    private let lens: CGFloat = 160

    var body: some View {
        GeometryReader { geo in
            // ponytail: zoom = camera's native pixels (min 2x on screen); tune the factor if the loupe looks too soft/strong.
            let zoom = max(2, image.size.width / max(geo.size.width, 1))
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable()
                if let overlay {
                    overlay.frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                }
                if let p = hover.location {
                    Image(nsImage: image).resizable()
                        .frame(width: geo.size.width * zoom, height: geo.size.height * zoom)
                        .offset(x: lens / 2 - p.x * zoom, y: lens / 2 - p.y * zoom)
                        .frame(width: lens, height: lens, alignment: .topLeading)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                        .shadow(radius: 8)
                        .position(p)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hover.location = p
                case .ended: hover.location = nil
                }
            }
        }
        .aspectRatio(image.size, contentMode: .fit)
    }
}

final class Hover: ObservableObject { // not @State: its macro plugin ships only with Xcode, not the CLT
    @Published var location: CGPoint?
}

struct ViewerView: View {
    @ObservedObject var camera: Camera
    let status: PrinterStatus
    @ObservedObject var viewer: Viewer
    @AppStorage(AppLanguage.key) private var language = "system"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            if let image = camera.image {
                CameraImage(image: image, overlay: viewer.showInfo ? AnyView(PrintOverlay(status: status)) : nil)
            } else {
                Text(camera.status).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 10) {
                LightButton(status: status)
                Button { viewer.showInfo.toggle() } label: {
                    Image(systemName: viewer.showInfo ? "info.circle.fill" : "info.circle")
                }
                .help(viewer.showInfo ? LocalizedStringKey("Hide print info") : "Show print info")
                Button { viewer.pinned.toggle() } label: {
                    Image(systemName: viewer.pinned ? "pin.fill" : "pin")
                }
                .help(viewer.pinned ? LocalizedStringKey("Unpin") : "Keep on top of other windows")
                Button { viewer.toggleFullScreen() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Full screen (Esc to exit)")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
        }
        .frame(minWidth: 320, minHeight: 180)
        .environment(\.locale, Locale(identifier: AppLanguage.resolved(language)))
    }
}
