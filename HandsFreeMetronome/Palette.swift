import SwiftUI
import UIKit

/// The app's colours, and why.
///
/// Not My Tempo is read out of the corner of your eye: the phone sits on a stand
/// while your eyes stay on the music and your hands on the instrument, often in a
/// dim practice room. So the key colour is chosen for peripheral vision in low
/// light, not for decoration.
///
/// • `cue` (cyan) — every beat, and everything you can act on. Peripheral and
///   low-light vision is carried by the rods, which peak around 500 nm — this
///   blue-green — so a beat in cue colour is the one you catch without looking.
///   It is also the colour of the blue "cue lights" backstage that signal a
///   performer to go while keeping eyes adjusted to the dark.
/// • `beatRed` — the downbeat. Red sits opposite cyan on the colour wheel, so
///   beat 1 is the loudest thing on screen, and the pair stays apart for
///   red-green colour blindness (cyan reads blue, red reads brown) — the old
///   gold-vs-red pair collapsed into one yellow-brown there.
/// • Green stays reserved for "on the mark": in tune, perfect tap.
///
/// Light mode uses a deeper ink of the same hue so small text keeps ≥4.5:1 on white.
extension Color {
    static let cue = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x22 / 255, green: 0xD3 / 255, blue: 0xEE / 255, alpha: 1)   // #22D3EE
            : UIColor(red: 0x0A / 255, green: 0x7E / 255, blue: 0xA4 / 255, alpha: 1)   // #0A7EA4
    })

    /// Text and icons drawn on a solid `cue` fill.
    static let onCue = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? .black : .white
    })

    static let beatRed = Color(red: 0.90, green: 0.22, blue: 0.20)
}
