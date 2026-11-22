import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI

enum PaperTextureKind: String, Codable, Sendable {
    case cotton
    case washi
    case kraft
    case parchment
    case linen
    case watercolor
    case dotted
    case graphite
}

struct ProceduralPaperTexture: PaperTexture, Equatable {
    let id: String
    let kind: PaperTextureKind
    let isDarkSurface: Bool

    var blendMode: BlendMode {
        isDarkSurface ? .screen : .multiply
    }

    var baseOpacity: Double {
        switch kind {
        case .cotton: return 0.35
        case .washi: return 0.45
        case .kraft: return 0.55
        case .parchment: return 0.55
        case .linen: return 0.45
        case .watercolor: return 0.50
        case .dotted: return 0.55
        case .graphite: return 0.24
        }
    }
}

actor PaperTextureCache {
    static let shared = PaperTextureCache()

    private let tileSize = 512
    private var memoryCache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private var diskCacheDir: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches.appendingPathComponent("com.farrukh.voicetype/PaperTextures_v1", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func cachedTileSync(for id: String) -> NSImage? {
        memoryCache[id]
    }

    func tile(for texture: ProceduralPaperTexture) async -> NSImage? {
        if let cached = memoryCache[texture.id] {
            return cached
        }
        if let existingTask = inFlight[texture.id] {
            return await existingTask.value
        }

        let task = Task.detached(priority: .utility) { () -> NSImage? in
            if let diskImage = self.loadFromDisk(id: texture.id) {
                return diskImage
            }
            guard let generated = self.generateTile(for: texture) else {
                return nil
            }
            self.saveToDisk(image: generated, id: texture.id)
            return generated
        }
        inFlight[texture.id] = task
        let result = await task.value
        inFlight.removeValue(forKey: texture.id)
        if let result {
            memoryCache[texture.id] = result
        }
        return result
    }

    private nonisolated func loadFromDisk(id: String) -> NSImage? {
        guard let dir = diskCacheDirSync() else { return nil }
        let url = dir.appendingPathComponent("\(id).png")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private nonisolated func saveToDisk(image: NSImage, id: String) {
        guard let dir = diskCacheDirSync(),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return
        }
        let url = dir.appendingPathComponent("\(id).png")
        try? png.write(to: url, options: .atomic)
    }

    private nonisolated func diskCacheDirSync() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches.appendingPathComponent("com.farrukh.voicetype/PaperTextures_v1", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Procedural Tile Generation (512x512 Seamless)

    nonisolated func generateTile(for texture: ProceduralPaperTexture) -> NSImage? {
        let size = tileSize
        let context = CIContext(options: [.useSoftwareRenderer: false])

        switch texture.kind {
        case .cotton:
            return renderNeutralNoiseTile(size: size, contrast: 0.08, blurRadius: 0.35, context: context)
        case .graphite:
            return renderGraphiteChalkTile(size: size, context: context)
        case .watercolor:
            return renderWatercolorColdPressTile(size: size, context: context)
        case .washi:
            return renderFiberTile(size: size, baseNoiseContrast: 0.06, fiberCount: 380, darkFibers: true, flecks: 0, context: context)
        case .kraft:
            return renderFiberTile(size: size, baseNoiseContrast: 0.10, fiberCount: 440, darkFibers: true, flecks: 260, context: context)
        case .parchment:
            return renderParchmentTile(size: size, context: context)
        case .linen:
            return renderLinenTile(size: size, context: context)
        case .dotted:
            return renderDottedTile(size: size, context: context)
        }
    }

    private nonisolated func seamlessNoiseCGImage(size: Int, blurRadius: Double, context: CIContext) -> CGImage? {
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let gray = random
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
                "inputGVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
                "inputBVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
            .cropped(to: CGRect(x: 0, y: 0, width: size + 64, height: size + 64))

        let processed: CIImage
        if blurRadius > 0 {
            processed = gray
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
                .cropped(to: CGRect(x: 32, y: 32, width: size, height: size))
                .transformed(by: CGAffineTransform(translationX: -32, y: -32))
        } else {
            processed = gray.cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        }

        // Делаем тайл бесшовным через плавное сведение краёв по обеим осям
        guard let baseCG = context.createCGImage(processed, from: CGRect(x: 0, y: 0, width: size, height: size)) else {
            return nil
        }
        return makeToroidalSeamless(cgImage: baseCG, size: size)
    }

    private nonisolated func makeToroidalSeamless(cgImage: CGImage, size: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return cgImage
        }

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        ctx.draw(cgImage, in: rect)

        // Накладываем со сдвигом на половину тайла с радиальной маской — швы полностью исчезают.
        let half = size / 2
        ctx.saveGState()
        let maskCtx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        if let maskCtx {
            let colors = [CGColor(gray: 0, alpha: 1), CGColor(gray: 1, alpha: 1)] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0.25, 1.0]) {
                let center = CGPoint(x: half, y: half)
                maskCtx.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: CGFloat(half),
                    options: [.drawsAfterEndLocation]
                )
            }
            if let mask = maskCtx.makeImage() {
                ctx.clip(to: rect, mask: mask)
                let offsets = [
                    CGPoint(x: -half, y: -half),
                    CGPoint(x: half, y: -half),
                    CGPoint(x: -half, y: half),
                    CGPoint(x: half, y: half)
                ]
                for offset in offsets {
                    ctx.draw(cgImage, in: CGRect(origin: offset, size: CGSize(width: size, height: size)))
                }
            }
        }
        ctx.restoreGState()
        return ctx.makeImage() ?? cgImage
    }

    private nonisolated func renderNeutralNoiseTile(
        size: Int,
        contrast: Double,
        blurRadius: Double,
        context: CIContext
    ) -> NSImage? {
        guard let noise = seamlessNoiseCGImage(size: size, blurRadius: blurRadius, context: context) else {
            return nil
        }
        let ci = CIImage(cgImage: noise)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: contrast,
                kCIInputBrightnessKey: 0.45
            ])
        guard let out = context.createCGImage(ci, from: CGRect(x: 0, y: 0, width: size, height: size)) else {
            return nil
        }
        return NSImage(cgImage: out, size: NSSize(width: size, height: size))
    }

    private nonisolated func renderGraphiteChalkTile(size: Int, context: CIContext) -> NSImage? {
        guard let noise = seamlessNoiseCGImage(size: size, blurRadius: 0.4, context: context) else {
            return nil
        }
        let ci = CIImage(cgImage: noise)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 0.32,
                kCIInputBrightnessKey: -0.35
            ])
        guard let out = context.createCGImage(ci, from: CGRect(x: 0, y: 0, width: size, height: size)) else {
            return nil
        }
        return NSImage(cgImage: out, size: NSSize(width: size, height: size))
    }

    private nonisolated func renderWatercolorColdPressTile(size: Int, context: CIContext) -> NSImage? {
        guard let noiseCG = seamlessNoiseCGImage(size: size, blurRadius: 2.2, context: context) else {
            return nil
        }
        // Карта высот с мягким освещением сверху слева (холодное прессование)
        let heightMap = CIImage(cgImage: noiseCG)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 0.85,
                kCIInputBrightnessKey: 0.0
            ])

        let shaded = heightMap
            .applyingFilter("CIHeightFieldFromMask", parameters: [kCIInputRadiusKey: 3.5])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.14, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.14, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.14, w: 0),
                "inputBiasVector": CIVector(x: 0.84, y: 0.83, z: 0.80, w: 1)
            ])
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))

        guard let out = context.createCGImage(shaded, from: CGRect(x: 0, y: 0, width: size, height: size)) else {
            return nil
        }
        return NSImage(cgImage: out, size: NSSize(width: size, height: size))
    }

    private nonisolated func renderFiberTile(
        size: Int,
        baseNoiseContrast: Double,
        fiberCount: Int,
        darkFibers: Bool,
        flecks: Int,
        context: CIContext
    ) -> NSImage? {
        guard let ctx = createMultiplyCanvas(size: size) else { return nil }

        if let noise = seamlessNoiseCGImage(size: size, blurRadius: 0.5, context: context) {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(baseNoiseContrast * 2.2))
            ctx.draw(noise, in: CGRect(x: 0, y: 0, width: size, height: size))
            ctx.restoreGState()
        }

        var rng = SeededPRNG(seed: darkFibers ? (flecks > 0 ? 4201 : 1337) : 777)
        let s = CGFloat(size)

        for _ in 0..<fiberCount {
            let x = rng.nextCGFloat(in: 0..<s)
            let y = rng.nextCGFloat(in: 0..<s)
            let angle = rng.nextCGFloat(in: 0..<(2 * .pi))
            let length = rng.nextCGFloat(in: 6...20)
            let dx = cos(angle) * length
            let dy = sin(angle) * length
            let isLight = rng.nextDouble() > 0.55

            let strokeColor: CGColor = isLight
                ? CGColor(red: 1, green: 0.99, blue: 0.96, alpha: 0.35)
                : CGColor(red: 0.25, green: 0.19, blue: 0.12, alpha: 0.16)

            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(rng.nextCGFloat(in: 0.45...1.0))

            // Отрисовываем с периодическим переносом на 9 соседних позиций для бесшовности
            for ox in [-s, 0, s] {
                for oy in [-s, 0, s] {
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: x + ox, y: y + oy))
                    ctx.addQuadCurve(
                        to: CGPoint(x: x + ox + dx, y: y + oy + dy),
                        control: CGPoint(x: x + ox + dx * 0.5 + 2, y: y + oy + dy * 0.5 - 2)
                    )
                    ctx.strokePath()
                }
            }
        }

        if flecks > 0 {
            for _ in 0..<flecks {
                let x = rng.nextCGFloat(in: 0..<s)
                let y = rng.nextCGFloat(in: 0..<s)
                let r = rng.nextCGFloat(in: 0.5...1.6)
                ctx.setFillColor(CGColor(red: 0.18, green: 0.12, blue: 0.06, alpha: 0.24))
                for ox in [-s, 0, s] {
                    for oy in [-s, 0, s] {
                        ctx.fillEllipse(in: CGRect(x: x + ox, y: y + oy, width: r, height: r))
                    }
                }
            }
        }

        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }

    private nonisolated func renderParchmentTile(size: Int, context: CIContext) -> NSImage? {
        guard let ctx = createMultiplyCanvas(size: size) else { return nil }
        if let noise = seamlessNoiseCGImage(size: size, blurRadius: 14.0, context: context) {
            ctx.saveGState()
            ctx.setAlpha(0.28)
            ctx.draw(noise, in: CGRect(x: 0, y: 0, width: size, height: size))
            ctx.restoreGState()
        }

        var rng = SeededPRNG(seed: 9091)
        let s = CGFloat(size)
        for _ in 0..<24 {
            let x = rng.nextCGFloat(in: 0..<s)
            let y = rng.nextCGFloat(in: 0..<s)
            let radius = rng.nextCGFloat(in: 24...75)
            ctx.setFillColor(CGColor(red: 0.68, green: 0.56, blue: 0.34, alpha: 0.06))
            for ox in [-s, 0, s] {
                for oy in [-s, 0, s] {
                    ctx.fillEllipse(in: CGRect(x: x + ox - radius, y: y + oy - radius, width: radius * 2, height: radius * 2))
                }
            }
        }
        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }

    private nonisolated func renderLinenTile(size: Int, context: CIContext) -> NSImage? {
        guard let ctx = createMultiplyCanvas(size: size) else { return nil }
        let step: CGFloat = 4
        let s = CGFloat(size)

        for pos in stride(from: CGFloat(0), to: s, by: step) {
            let isAlt = Int(pos / step) % 2 == 0
            ctx.setStrokeColor(CGColor(red: 0.38, green: 0.34, blue: 0.27, alpha: isAlt ? 0.10 : 0.05))
            ctx.setLineWidth(1.0)
            ctx.move(to: CGPoint(x: 0, y: pos))
            ctx.addLine(to: CGPoint(x: s, y: pos))
            ctx.strokePath()

            ctx.setStrokeColor(CGColor(red: 0.38, green: 0.34, blue: 0.27, alpha: isAlt ? 0.05 : 0.10))
            ctx.move(to: CGPoint(x: pos, y: 0))
            ctx.addLine(to: CGPoint(x: pos, y: s))
            ctx.strokePath()
        }

        if let noise = seamlessNoiseCGImage(size: size, blurRadius: 0.4, context: context) {
            ctx.saveGState()
            ctx.setAlpha(0.08)
            ctx.draw(noise, in: CGRect(x: 0, y: 0, width: size, height: size))
            ctx.restoreGState()
        }

        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }

    private nonisolated func renderDottedTile(size: Int, context: CIContext) -> NSImage? {
        guard let ctx = createMultiplyCanvas(size: size) else { return nil }
        let step: CGFloat = 24
        let dotRadius: CGFloat = 1.05
        let s = CGFloat(size)

        if let noise = seamlessNoiseCGImage(size: size, blurRadius: 0.5, context: context) {
            ctx.saveGState()
            ctx.setAlpha(0.06)
            ctx.draw(noise, in: CGRect(x: 0, y: 0, width: size, height: size))
            ctx.restoreGState()
        }

        ctx.setFillColor(CGColor(red: 0.35, green: 0.33, blue: 0.28, alpha: 0.32))
        var x: CGFloat = step / 2
        while x < s {
            var y: CGFloat = step / 2
            while y < s {
                ctx.fillEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                y += step
            }
            x += step
        }

        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }

    private nonisolated func createMultiplyCanvas(size: Int) -> CGContext? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx
    }
}

private struct SeededPRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 1 : seed
    }

    mutating func nextUInt64() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func nextDouble() -> Double {
        Double(nextUInt64() >> 11) / Double(1 << 53)
    }

    mutating func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        let t = CGFloat(nextDouble())
        return range.lowerBound + (range.upperBound - range.lowerBound) * t
    }

    mutating func nextCGFloat(in range: Range<CGFloat>) -> CGFloat {
        let t = CGFloat(nextDouble())
        return range.lowerBound + (range.upperBound - range.lowerBound) * t
    }
}
