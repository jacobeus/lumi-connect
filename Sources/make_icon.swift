// Renders the 1024 px app icon: an octave of piano keys on a rounded gradient tile.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(calibratedRed: 0.42, green: 0.25, blue: 0.95, alpha: 1),
           ending: NSColor(calibratedRed: 0.10, green: 0.70, blue: 0.95, alpha: 1))!.draw(in: tile, angle: -60)

let keys = NSRect(x: 232, y: 292, width: 560, height: 440)
let whiteWidth = keys.width / 7
NSColor.white.setFill()
for i in 0..<7 {
    NSBezierPath(roundedRect: NSRect(x: keys.minX + CGFloat(i) * whiteWidth + 6, y: keys.minY,
                                     width: whiteWidth - 12, height: keys.height), xRadius: 18, yRadius: 18).fill()
}
// Black keys sit on the boundaries after C, D, F, G and A.
NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
for boundary in [1, 2, 4, 5, 6] {
    let width = whiteWidth * 0.6
    NSBezierPath(roundedRect: NSRect(x: keys.minX + CGFloat(boundary) * whiteWidth - width / 2, y: keys.minY + keys.height * 0.4,
                                     width: width, height: keys.height * 0.6), xRadius: 14, yRadius: 14).fill()
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
