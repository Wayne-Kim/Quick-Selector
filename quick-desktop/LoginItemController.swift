import Foundation
import ServiceManagement

@MainActor
enum LoginItemController {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("[quick-desktop] login item toggle failed: \(error.localizedDescription)")
        }
    }
}
