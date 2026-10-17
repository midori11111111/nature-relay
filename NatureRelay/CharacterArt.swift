import SwiftUI
import ImageIO

@MainActor
private enum CompanionThumbnailCache {
    static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func image(named name: String, size: CGFloat) -> UIImage? {
        let pixels = min(1024, max(96, Int(size * 3)))
        let key = "\(name):\(pixels)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        let url = RelayStore.mediaDirectory.appendingPathComponent(name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        images.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}

/// A saved AI illustration when available, with the offline companion as a fallback.
/// Generated artwork is read from the journal, so it remains available without a network.
struct CompanionArtwork: View {
    let observation: NatureObservation
    var size: CGFloat = 180

    var body: some View {
        if let name = observation.companionImageName, let image = CompanionThumbnailCache.image(named: name, size: size) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .background(.white, in: RoundedRectangle(cornerRadius: size * 0.12))
                .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
                .overlay(RoundedRectangle(cornerRadius: size * 0.12).stroke(.white, lineWidth: size * 0.018))
                .shadow(color: NRTheme.ink.opacity(0.13), radius: size * 0.025, x: 0, y: size * 0.035)
                .accessibilityLabel("AI illustration of \(observation.name)")
        } else if let image = SpeciesCharacterCatalog.artwork(for: observation, targetSize: size) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: NRTheme.ink.opacity(0.12), radius: size * 0.025, y: size * 0.025)
                .accessibilityLabel("\(SpeciesCharacterCatalog.assetInfo(for: observation).title), illustrated companion for \(observation.commonName ?? observation.name)")
        } else {
            NatureCharacter(kind: observation.kind, size: size, tint: Color(nrHex: observation.paletteHex))
        }
    }
}

/// Original, locally drawn companions. No network or purchased artwork required.
struct NatureCharacter: View {
    let kind: NatureKind
    var size: CGFloat = 180
    var tint: Color? = nil

