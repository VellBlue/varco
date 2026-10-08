// Varco icon: a glowing arched gateway (wine-colored pixel dithering) on a paper background.
import AppKit
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a) }
// background: macOS-style rounded square
let bg = CGRect(x: 100, y: 100, width: 824, height: 824)
let bgPath = CGPath(roundedRect: bg, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: col(0x000000, 0.28))
ctx.addPath(bgPath); ctx.setFillColor(col(0xF3F0EA)); ctx.fillPath(); ctx.restoreGState()
ctx.saveGState(); ctx.addPath(bgPath); ctx.clip()
let g = CGGradient(colorsSpace: cs, colors: [col(0xF7F4EE), col(0xE6DFD5)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// light coming out of the gateway onto the floor
let floor = CGGradient(colorsSpace: cs, colors: [col(0xC4486E, 0.55), col(0xC4486E, 0)] as CFArray, locations: [0, 1])!
ctx.saveGState(); ctx.translateBy(x: 512, y: 236); ctx.scaleBy(x: 1, y: 0.28)
ctx.drawRadialGradient(floor, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 360, options: []); ctx.restoreGState()
// the arch
let aw: CGFloat = 330, ah: CGFloat = 520, ax = 512 - aw / 2, ay: CGFloat = 250
let arch = CGMutablePath()
arch.move(to: CGPoint(x: ax, y: ay)); arch.addLine(to: CGPoint(x: ax, y: ay + ah - aw / 2))
arch.addArc(center: CGPoint(x: 512, y: ay + ah - aw / 2), radius: aw / 2, startAngle: .pi, endAngle: 0, clockwise: true)
arch.addLine(to: CGPoint(x: ax + aw, y: ay)); arch.closeSubpath()
ctx.saveGState(); ctx.addPath(arch); ctx.clip()
// ordered 8x8 dithering between three wine tones (light at the bottom, dark at the top)
var B = [[0]]; for _ in 0..<3 { let n = B.count; var R = Array(repeating: Array(repeating: 0, count: 2 * n), count: 2 * n)
  for y in 0..<(2 * n) { for x in 0..<(2 * n) { R[y][x] = B[y % n][x % n] * 4 + [[0, 2], [3, 1]][y / n][x / n] } }; B = R }
let tones: [UInt32] = [0x3A0718, 0x7A1131, 0xC4486E, 0xF1C4CF]
let cell: CGFloat = 14
var yy = ay; var row = 0
while yy < ay + ah { var xx = ax; var colI = 0
  while xx < ax + aw { let p = (yy - ay) / ah, dx = abs((xx + cell / 2) - 512) / (aw / 2)
    let L = max(0, min(1, 1 - p * 0.95 + 0.25 - dx * dx * 0.35)) * 0.999 * CGFloat(tones.count - 1)
    let b = Int(L), th = (CGFloat(B[row % 8][colI % 8]) + 0.5) / 64
    let i = min(tones.count - 1, b + ((L - CGFloat(b)) > th ? 1 : 0))
    ctx.setFillColor(col(tones[i])); ctx.fill(CGRect(x: xx, y: yy, width: cell, height: cell))
    xx += cell; colI += 1 }
  yy += cell; row += 1 }
ctx.restoreGState()
// the arch's frame
ctx.addPath(arch); ctx.setStrokeColor(col(0x17141A)); ctx.setLineWidth(22); ctx.setLineJoin(.round); ctx.strokePath()
ctx.restoreGState()
let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon_1024.png"))
print("ok")
