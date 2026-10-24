import AppKit
import Foundation

let input = URL(fileURLWithPath: "Baduy/Asset/ciboleger-dem.png")
let output = URL(fileURLWithPath: "Baduy/Asset/ciboleger-dem.json")
guard let image = NSImage(contentsOf: input), let rep = NSBitmapImageRep(data: image.tiffRepresentation!) else { fatalError("DEM PNG unreadable") }
let w = rep.pixelsWide, h = rep.pixelsHigh
var values = [Int](); values.reserveCapacity(w * h)
for y in 0..<h { for x in 0..<w {
    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    let r = c.redComponent > 1 ? c.redComponent / 255 : c.redComponent
    let g = c.greenComponent > 1 ? c.greenComponent / 255 : c.greenComponent
    let b = c.blueComponent > 1 ? c.blueComponent / 255 : c.blueComponent
    let meters = (r * 255) * 256 + (g * 255) + (b * 255) / 256 - 32768
    values.append(Int((meters * 100).rounded()))
} }
let object: [String: Any] = ["width": w, "height": h, "scale": 100, "encoding": "centimeters", "values": values]
let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
try data.write(to: output)
print("wrote \(output.path)")
