import Carbon.HIToolbox
import Foundation

final class HotKeyCenter {
    private static let signature: OSType = 0x5153_656C

    private var registered: [EventHotKeyRef] = []
    private var siteIDsByHotKeyID: [UInt32: UUID] = [:]
    private var handlerRef: EventHandlerRef?
    private let onPress: (UUID) -> Void

    init(onPress: @escaping (UUID) -> Void) {
        self.onPress = onPress
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().fire(hotKeyID.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    deinit {
        unregisterAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Replaces every registered shortcut and returns the sites whose shortcut another app already owns.
    func register(_ entries: [(siteID: UUID, shortcut: Shortcut)]) -> Set<UUID> {
        unregisterAll()
        var unavailable: Set<UUID> = []
        for (index, entry) in entries.enumerated() {
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(entry.shortcut.keyCode, entry.shortcut.carbonModifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                unavailable.insert(entry.siteID)
                continue
            }
            registered.append(ref)
            siteIDsByHotKeyID[hotKeyID.id] = entry.siteID
        }
        return unavailable
    }

    func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
        siteIDsByHotKeyID.removeAll()
    }

    private func fire(_ hotKeyID: UInt32) {
        guard let siteID = siteIDsByHotKeyID[hotKeyID] else { return }
        onPress(siteID)
    }
}
