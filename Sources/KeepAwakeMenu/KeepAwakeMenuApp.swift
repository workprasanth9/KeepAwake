#if os(macOS)
import AppKit
import KeepAwakeCore
import SwiftUI

@MainActor
final class MenuModel: ObservableObject {
    @Published var headline = "Sleep allowed"
    @Published var detail = "Idle display sleep and idle system sleep can occur"
    @Published var holding = false

    private var session: PowerSession?
    private var generation = 0

    func start(minutes: Int) {
        begin(StartInput(duration: "\(minutes)m"))
    }

    func startIndefinite() {
        begin(StartInput(indefinite: true))
    }

    func stop() {
        generation += 1
        session?.cancel()
        session = nil
        holding = false
        headline = "Sleep allowed"
        detail = "Idle display sleep and idle system sleep can occur"
    }

    private func begin(_ input: StartInput) {
        stop()
        let request: ResolvedRequest
        do {
            let config = try ManagedConfigLoader.loadDefault().config
            request = try RequestResolver.resolve(
                input,
                config: config,
                now: Date(),
                calendar: .current,
                context: .start
            )
        } catch {
            headline = "Could not start"
            detail = error.localizedDescription
            holding = false
            return
        }
        generation += 1
        let token = generation
        let session = PowerSession(installSignalHandlers: false, log: { _ in })
        self.session = session
        holding = true
        headline = "Awake"
        detail = request.summary
        Thread {
            do {
                try session.run(request)
            } catch {
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.holding = false
                    self.headline = "Could not start"
                    self.detail = error.localizedDescription
                    self.session = nil
                }
                return
            }
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.holding = false
                self.headline = "Sleep allowed"
                self.detail = "Idle display sleep and idle system sleep can occur"
                self.session = nil
            }
        }.start()
    }
}

@main
struct KeepAwakeMenuApp: App {
    @StateObject private var model = MenuModel()

    var body: some Scene {
        MenuBarExtra {
            Text(model.headline)
            Text(model.detail)
            Divider()
            Button("Awake for 30 minutes") { model.start(minutes: 30) }
            Button("Awake for 1 hour") { model.start(minutes: 60) }
            Button("Awake for 2 hours") { model.start(minutes: 120) }
            Button("Awake for 4 hours") { model.start(minutes: 240) }
            Button("Awake until I stop it") { model.startIndefinite() }
            Divider()
            Button("Stop") { model.stop() }
                .disabled(!model.holding)
            Divider()
            Button("Quit KeepAwake") {
                model.stop()
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: model.holding ? "cup.and.saucer.fill" : "cup.and.saucer")
                .accessibilityLabel("KeepAwake")
        }
        .menuBarExtraStyle(.menu)
    }
}
#else
import Foundation
#if canImport(Glibc)
import Glibc
#endif

@main
enum KeepAwakeMenuMain {
    static func main() {
        let message = "KeepAwakeMenu requires macOS 13 or later.\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }
}
#endif
