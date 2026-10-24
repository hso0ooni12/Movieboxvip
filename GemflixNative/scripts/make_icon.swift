import AppKit

let output = CommandLine.arguments[1]
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(colors: [
    NSColor(calibratedRed: 0.27, green: 0.035, blue: 0.115, alpha: 1),
    NSColor(calibratedRed: 0.018, green: 0.01, blue: 0.022, alpha: 1)
])!.draw(in: bounds, angle: 320)

let glow = NSBezierPath(ovalIn: NSRect(x: 80, y: 250, width: 860, height: 860))
NSColor(calibratedRed: 1, green: 0.13, blue: 0.32, alpha: 0.17).setFill()
glow.fill()

let plate = NSBezierPath(roundedRect: NSRect(x: 186, y: 193, width: 652, height: 638),
                         xRadius: 156, yRadius: 156)
NSColor(calibratedRed: 0.16, green: 0.035, blue: 0.09, alpha: 0.95).setFill()
plate.fill()
NSColor(calibratedRed: 1, green: 0.35, blue: 0.48, alpha: 0.55).setStroke()
plate.lineWidth = 6
plate.stroke()

let triangle = NSBezierPath()
triangle.move(to: NSPoint(x: 398, y: 336))
triangle.line(to: NSPoint(x: 704, y: 512))
triangle.line(to: NSPoint(x: 398, y: 688))
triangle.close()
NSGradient(colors: [
    NSColor(calibratedRed: 1, green: 0.43, blue: 0.52, alpha: 1),
    NSColor(calibratedRed: 0.83, green: 0.11, blue: 0.27, alpha: 1)
])!.draw(in: triangle, angle: 220)

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Icon rendering failed")
}
try png.write(to: URL(fileURLWithPath: output))
