import AppKit
import CoreAudio
import SwiftUI

/// Shows a discreet dot in the notch while the microphone is live.
///
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` is a read of the device's
/// state, not a capture, so this needs no microphone permission and never
/// prompts — we learn *that* the mic is on, never what it hears.
///
/// The camera has an equivalent in CoreMediaIO, but merely enumerating video
/// devices can trip the camera permission prompt, and a status dot isn't worth
/// making the user answer that. Mic only, deliberately.
@MainActor
final class PrivacyService {
    private let model: NotchViewModel

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var registered: [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        listen(
            on: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultInputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        ) { [weak self] in
            self?.attach()
        }
        attach()
    }

    func stop() {
        for entry in registered {
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(entry.object, &address, DispatchQueue.main, entry.block)
        }
        registered.removeAll()
    }

    private func attach() {
        // Drop listeners on the old input before following the new one.
        let stale = registered.filter { $0.object == device }
        for entry in stale {
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(entry.object, &address, DispatchQueue.main, entry.block)
        }
        registered.removeAll { $0.object == device }

        guard let input = defaultInputDevice() else {
            update(false)
            return
        }
        device = input
        listen(
            on: device,
            selector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            scope: kAudioObjectPropertyScopeGlobal
        ) { [weak self] in
            guard let self else { return }
            update(isRunning(device))
        }
        update(isRunning(device))
    }

    private func update(_ micInUse: Bool) {
        guard model.privacy.micInUse != micInUse else { return }
        withAnimation(Motion.pill) { model.privacy.micInUse = micInUse }
        Log.system.info("microphone in use: \(micInUse)")
    }

    // MARK: CoreAudio

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
        guard AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr
        else { return }
        registered.append((object, address, block))
    }

    private func defaultInputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
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

    private func isRunning(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }
}
