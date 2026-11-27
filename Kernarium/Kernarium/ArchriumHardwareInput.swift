// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import GuestHostCore
import UIKit

/// The keys the Linux keyboard settings write, read by `ArchriumHardwareInput`
/// when the guest takes the devices.
enum ArchriumKeyboardSettings {
    static let commandAsControlKey = "ArchriumLinuxCommandAsControl"
    static let capsLockAsEscapeKey = "ArchriumLinuxCapsLockAsEscape"
    static let keyRepeatKey = "ArchriumLinuxKeyRepeat"

    static func apply(to input: GuestHardwareInput, defaults: UserDefaults = .standard) {
        input.commandAsControl = defaults.bool(forKey: commandAsControlKey)
        input.capsLockAsEscape = defaults.bool(forKey: capsLockAsEscapeKey)
        // A stored false turns repeats off; a missing key leaves them on.
        input.repeatsKeys = defaults.object(forKey: keyRepeatKey) as? Bool ?? true
    }
}

/// The Linux guest's physical keyboard, mouse and trackpad.
///
/// Andarium only gave these devices to its Android guest. A Linux desktop
/// needs real evdev input: key positions, an absolute pointer with buttons,
/// and the mouse wheel. This class plugs the runtime's hardware keyboard,
/// mouse and pointer for every Linux run, and sends UIKit's hardware events
/// through `GuestHardwareInput`.
///
/// The devices stay plugged while the guest runs. Leaving the display only
/// makes the input inactive: keys and buttons are released, so nothing stays
/// down in the guest, but the guest keeps its keyboard and mouse.
@MainActor
final class ArchriumHardwareInput: GuestHardwareSink {
    static let shared = ArchriumHardwareInput()

    let input = GuestHardwareInput()

    private var running = false
    private var keyboardPlugged = false
    private var mousePlugged = false
    private var retryTask: Task<Void, Never>?

    private init() {
        input.sink = self
        // Linux owns its Caps Lock through evdev; do not let the Android
        // reconciliation tap it when iOS's own Caps Lock state differs.
        input.reconcilesCapsLock = false
        // A Linux desktop wants a real relative mouse, not Android's absolute
        // pointer/tablet device. The system pointer's position becomes motion.
        input.usesRelativePointer = true
        // The pointer is the guest's from the start: clicks and hovers must
        // not fall back to touchscreen coordinates.
        input.routesPointer = true
        ArchriumKeyboardSettings.apply(to: input)
    }

    /// The run began or ended, and the display is (or is not) in front.
    func update(running: Bool, foreground: Bool) {
        if self.running != running {
            self.running = running
            if !running { resetConnections() }
        }
        // The keyboard choices may have changed while the settings sheet was
        // open; no key is held then, so applying them now is safe.
        ArchriumKeyboardSettings.apply(to: input)
        input.isActive = running && foreground
        guard input.isActive else {
            retryTask?.cancel()
            retryTask = nil
            input.releaseAll()
            return
        }
        ensurePlugged()
        scheduleRetry()
    }

    // MARK: GuestHardwareSink

    func hardwareKeyboardUsed() {
        ensurePlugged()
    }

    func hardwareKey(usage: UInt32, pressed: Bool) {
        ensurePlugged()
        _ = kernarium_runtime_loader_send_keyboard_usage(usage, pressed)
    }

    func hardwarePointerUsed() {
        ensurePlugged()
    }

    func hardwarePointer(_ report: PointerReport) {
        ensurePlugged()
        _ = kernarium_runtime_loader_send_pointer(
            report.x, report.y, report.buttons, report.inRange
        )
    }

    func hardwareMouse(
        dx: Int32,
        dy: Int32,
        buttons: UInt32,
        wheel: Int32,
        horizontalWheel: Int32
    ) {
        ensurePlugged()
        _ = kernarium_runtime_loader_send_mouse(
            dx, dy, buttons, wheel, horizontalWheel
        )
    }

    // MARK: Plugging

    private func ensurePlugged() {
        guard running, input.isActive else { return }
        if !keyboardPlugged, kernarium_runtime_loader_set_input_connected(
            Int32(KERNARIUM_RUNTIME_INPUT_KEYBOARD), true
        ) == 0 {
            keyboardPlugged = true
        }
        if !mousePlugged, kernarium_runtime_loader_set_input_connected(
            Int32(KERNARIUM_RUNTIME_INPUT_MOUSE), true
        ) == 0 {
            mousePlugged = true
        }
    }

    /// The runtime's hardware devices exist only after its boot has built
    /// them, which happens just after the run begins. Retry briefly instead
    /// of losing the first keys and the first click.
    private func scheduleRetry() {
        guard running, input.isActive, !(keyboardPlugged && mousePlugged) else {
            return
        }
        guard retryTask == nil else { return }
        retryTask = Task { @MainActor [weak self] in
            for _ in 0 ..< 30 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.running, self.input.isActive else {
                    return
                }
                self.ensurePlugged()
                if self.keyboardPlugged && self.mousePlugged { break }
            }
            self?.retryTask = nil
        }
    }

    private func resetConnections() {
        retryTask?.cancel()
        retryTask = nil
        keyboardPlugged = false
        mousePlugged = false
        input.releaseAll()
    }
}
