// Draws the File Sync app icon at 1024 px. Run: swift make_icon.swift <out.png>
// Pastel sticker look: soft lavender-to-peach gradient, chunky outlined folders, a lightning sync bolt
// from master to target, and a hazard-tape ribbon reading LOCAL across the top-right corner.
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext
func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
func withShadow(_ color: NSColor, blur: CGFloat, dy: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowColor = color; s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: dy); s.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

let ink = hex(0x4A3358)        // deep muted plum outline colour
let cream = hex(0xFCFBF8)      // warm off-white, never pure white
let mint = hex(0xB8EBD0)       // target folder
let sky = hex(0xBFD8F6)        // master folder
let butter = hex(0xFFE9A3)     // tape + confetti
let blush = hex(0xF7C6DC)

// macOS icon grid: 824 pt body centred in 1024, soft drop shadow.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
withShadow(hex(0x4A3358, 0.28), blur: 28, dy: -12) { hex(0xC9B6F2).setFill(); squircle.fill() }

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
// Soft diagonal gradient: lavender -> blush pink -> peach.
NSGradient(colors: [hex(0xC6B3F5), hex(0xF3BFDD), hex(0xFFD2B0)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: body, angle: -45)
// Playful confetti dots in the background.
for (x, y, r, c) in [(210, 800, 16, cream), (300, 860, 9, butter), (180, 690, 8, mint),
                     (840, 230, 14, butter), (760, 160, 9, cream), (870, 330, 7, mint),
                     (215, 210, 11, butter), (330, 150, 7, cream)] as [(CGFloat, CGFloat, CGFloat, NSColor)] {
    c.withAlphaComponent(0.95).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
}
// Subtle top sheen.
NSGradient(starting: hex(0xFCFBF8, 0.22), ending: hex(0xFCFBF8, 0))!.draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)

// Chunky outlined folder (tab + body), sticker style.
func folder(_ r: NSRect, fill: NSColor, shade: NSColor, tilt: CGFloat, tabRight: Bool = false) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: r.midX, yBy: r.midY); t.rotate(byDegrees: tilt); t.translateX(by: -r.midX, yBy: -r.midY)
    t.concat()
    let tab = NSBezierPath(roundedRect: NSRect(x: tabRight ? r.maxX - 6 - r.width * 0.46 : r.minX + 6, y: r.maxY - 70, width: r.width * 0.46, height: 110), xRadius: 32, yRadius: 32)
    let main = NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height - 30), xRadius: 44, yRadius: 44)
    let shape = NSBezierPath(); shape.append(tab); shape.append(main)
    shape.windingRule = .nonZero
    // Hard offset "sticker" shadow.
    NSGraphicsContext.saveGraphicsState()
    let off = NSAffineTransform(); off.translateX(by: 14, yBy: -18); off.concat()
    ink.withAlphaComponent(0.32).setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    ink.setStroke(); tab.lineWidth = 22; main.lineWidth = 22
    shade.setFill(); tab.fill(); tab.stroke()
    fill.setFill(); main.fill()
    // Front flap highlight line.
    let flap = NSBezierPath(roundedRect: NSRect(x: r.minX + 36, y: r.maxY - 92, width: r.width - 72, height: 16), xRadius: 8, yRadius: 8)
    cream.withAlphaComponent(0.6).setFill(); flap.fill()
    main.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

// Master (baby blue, upper left) and target (mint, lower right).
folder(NSRect(x: 150, y: 420, width: 330, height: 250), fill: sky, shade: hex(0x9EC0EC), tilt: 5)
folder(NSRect(x: 470, y: 190, width: 330, height: 250), fill: mint, shade: hex(0x8FD6B2), tilt: -5, tabRight: true)

// Lightning-bolt sync arrow pointing from master down-right into target.
let bolt = NSBezierPath()
let pts: [(CGFloat, CGFloat)] = [
    (-60, 190), (80, 190), (25, 80), (95, 80), (50, -30), (118, -30),   // right side zig
    (0, -200),                                                         // arrow tip
    (-118, -30), (-40, -30), (-25, 40), (-95, 40)                      // left side back up
]
bolt.move(to: NSPoint(x: pts[0].0, y: pts[0].1))
for p in pts.dropFirst() { bolt.line(to: NSPoint(x: p.0, y: p.1)) }
bolt.close()
bolt.lineJoinStyle = .round
let boltT = NSAffineTransform(); boltT.translateX(by: 478, yBy: 468); boltT.rotate(byDegrees: 36); boltT.scale(by: 0.84)
bolt.transform(using: boltT as AffineTransform)
NSGraphicsContext.saveGraphicsState()
let off = NSAffineTransform(); off.translateX(by: 14, yBy: -18); off.concat()
ink.withAlphaComponent(0.32).setFill(); bolt.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: hex(0xFFF0B3), ending: hex(0xFFD77A))!.draw(in: bolt, angle: -90)
ink.setStroke(); bolt.lineWidth = 22; bolt.stroke()

// Hazard-tape ribbon across the top-right corner reading LOCAL.
NSGraphicsContext.saveGraphicsState()
cg.translateBy(x: 730, y: 730)
cg.rotate(by: -.pi / 4)
let tapeH: CGFloat = 150
let tape = NSRect(x: -420, y: -tapeH / 2, width: 840, height: tapeH)
withShadow(hex(0x4A3358, 0.30), blur: 18, dy: -8) { butter.setFill(); NSBezierPath(rect: tape).fill() }
// Soft lilac diagonal stripes on both ends, leaving the middle clear for text.
NSGraphicsContext.saveGraphicsState()
NSBezierPath(rect: tape).addClip()
hex(0xAE95DC).setFill()
var x: CGFloat = -440
while x < 440 {
    if abs(x + 30) > 200 {
        let s = NSBezierPath()
        s.move(to: NSPoint(x: x, y: -tapeH / 2)); s.line(to: NSPoint(x: x + 30, y: -tapeH / 2))
        s.line(to: NSPoint(x: x + 30 + tapeH * 0.7, y: tapeH / 2)); s.line(to: NSPoint(x: x + tapeH * 0.7, y: tapeH / 2))
        s.close(); s.fill()
    }
    x += 60
}
NSGraphicsContext.restoreGraphicsState()
// Edge lines.
ink.setFill()
NSBezierPath(rect: NSRect(x: tape.minX, y: tape.maxY - 10, width: tape.width, height: 10)).fill()
NSBezierPath(rect: NSRect(x: tape.minX, y: tape.minY, width: tape.width, height: 10)).fill()
let font = NSFont.systemFont(ofSize: 92, weight: .black)
let para = NSMutableParagraphStyle(); para.alignment = .center
let text = NSAttributedString(string: "LOCAL", attributes: [.font: font, .foregroundColor: ink, .kern: 6, .paragraphStyle: para])
let ts = text.size()
text.draw(in: NSRect(x: -ts.width / 2 - 2, y: -ts.height / 2 + 2, width: ts.width + 4, height: ts.height))
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()   // squircle clip

// Thin inner rim to crisp the edge.
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: 182, yRadius: 182)
hex(0xFCFBF8, 0.18).setStroke(); rim.lineWidth = 6; rim.stroke()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
