// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import UIKit

/// Keys the virtual keyboard sends. Character keys go through the same
/// evdev map as the system keyboard, so a letter typed here is the same
/// Linux key event a hardware keyboard would produce.
private enum VirtualKey: Hashable {
    case character(Character)
    case escape, tab, control, option, command, shift, backspace, enter, space
    case left, right, up, down
}

private enum VirtualModifier: Hashable {
    case control, option, command, shift
}

private struct VirtualKeyButton: View {
    let key: VirtualKey
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(active ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        switch key {
        case let .character(character): String(character)
        case .escape: "Esc"
        case .tab: "Tab"
        case .control: "Ctrl"
        case .option: "Alt"
        case .command: "⌘"
        case .shift: "⇧"
        case .backspace: "⌫"
        case .enter: "⏎"
        case .space: "Space"
        case .left: "←"
        case .right: "→"
        case .up: "↑"
        case .down: "↓"
        }
    }
}

struct VirtualLinuxInputView: View {
    @Binding var isPresented: Bool
    @State private var mode: Mode = .keyboard
    @State private var symbols = false
    @State private var sticky: Set<VirtualModifier> = []
    @State private var dragging = false
    @State private var lastTranslation: CGSize = .zero

    private enum Mode: String, CaseIterable {
        case keyboard = "Keyboard"
        case trackpad = "Trackpad"
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            if mode == .keyboard {
                keyboard
            } else {
                trackpad
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("Input", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            Spacer(minLength: 4)
            Button {
                isPresented = false
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 32)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
    }

    private var keyboard: some View {
        VStack(spacing: 4) {
            shortcutRow
            row([.escape, .tab, .control, .option, .command, .left, .up, .down, .right])
            if symbols {
                row(characters("!@#$%^&*()"))
                row(characters("-+=[]{}"))
                row(characters(";:'\",.<>/\\|"))
            } else {
                row(characters("1234567890"))
                row(characters("qwertyuiop"))
                row(characters("asdfghjkl"))
                row(characters("zxcvbnm"))
            }
            HStack(spacing: 4) {
                keyButton(.shift, active: sticky.contains(.shift))
                keyButton(.character(symbols ? "_" : ","))
                keyButton(.backspace)
                keyButton(.enter)
                Button {
                    symbols.toggle()
                } label: {
                    Text(symbols ? "ABC" : "?123")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                keyButton(.space)
            }
        }
    }

    private var trackpad: some View {
        VStack(spacing: 8) {
            TrackpadSurface()
                .frame(height: 150)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    Text("Drag to move · 1-finger tap left · 2-finger tap right · 3-finger tap middle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .allowsHitTesting(false)
                }

            HStack(spacing: 6) {
                trackpadButton("Left", .primary)
                trackpadButton("Right", .secondary)
                trackpadButton("Middle", .middle)
                Button("Scroll ↑") { VirtualKeySender.wheel(120) }
                    .buttonStyle(.bordered)
                Button("Scroll ↓") { VirtualKeySender.wheel(-120) }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var shortcutRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                shortcut("Copy", "c", [.control])
                shortcut("Paste", "v", [.control])
                shortcut("Cut", "x", [.control])
                shortcut("Undo", "z", [.control])
                shortcut("Term", "t", [.control, .option])
                shortcut("Alt-Tab", "\t", [.option])
                Button("Super") {
                    VirtualKeySender.tap(LinuxKeyboard.leftSuper, modifiers: [])
                }
                .buttonStyle(.bordered)
                .font(.caption)
                Button("Paste host") { pasteHostClipboard() }
                    .buttonStyle(.bordered)
                    .font(.caption)
            }
        }
        .frame(height: 32)
    }

    private func shortcut(_ title: String, _ character: Character, _ modifiers: [VirtualModifier]) -> some View {
        Button(title) {
            VirtualKeySender.text(character, modifiers: modifiers, shifted: false)
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    private func pasteHostClipboard() {
        guard let string = UIPasteboard.general.string, !string.isEmpty else { return }
        for character in string.prefix(20_000) {
            VirtualKeySender.text(character, modifiers: [], shifted: false)
        }
    }

    private func row(_ keys: [VirtualKey]) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                keyButton(key)
            }
        }
    }

    private func characters(_ string: String) -> [VirtualKey] {
        string.map { .character($0) }
    }

    private func keyButton(_ key: VirtualKey, active: Bool = false) -> some View {
        VirtualKeyButton(key: key, active: active) {
            press(key)
        }
    }

    private func trackpadButton(_ title: String, _ button: VirtualKeySender.Button) -> some View {
        Button(title) { VirtualKeySender.click(button) }
            .buttonStyle(.bordered)
    }

    private func press(_ key: VirtualKey) {
        switch key {
        case let .character(character):
            var modifiers: [VirtualModifier] = []
            for modifier in [VirtualModifier.control, .option, .command] where sticky.contains(modifier) {
                modifiers.append(modifier)
            }
            let shifted = sticky.contains(.shift) || character.isUppercase
            VirtualKeySender.text(character, modifiers: modifiers, shifted: shifted)
            sticky.removeAll()
        case .escape:
            VirtualKeySender.tap(LinuxKeyboard.escape, modifiers: sticky)
            sticky.removeAll()
        case .tab:
            VirtualKeySender.tap(LinuxKeyboard.tab, modifiers: sticky)
            sticky.removeAll()
        case .control:
            toggle(.control)
        case .option:
            toggle(.option)
        case .command:
            toggle(.command)
        case .shift:
            toggle(.shift)
        case .backspace:
            VirtualKeySender.tap(LinuxKeyboard.backspace, modifiers: sticky)
            sticky.removeAll()
        case .enter:
            VirtualKeySender.tap(LinuxKeyboard.enter, modifiers: sticky)
            sticky.removeAll()
        case .space:
            VirtualKeySender.tap(LinuxKeyboard.space, modifiers: sticky)
            sticky.removeAll()
        case .left:
            VirtualKeySender.tap(LinuxKeyboard.left, modifiers: sticky)
            sticky.removeAll()
        case .right:
            VirtualKeySender.tap(LinuxKeyboard.right, modifiers: sticky)
            sticky.removeAll()
        case .up:
            VirtualKeySender.tap(LinuxKeyboard.up, modifiers: sticky)
            sticky.removeAll()
        case .down:
            VirtualKeySender.tap(LinuxKeyboard.down, modifiers: sticky)
            sticky.removeAll()
        }
    }

    private func toggle(_ modifier: VirtualModifier) {
        if sticky.contains(modifier) {
            sticky.remove(modifier)
        } else {
            sticky.insert(modifier)
        }
    }
}

private struct TrackpadSurface: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 3
        view.addGestureRecognizer(pan)

