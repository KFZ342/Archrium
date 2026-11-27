// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI

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
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.28))
                Text("Drag to move · Tap to click")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !dragging {
                                    dragging = true
                                    lastTranslation = .zero
                                }
                                let dx = value.translation.width - lastTranslation.width
                                let dy = value.translation.height - lastTranslation.height
                                lastTranslation = value.translation
                                if abs(dx) >= 0.5 || abs(dy) >= 0.5 {
                                    VirtualKeySender.mouse(
                                        dx: Int32(dx * 1.6), dy: Int32(dy * 1.6),
                                        buttons: 0, wheel: 0
                                    )
                                }
                            }
                            .onEnded { value in
                                let moved = abs(value.translation.width) + abs(value.translation.height)
                                if moved < 8 {
                                    VirtualKeySender.click(.primary)
                                }
                                dragging = false
                            }
                    )
            }
            .frame(height: 150)

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
        for modifier in codes { send(modifier, true) }
        if shifted && !character.isUppercase {
            send(LinuxKeyboard.leftShift, true)
        }
        if let stroke = LinuxKeyboard.stroke(for: character) {
            send(stroke.code, true)
            send(stroke.code, false)
        } else if let ascii = character.asciiValue {
            send(UInt16(ascii), true)
            send(UInt16(ascii), false)
        }
        if shifted && !character.isUppercase {
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