    var body: some View {
        Canvas { context, canvasSize in
            context.scaleBy(x: canvasSize.width / 200, y: canvasSize.height / 200)
            switch kind {
            case .flower: drawFlower(&context)
            case .tree: drawTree(&context)
            case .bird: drawBird(&context)
            case .butterfly: drawButterfly(&context)
            case .plant: drawPlant(&context)
            case .other: drawSeed(&context)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: NRTheme.ink.opacity(0.13), radius: size * 0.025, x: 0, y: size * 0.035)
        .accessibilityLabel("\(kind.friendName), an original \(kind.title.lowercased()) companion")
    }

    private func paint(_ path: Path, _ color: Color, _ c: inout GraphicsContext, border: Bool = true) {
        if border { c.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)) }
        c.fill(path, with: .color(color))
    }

    private func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
    }

    private func face(_ c: inout GraphicsContext, x: CGFloat = 100, y: CGFloat = 108, gap: CGFloat = 15) {
        let ink = NRTheme.ink
        c.fill(oval(x - gap - 2.8, y - 5, 5.6, 8), with: .color(ink))
        c.fill(oval(x + gap - 2.8, y - 5, 5.6, 8), with: .color(ink))
        c.fill(oval(x - gap - 12, y + 6, 14, 7), with: .color(Color(red: 0.97, green: 0.51, blue: 0.52).opacity(0.7)))
        c.fill(oval(x + gap - 2, y + 6, 14, 7), with: .color(Color(red: 0.97, green: 0.51, blue: 0.52).opacity(0.7)))
        var mouth = Path()
        mouth.move(to: CGPoint(x: x - 4, y: y + 9))
        mouth.addQuadCurve(to: CGPoint(x: x + 4, y: y + 9), control: CGPoint(x: x, y: y + 15))
        c.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    private func leaf(_ origin: CGPoint, tip: CGPoint, breadth: CGFloat) -> Path {
        var p = Path()
        p.move(to: origin)
        let mx = (origin.x + tip.x) / 2
        let my = (origin.y + tip.y) / 2
        let dx = tip.x - origin.x
        let dy = tip.y - origin.y
        let length = max(hypot(dx, dy), 1)
        let nx = -dy / length * breadth
        let ny = dx / length * breadth
        p.addQuadCurve(to: tip, control: CGPoint(x: mx + nx, y: my + ny))
        p.addQuadCurve(to: origin, control: CGPoint(x: mx - nx, y: my - ny))
        return p
    }

    private func drawFlower(_ c: inout GraphicsContext) {
        var stem = Path()
        stem.move(to: CGPoint(x: 101, y: 117)); stem.addQuadCurve(to: CGPoint(x: 103, y: 175), control: CGPoint(x: 89, y: 150))
        c.stroke(stem, with: .color(.white), style: StrokeStyle(lineWidth: 17, lineCap: .round))
        c.stroke(stem, with: .color(Color(red: 0.31, green: 0.57, blue: 0.31)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        paint(leaf(CGPoint(x: 101, y: 157), tip: CGPoint(x: 145, y: 140), breadth: 17), Color(red: 0.51, green: 0.72, blue: 0.39), &c)
        paint(leaf(CGPoint(x: 99, y: 164), tip: CGPoint(x: 61, y: 145), breadth: 15), Color(red: 0.39, green: 0.62, blue: 0.35), &c)
        let petal = tint ?? Color(red: 0.97, green: 0.64, blue: 0.65)
        for i in 0..<7 {
            let angle = Double(i) * .pi * 2 / 7 - .pi / 2
            let x = 100 + cos(angle) * 35
            let y = 88 + sin(angle) * 35
            paint(oval(x - 23, y - 25, 46, 50), i % 2 == 0 ? petal : (tint?.opacity(0.88) ?? Color(red: 0.95, green: 0.54, blue: 0.59)), &c)
        }
        paint(oval(65, 54, 70, 70), Color(red: 1, green: 0.87, blue: 0.48), &c, border: false)
        face(&c, y: 86, gap: 13)
    }

    private func drawTree(_ c: inout GraphicsContext) {
        var trunk = Path(roundedRect: CGRect(x: 79, y: 106, width: 43, height: 68), cornerRadius: 18)
        trunk.addEllipse(in: CGRect(x: 68, y: 159, width: 27, height: 18))
        trunk.addEllipse(in: CGRect(x: 107, y: 159, width: 27, height: 18))
        paint(trunk, Color(red: 0.71, green: 0.51, blue: 0.32), &c)
        var crown = Path()
        crown.move(to: CGPoint(x: 45, y: 113))
        crown.addCurve(to: CGPoint(x: 42, y: 69), control1: CGPoint(x: 21, y: 103), control2: CGPoint(x: 24, y: 76))
        crown.addCurve(to: CGPoint(x: 76, y: 40), control1: CGPoint(x: 38, y: 44), control2: CGPoint(x: 57, y: 31))
        crown.addCurve(to: CGPoint(x: 128, y: 39), control1: CGPoint(x: 85, y: 15), control2: CGPoint(x: 115, y: 15))
        crown.addCurve(to: CGPoint(x: 160, y: 73), control1: CGPoint(x: 155, y: 30), control2: CGPoint(x: 175, y: 51))
        crown.addCurve(to: CGPoint(x: 155, y: 116), control1: CGPoint(x: 183, y: 87), control2: CGPoint(x: 176, y: 111))
        crown.addCurve(to: CGPoint(x: 45, y: 113), control1: CGPoint(x: 126, y: 141), control2: CGPoint(x: 68, y: 135))
        paint(crown, tint ?? Color(red: 0.48, green: 0.69, blue: 0.39), &c)
        c.fill(oval(66, 47, 17, 11), with: .color(Color.white.opacity(0.22)))
        c.fill(oval(122, 80, 12, 9), with: .color(Color.white.opacity(0.2)))
        face(&c, y: 93, gap: 17)
    }

    private func drawBird(_ c: inout GraphicsContext) {
        var foot = Path()
        foot.move(to: CGPoint(x: 83, y: 150)); foot.addLine(to: CGPoint(x: 79, y: 169)); foot.addLine(to: CGPoint(x: 68, y: 171))
        foot.move(to: CGPoint(x: 117, y: 151)); foot.addLine(to: CGPoint(x: 122, y: 169)); foot.addLine(to: CGPoint(x: 134, y: 171))
        c.stroke(foot, with: .color(.white), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
        c.stroke(foot, with: .color(Color(red: 0.88, green: 0.61, blue: 0.31)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        var body = Path()
        body.move(to: CGPoint(x: 45, y: 125))
        body.addCurve(to: CGPoint(x: 65, y: 49), control1: CGPoint(x: 34, y: 102), control2: CGPoint(x: 40, y: 68))
        body.addCurve(to: CGPoint(x: 145, y: 65), control1: CGPoint(x: 88, y: 28), control2: CGPoint(x: 131, y: 38))
        body.addCurve(to: CGPoint(x: 157, y: 127), control1: CGPoint(x: 161, y: 85), control2: CGPoint(x: 145, y: 114))
        body.addLine(to: CGPoint(x: 177, y: 113))
        body.addQuadCurve(to: CGPoint(x: 163, y: 147), control: CGPoint(x: 177, y: 140))
        body.addCurve(to: CGPoint(x: 45, y: 125), control1: CGPoint(x: 135, y: 179), control2: CGPoint(x: 61, y: 165))
        paint(body, tint ?? Color(red: 0.48, green: 0.71, blue: 0.79), &c)
        c.fill(oval(68, 105, 64, 48), with: .color(Color(red: 0.86, green: 0.92, blue: 0.88)))
        var tuft = Path()
        tuft.move(to: CGPoint(x: 91, y: 43)); tuft.addQuadCurve(to: CGPoint(x: 79, y: 24), control: CGPoint(x: 71, y: 26))
        tuft.addQuadCurve(to: CGPoint(x: 103, y: 42), control: CGPoint(x: 103, y: 22))
        paint(tuft, tint ?? Color(red: 0.48, green: 0.71, blue: 0.79), &c)
        face(&c, y: 87, gap: 17)
        var beak = Path()
        beak.move(to: CGPoint(x: 95, y: 98)); beak.addLine(to: CGPoint(x: 105, y: 98)); beak.addQuadCurve(to: CGPoint(x: 100, y: 108), control: CGPoint(x: 107, y: 104)); beak.closeSubpath()
        c.fill(beak, with: .color(Color(red: 0.97, green: 0.69, blue: 0.32)))
    }

    private func drawButterfly(_ c: inout GraphicsContext) {
        for side: CGFloat in [-1, 1] {
            var wing = Path()
            wing.move(to: CGPoint(x: 100, y: 105))
            wing.addCurve(to: CGPoint(x: 100 + side * 64, y: 43), control1: CGPoint(x: 100 + side * 24, y: 35), control2: CGPoint(x: 100 + side * 65, y: 22))
            wing.addCurve(to: CGPoint(x: 100 + side * 31, y: 113), control1: CGPoint(x: 100 + side * 92, y: 78), control2: CGPoint(x: 100 + side * 61, y: 116))
            wing.addCurve(to: CGPoint(x: 100 + side * 49, y: 161), control1: CGPoint(x: 100 + side * 70, y: 107), control2: CGPoint(x: 100 + side * 73, y: 149))
            wing.addCurve(to: CGPoint(x: 100, y: 126), control1: CGPoint(x: 100 + side * 20, y: 180), control2: CGPoint(x: 100 + side * 8, y: 148))
            wing.closeSubpath()
            paint(wing, tint ?? Color(red: 0.75, green: 0.64, blue: 0.83), &c)
            c.fill(oval(100 + side * 48 - 12, 65, 24, 31), with: .color(Color(red: 0.92, green: 0.80, blue: 0.88)))
            c.fill(oval(100 + side * 36 - 8, 132, 16, 16), with: .color(Color(red: 1, green: 0.85, blue: 0.57)))
        }
        var antenna = Path()
        antenna.move(to: CGPoint(x: 94, y: 82)); antenna.addQuadCurve(to: CGPoint(x: 82, y: 59), control: CGPoint(x: 94, y: 61))
        antenna.move(to: CGPoint(x: 106, y: 82)); antenna.addQuadCurve(to: CGPoint(x: 118, y: 59), control: CGPoint(x: 106, y: 61))
        c.stroke(antenna, with: .color(NRTheme.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        paint(Path(roundedRect: CGRect(x: 82, y: 79, width: 36, height: 76), cornerRadius: 18), Color(red: 0.98, green: 0.81, blue: 0.49), &c)
        face(&c, y: 100, gap: 8)
    }

    private func drawPlant(_ c: inout GraphicsContext) {
        paint(leaf(CGPoint(x: 102, y: 85), tip: CGPoint(x: 44, y: 38), breadth: 26), Color(red: 0.44, green: 0.65, blue: 0.32), &c)
        paint(leaf(CGPoint(x: 98, y: 82), tip: CGPoint(x: 151, y: 30), breadth: 28), Color(red: 0.65, green: 0.77, blue: 0.36), &c)
        var body = Path()
        body.move(to: CGPoint(x: 100, y: 72))
        body.addCurve(to: CGPoint(x: 154, y: 133), control1: CGPoint(x: 115, y: 95), control2: CGPoint(x: 153, y: 95))
        body.addCurve(to: CGPoint(x: 100, y: 174), control1: CGPoint(x: 158, y: 163), control2: CGPoint(x: 127, y: 178))
        body.addCurve(to: CGPoint(x: 46, y: 133), control1: CGPoint(x: 73, y: 178), control2: CGPoint(x: 42, y: 163))
        body.addCurve(to: CGPoint(x: 100, y: 72), control1: CGPoint(x: 47, y: 95), control2: CGPoint(x: 85, y: 95))
        paint(body, tint ?? Color(red: 0.79, green: 0.85, blue: 0.53), &c)
        c.fill(oval(65, 109, 12, 7), with: .color(.white.opacity(0.45)))
        face(&c, y: 130, gap: 17)
    }

    private func drawSeed(_ c: inout GraphicsContext) {
        paint(leaf(CGPoint(x: 101, y: 63), tip: CGPoint(x: 141, y: 27), breadth: 20), Color(red: 0.51, green: 0.69, blue: 0.37), &c)
        paint(oval(50, 57, 100, 114), tint ?? Color(red: 0.90, green: 0.72, blue: 0.43), &c)
        c.fill(oval(68, 74, 17, 10), with: .color(.white.opacity(0.35)))
        face(&c, y: 117, gap: 17)
    }
}

extension Color {
    /// Accepts six-digit RGB, with or without a leading #. Invalid/missing colors stay nil.
    init?(nrHex: String?) {
        guard let nrHex else { return nil }
        let hex = nrHex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}
