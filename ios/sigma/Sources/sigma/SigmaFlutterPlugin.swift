import Combine
// Flutter's headers predate Swift concurrency; it calls plugins on the main thread.
@preconcurrency import Flutter
import NimbusSigma
import SwiftUI
import UIKit

/// Registers the "sigma/sheet" platform view: Sigma's native editor.
public final class SigmaFlutterPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        registrar.register(SheetFactory(messenger: registrar.messenger()), withId: "sigma/sheet")
    }
}

final class SheetFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        MainActor.assumeIsolated { SheetPlatformView(frame: frame, id: viewId, messenger: messenger, params: args as? [String: Any] ?? [:]) }
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
}

/// Dart answered a link request with a failure.
private struct LinkFailed: Error { let message: String }

/// One SigmaSheetView and its SigmaSession, talking to its SigmaSheet widget
/// over "sigma/sheet_<id>": the native side asks Dart for links and
/// reports the phase, save state, title and saves; Dart sends commands.
@MainActor
final class SheetPlatformView: NSObject, @preconcurrency FlutterPlatformView {
    private let container: SheetContainer
    private let channel: FlutterMethodChannel
    private var session: SigmaSession?
    private let controller = SigmaGridController()
    private var watching = Set<AnyCancellable>()
    /// The last link request ended in a failure from Dart, not the server.
    private var linkFailure: String?
    private let params: [String: Any]