        for (touches, action) in [
            (1, #selector(Coordinator.primaryTap(_:))),
            (2, #selector(Coordinator.secondaryTap(_:))),
            (3, #selector(Coordinator.middleTap(_:)))
        ] {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: action)
            tap.numberOfTouchesRequired = touches
            tap.require(toFail: pan)
            view.addGestureRecognizer(tap)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}

    final class Coordinator: NSObject {
        private var last: CGPoint = .zero

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                // UIKit begins a pan after a few points, so zeroing here
                // would replay that distance as a jump on the first change.
                last = gesture.translation(in: view)
            case .changed:
                let dx = translation.x - last.x
                let dy = translation.y - last.y
                last = translation
                if gesture.numberOfTouches >= 2 {
                    _ = kernarium_runtime_loader_send_mouse(
                        0, 0, 0,
                        Int32(-dy * 1.5), Int32(dx * 1.5)
                    )
                } else if abs(dx) >= 0.5 || abs(dy) >= 0.5 {
                    _ = kernarium_runtime_loader_send_mouse(
                        Int32(dx * 1.6), Int32(dy * 1.6), 0, 0, 0
                    )
                }
            default:
                last = .zero
            }
        }

        @objc func primaryTap(_ gesture: UITapGestureRecognizer) {
            VirtualKeySender.click(.primary)
        }

        @objc func secondaryTap(_ gesture: UITapGestureRecognizer) {
            VirtualKeySender.click(.secondary)
        }

        @objc func middleTap(_ gesture: UITapGestureRecognizer) {
            VirtualKeySender.click(.middle)
        }
    }
}

private enum VirtualKeySender {
    enum Button {
        case primary, secondary, middle
        var mask: UInt32 {
            switch self {
            case .primary: 1
            case .secondary: 2
            case .middle: 4
            }
        }
    }

    static func tap(_ code: UInt16, modifiers: Set<VirtualModifier>) {
        let codes = modifiers.map(code(for:))
        for modifier in codes { send(modifier, true) }
        send(code, true)
        send(code, false)
        for modifier in codes.reversed() { send(modifier, false) }
    }

    static func text(_ character: Character, modifiers: [VirtualModifier], shifted: Bool) {
        let codes = modifiers.map(code(for:))
        let stroke = LinuxKeyboard.stroke(for: character)
        // A shifted character such as "!" or "A" needs Shift even when the
        // person did not tap the sticky Shift key. Without it the guest sees
        // the unshifted key ("1" or "a").
        let needsShift = shifted || (stroke?.shifted ?? false)
        for modifier in codes { send(modifier, true) }
        if needsShift {
            send(LinuxKeyboard.leftShift, true)
        }
        if let stroke {
            send(stroke.code, true)
            send(stroke.code, false)
        } else if let ascii = character.asciiValue {
            send(UInt16(ascii), true)
            send(UInt16(ascii), false)
        }
        if needsShift {
            send(LinuxKeyboard.leftShift, false)
        }
        for modifier in codes.reversed() { send(modifier, false) }
    }

    static func click(_ button: Button) {
        _ = kernarium_runtime_loader_send_mouse(0, 0, button.mask, 0, 0)
        _ = kernarium_runtime_loader_send_mouse(0, 0, 0, 0, 0)
    }

    static func wheel(_ amount: Int32) {
        _ = kernarium_runtime_loader_send_mouse(0, 0, 0, amount, 0)
    }

    static func mouse(dx: Int32, dy: Int32, buttons: UInt32, wheel: Int32) {
        _ = kernarium_runtime_loader_send_mouse(dx, dy, buttons, wheel, 0)
    }

    private static func code(for modifier: VirtualModifier) -> UInt16 {
        switch modifier {
        case .control: LinuxKeyboard.leftControl
        case .option: LinuxKeyboard.leftAlt
        case .command: LinuxKeyboard.leftSuper
        case .shift: LinuxKeyboard.leftShift
        }
    }

    private static func send(_ code: UInt16, _ pressed: Bool) {
        kernarium_runtime_loader_send_key(code, pressed ? 1 : 0)
    }
}
