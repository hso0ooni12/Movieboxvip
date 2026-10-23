import AppKit

let output = CommandLine.arguments[1]
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(colors: [
    NSColor(calibratedRed: 0.016, green: 0.16, blue: 0.18, alpha: 1),
    NSColor(calibratedRed: 0.018, green: 0.035, blue: 0.064, alpha: 1)
])!.draw(in: bounds, angle: 320)

let glow = NSBezierPath(ovalIn: NSRect(x: 80, y: 250, width: 860, height: 860))
NSColor(calibratedRed: 0.12, green: 0.83, blue: 0.71, alpha: 0.16).setFill()
glow.fill()

let plate = NSBezierPath(roundedRect: NSRect(x: 186, y: 193, width: 652, height: 638),
                         xRadius: 156, yRadius: 156)
NSColor(calibratedRed: 0.05, green: 0.15, blue: 0.18, alpha: 0.92).setFill()
plate.fill()
NSColor(calibratedRed: 0.32, green: 0.94, blue: 0.82, alpha: 0.55).setStroke()
plate.lineWidth = 6
plate.stroke()

let triangle = NSBezierPath()
triangle.move(to: NSPoint(x: 398, y: 336))
triangle.line(to: NSPoint(x: 704, y: 512))
triangle.line(to: NSPoint(x: 398, y: 688))
triangle.close()
NSGradient(colors: [
    NSColor(calibratedRed: 0.54, green: 1, blue: 0.9, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.74, alpha: 1)
])!.draw(in: triangle, angle: 220)

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Icon rendering failed")
}
try png.write(to: URL(fileURLWithPath: output))
