import AppKit
import CoreAudio

/// Turns system volume changes into a notch HUD.
///
/// Fully event-driven: CoreAudio tells us the instant the level or mute state
/// moves, whoever moved it — the keyboard, the menu bar, or another app. No
/// polling, no key monitoring, so no Accessibility prompt.
@MainActor
final class AudioService {
    private let model: NotchViewModel

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var registered: [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    /// Seeded on the first read so launching the app doesn't flash a HUD.
    private var last: (value: Double, muted: Bool)?

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        observeDefaultDevice()
        attachToCurrentDevice()
    }

    func stop() {
        for entry in registered {
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(entry.object, &address, DispatchQueue.main, entry.block)
        }
        registered.removeAll()
    }

    // MARK: Wiring

    private func observeDefaultDevice() {
        listen(
            on: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        ) { [weak self] in
            guard let self else { return }
            // Switching to AirPods or a monitor means re-subscribing.
            detachFromDevice()
            attachToCurrentDevice()
        }
    }

    private func attachToCurrentDevice() {
        guard let current = defaultOutputDevice() else { return }
        device = current
        last = read(device)

        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            listen(on: device, selector: selector, scope: kAudioDevicePropertyScopeOutput) { [weak self] in
                self?.volumeChanged()
            }
        }
    }

    private func detachFromDevice() {
        let deviceListeners = registered.filter { $0.object == device }
        for entry in deviceListeners {
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(entry.object, &address, DispatchQueue.main, entry.block)
        }
        registered.removeAll { $0.object == device }
        device = AudioObjectID(kAudioObjectUnknown)
        last = nil
    }

    private func listen(
        on object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        handler: @escaping @MainActor () -> Void
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block)
        guard status == noErr else { return }
        registered.append((object, address, block))
    }

    // MARK: Reading

    private func volumeChanged() {
        guard device != kAudioObjectUnknown, let reading = read(device) else { return }
        defer { last = reading }

        guard let previous = last else { return }
        let moved = abs(reading.value - previous.value) > 0.001 || reading.muted != previous.muted
        guard moved, model.settings.showVolumeHUD else { return }

        Log.system.info("volume \(reading.value, format: .fixed(precision: 2)) muted=\(reading.muted)")
        model.present(.level(LevelActivity(
            kind: .volume,
            value: reading.value,
            isMuted: reading.muted
        )))
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    private func read(_ device: AudioObjectID) -> (value: Double, muted: Bool)? {
        guard let value = scalarVolume(device) else { return nil }
        return (value, muted(device))
    }

    /// Most devices expose a master element; the rest only answer per channel.
    private func scalarVolume(_ device: AudioObjectID) -> Double? {
        if let main = float(device, kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return Double(main)
        }
        let channels = [UInt32(1), UInt32(2)].compactMap {
            float(device, kAudioDevicePropertyVolumeScalar, element: $0)
        }
        guard !channels.isEmpty else { return nil }
        return Double(channels.reduce(0, +) / Float(channels.count))
    }

    private func muted(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value == 1
    }

    private func float(
        _ device: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }
}
