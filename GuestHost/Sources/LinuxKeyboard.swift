// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

enum LinuxKeyboard {
    struct Stroke {
        let code: UInt16
        let shifted: Bool
    }

    static let escape: UInt16 = 1
    static let tab: UInt16 = 15
    static let backspace: UInt16 = 14
    static let enter: UInt16 = 28
    static let leftControl: UInt16 = 29
    static let leftShift: UInt16 = 42
    static let leftAlt: UInt16 = 56
    static let leftSuper: UInt16 = 125
    static let space: UInt16 = 57
    static let left: UInt16 = 105
    static let right: UInt16 = 106
    static let up: UInt16 = 103
    static let down: UInt16 = 108

    static func stroke(for character: Character) -> Stroke? {
        if character == "\n" || character == "\r" {
            return Stroke(code: 28, shifted: false)
        }
        if character == "\t" {
            return Stroke(code: 15, shifted: false)
        }
        if character == " " {
            return Stroke(code: 57, shifted: false)
        }

        let rows: [(String, [UInt16])] = [
            ("1234567890-=", Array(2...13)),
            ("qwertyuiop[]", Array(16...27)),
            ("asdfghjkl;'`", Array(30...41)),
            ("\\zxcvbnm,./", Array(43...53)),
        ]
        let shiftedRows = [
            "!@#$%^&*()_+",
            "QWERTYUIOP{}",
            "ASDFGHJKL:\"~",
            "|ZXCVBNM<>?",
        ]
        for (rowIndex, row) in rows.enumerated() {
            if let index = row.0.firstIndex(of: character) {
                let offset = row.0.distance(from: row.0.startIndex, to: index)
                return Stroke(code: row.1[offset], shifted: false)
            }
            let shifted = shiftedRows[rowIndex]
            if let index = shifted.firstIndex(of: character) {
                let offset = shifted.distance(from: shifted.startIndex, to: index)
                return Stroke(code: row.1[offset], shifted: true)
            }
        }
        return nil
    }
}