    init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger, params: [String: Any]) {
        self.params = params
        container = SheetContainer(frame: frame)
        channel = FlutterMethodChannel(name: "sigma/sheet_\(id)", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            MainActor.assumeIsolated { self?.handle(call, result) ?? result(nil) }
        }
    }

    deinit {
        let s = session
        Task { @MainActor in try? await s?.save() }
    }

    func view() -> UIView { container }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        // Dart listens first, then starts the sheet, so the first link request has an answerer.
        case "start": start(); result(nil)
        case "save": run(result) { s in try await s.save(); return nil }
        case "export":
            run(result) { s in
                let f = try await s.export((args["format"] as? String).flatMap(SigmaFormat.init(rawValue:)))
                return ["bytes": FlutterStandardTypedData(bytes: f.data), "filename": f.filename, "format": f.format.rawValue, "mimeType": f.format.mimeType]
            }
        case "undo": controller.undo(); result(nil)
        case "redo": controller.redo(); result(nil)
        case "reload": run(result) { s in s.reload(); return nil }
        case "rename": run(result) { s in s.title = args["title"] as? String ?? ""; return nil }
        default: result(FlutterMethodNotImplemented)
        }
    }

    private func start() {
        guard session == nil else { return }
        let s = SigmaSession { [weak self] in
            guard let self else { throw SigmaError.notReady }
            do {
                let url = try await self.askDart()
                self.linkFailure = nil
                return url
            } catch let e as LinkFailed {
                self.linkFailure = e.message
                throw SigmaError.network(e.message)
            }
        }
        session = s
        var header = SigmaHeader(showsBack: params["back"] as? Bool ?? true, showsLogo: params["logo"] as? Bool ?? true) { [weak self] in
            // Dart decides what back means: its onBack, or popping the route.
            self?.channel.invokeMethod("back", arguments: nil)
        }
        if params["header"] as? Bool == false { header.isVisible = false }
        container.show(SigmaSheetView(session: s, controller: controller, header: header))
        watch(s)
        s.start()
    }

    /// Asks the widget's `link` function for a signed link.
    private func askDart() async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            channel.invokeMethod("link", arguments: nil) { answer in
                if let e = answer as? FlutterError {
                    cont.resume(throwing: LinkFailed(message: e.message ?? "Your link function failed."))
                } else if (answer as? NSObject) === FlutterMethodNotImplemented {
                    cont.resume(throwing: LinkFailed(message: "The sheet is not on screen."))
                } else if let s = answer as? String, let url = URL(string: s), url.scheme != nil {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: LinkFailed(message: "Your link function returned no link."))
                }
            }
        }
    }

    private func watch(_ s: SigmaSession) {
        s.$phase.removeDuplicates().sink { [weak self] p in
            guard let self else { return }
            switch p {
            case .loading: send("phase", ["phase": "loading"])
            case .ready:
                var body: [String: Any] = ["phase": "ready"]
                if let d = s.document {
                    body["document"] = ["id": d.id, "title": d.title, "filename": d.filename, "format": d.format.rawValue, "mode": d.mode.rawValue, "test": d.test]
                }
                send("phase", body)
            case let .failed(e):
                send("phase", ["phase": "failed", "error": Self.errorBody(e, linkFailure: linkFailure)])
            }
        }.store(in: &watching)
        s.$saveState.removeDuplicates().sink { [weak self] st in
            switch st {
            case .saved: self?.send("saveState", ["state": "saved"])
            case .unsaved: self?.send("saveState", ["state": "unsaved"])
            case .saving: self?.send("saveState", ["state": "saving"])
            case let .failed(e): self?.send("saveState", ["state": "failed", "error": Self.errorBody(e, linkFailure: nil)])
            }
        }.store(in: &watching)
        // The title is empty until the sheet opens; only a real one is news.
        s.$title.removeDuplicates().sink { [weak self] t in
            if !t.isEmpty || s.phase == .ready { self?.send("title", ["title": t]) }
        }.store(in: &watching)
        s.$lastSaved.compactMap { $0 }.sink { [weak self] at in self?.send("saved", ["at": at.timeIntervalSince1970 * 1000]) }.store(in: &watching)
    }

    private func send(_ method: String, _ body: [String: Any]) { channel.invokeMethod(method, arguments: body) }

    private func run(_ result: @escaping FlutterResult, _ body: @escaping (SigmaSession) async throws -> Any?) {
        guard let s = session else { return result(FlutterError(code: "not_ready", message: "The sheet is still opening.", details: nil)) }
        Task {
            do { result(try await body(s)) } catch let e as SigmaError {
                let b = Self.errorBody(e, linkFailure: nil)
                result(FlutterError(code: b["code"] as? String ?? "server", message: b["message"] as? String, details: b["status"].map { ["status": $0] }))
            } catch {
                result(FlutterError(code: "server", message: error.localizedDescription, details: nil))
            }
        }
    }

    static func errorBody(_ e: SigmaError, linkFailure: String?) -> [String: Any] {
        let message = e.errorDescription ?? ""
        switch e {
        case .unauthorized: return ["code": "unauthorized", "message": message]
        case .quotaExceeded: return ["code": "quota_exceeded", "message": message]
        case .notFound: return ["code": "not_found", "message": message]
        case .linkExpired: return ["code": "link_expired", "message": message]
        case .linkInvalid: return ["code": "link_invalid", "message": message]
        case .editor: return ["code": "editor", "message": message]
        case .notReady: return ["code": "not_ready", "message": message]
        case .engine: return ["code": "engine", "message": message]
        case let .server(status, _): return ["code": "server", "message": message, "status": status]
        case let .network(m): return ["code": linkFailure != nil && m == linkFailure ? "link_failed" : "network", "message": message]
        }
    }
}

/// Holds the SwiftUI editor. The editor presents its panels as sheets, so its
/// hosting controller must be a child of the screen's view controller.
final class SheetContainer: UIView {
    private var hosting: UIHostingController<AnyView>?

    func show<V: View>(_ view: V) {
        let host = UIHostingController(rootView: AnyView(view))
        host.view.backgroundColor = .systemBackground
        host.view.frame = bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(host.view)
        hosting = host
        attachToParent()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            hosting?.willMove(toParent: nil)
            hosting?.removeFromParent()
        } else {
            attachToParent()
        }
    }

    private func attachToParent() {
        guard let host = hosting, host.parent == nil, window != nil else { return }
        var r: UIResponder? = self
        while let next = r?.next {
            if let vc = next as? UIViewController { vc.addChild(host); host.didMove(toParent: vc); return }
            r = next
        }
    }
}
