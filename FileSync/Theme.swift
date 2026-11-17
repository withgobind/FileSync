import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Warm neutrals (never pure white) with one accent per difference kind.
enum Theme {
    static let canvas = dynamic(light: 0xF6F4EF, dark: 0x1C1B19)
    static let card = dynamic(light: 0xFCFBF8, dark: 0x262523)
    static let stroke = dynamic(light: 0xE4E0D8, dark: 0x3A3835)
    static let ink = dynamic(light: 0x23211E, dark: 0xEDEAE4)
    static let muted = dynamic(light: 0x86817A, dark: 0x9A958D)
    /// Pastel periwinkle for the main action; its text uses `onAccent` (deep ink) so it stays legible.
    static let accent = dynamic(light: 0xB7C8F4, dark: 0x8FA6E6)
    static let onAccent = dynamic(light: 0x1E2A4A, dark: 0x141B30)
    static let lavender = dynamic(light: 0xDCD0F5, dark: 0x4A4170)

    /// Readable (deeper) tone of each kind, for text and small glyphs.
    static func color(_ kind: DiffKind) -> Color {
        switch kind {
        case .onlyInSource: dynamic(light: 0x3E8E66, dark: 0x8FD6B0)
        case .onlyInTarget: dynamic(light: 0xC0703A, dark: 0xF2B48A)
        case .changed: dynamic(light: 0x4C6FC4, dark: 0xA9BFF2)
        }
    }

    /// Pastel fill of each kind, for badges, chips and buttons.
    static func pastel(_ kind: DiffKind) -> Color {
        switch kind {
        case .onlyInSource: dynamic(light: 0xC6EBD6, dark: 0x2F5A45)
        case .onlyInTarget: dynamic(light: 0xFAD6BE, dark: 0x6A4330)
        case .changed: dynamic(light: 0xCFDCF8, dark: 0x34456F)
        }
    }

    /// Ink used on a pastel fill.
    static func onPastel(_ kind: DiffKind) -> Color {
        switch kind {
        case .onlyInSource: dynamic(light: 0x23543B, dark: 0xD8F3E4)
        case .onlyInTarget: dynamic(light: 0x6E3A17, dark: 0xFDE6D6)
        case .changed: dynamic(light: 0x23386E, dark: 0xDDE7FB)
        }
    }

    static func glyph(_ kind: DiffKind) -> String {
        switch kind {
        case .onlyInSource: "plus"
        case .onlyInTarget: "minus"
        case .changed: "arrow.triangle.2.circlepath"
        }
    }

    static func symbol(_ kind: DiffKind) -> String {
        switch kind {
        case .onlyInSource: "plus.circle.fill"
        case .onlyInTarget: "minus.circle.fill"
        case .changed: "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
        })
    }
}

enum Format {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func date(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits).hour().minute())
    }

    static func count(_ n: Int, _ noun: String) -> String {
        "\(n.formatted()) \(noun)\(n == 1 ? "" : "s")"
    }
}

/// Real Finder icons: by file type for list rows, by path for chosen folders and their drives.
@MainActor
enum FinderIcon {
    private static var cache: [String: NSImage] = [:]

    static func forItem(name: String, isDirectory: Bool) -> NSImage {
        let ext = isDirectory ? "/" : (name as NSString).pathExtension.lowercased()
        if let hit = cache[ext] { return hit }
        let type: UTType = isDirectory ? .folder : (UTType(filenameExtension: ext) ?? .data)
        let image = NSWorkspace.shared.icon(for: type)
        cache[ext] = image
        return image
    }

    static func forPath(_ url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}

/// The one main action on a screen. Draws its own colors so it never fades into the background
/// (the system prominent style goes near-invisible on these warm neutrals when the window isn't key).
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var ink: Color = Theme.onAccent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? ink : Theme.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isEnabled ? tint : Theme.stroke)
                    .brightness(configuration.isPressed ? -0.08 : 0)
            )
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ink.opacity(isEnabled ? 0.12 : 0)))
            .shadow(color: isEnabled ? tint.opacity(0.35) : .clear, radius: 3, y: 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primary(_ tint: Color, ink: Color = Theme.onAccent) -> PrimaryButtonStyle { PrimaryButtonStyle(tint: tint, ink: ink) }
}


/// A pastel circle with the kind's glyph: green plus, peach minus, blue arrows.
struct KindBadge: View {
    let kind: DiffKind
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: Theme.glyph(kind))
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(Theme.onPastel(kind))
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.pastel(kind)))
    }
}
