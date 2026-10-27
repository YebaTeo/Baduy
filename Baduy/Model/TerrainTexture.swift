import UIKit
import RealityKit

private nonisolated struct TerrainElevationData: Decodable, Sendable {
    let width: Int
    let height: Int
    let scale: Int
    let values: [Int]
}

@MainActor
enum TerrainTexture {
    private static var cachedTexture: TextureResource?

    private static var loadingTask: Task<TextureResource, Error>?

    static func make() async throws -> TextureResource {
        if let cachedTexture { return cachedTexture }
        if let loadingTask { return try await loadingTask.value }
        let task = Task { @MainActor in
            let image = try await Task.detached(priority: .userInitiated) {
                let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                let url = directory.appendingPathComponent("baduy-terrain-sage-2k-v7.png")
                if let image = UIImage(contentsOfFile: url.path)?.cgImage { return image }
                let image = renderImage()
                if let data = image.pngData() { try? data.write(to: url, options: .atomic) }
                guard let cgImage = image.cgImage else { throw CocoaError(.fileReadCorruptFile) }
                return cgImage
            }.value
            return try await TextureResource(
                image: image,
                withName: "baduy-terrain-sage-v7",
                options: .init(semantic: .color)
            )
        }
        loadingTask = task
        defer { loadingTask = nil }
        let texture = try await task.value
        cachedTexture = texture
        return texture
    }

    nonisolated private static func renderImage() -> UIImage {
        let elevationData: TerrainElevationData? = {
            guard let url = Bundle.main.url(forResource: "ciboleger-dem", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(TerrainElevationData.self, from: data)
        }()
        let minimumElevation = elevationData?.values.min() ?? 0
        let maximumElevation = elevationData?.values.max() ?? 1
        let elevationRange = max(1, maximumElevation - minimumElevation)

        // 2K keeps the map responsive while per-pixel rendering and smooth
        // color variation avoid the blocky look of the old raster.
        let size = 2048
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext

            // Baduy palette: bamboo paper, forest green, and woven-cloth indigo.
            let parchmentColor = UIColor(red: 0.94, green: 0.88, blue: 0.72, alpha: 1.0)
            cg.setFillColor(parchmentColor.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))

            // Span: 1900m x 1900m (-950 to +950) covering all 214 settlement buildings and cultural landmarks
            let halfSpan: Float = 950.0
            func toPoint(_ p: SIMD3<Float>) -> CGPoint {
                CGPoint(
                    x: CGFloat(p.x + halfSpan) / CGFloat(halfSpan * 2.0) * CGFloat(size),
                    y: CGFloat(p.z + halfSpan) / CGFloat(halfSpan * 2.0) * CGFloat(size)
                )
            }

            // Elevation colors, relief, and grain cover the entire terrain footprint.
            var pixels = [UInt8](repeating: 255, count: size * size * 4)
            let stops: [SIMD3<Double>] = [
                [0.24, 0.40, 0.33], [0.46, 0.60, 0.43], [0.69, 0.74, 0.53]
            ]
            for y in 0..<size {
                for x in 0..<size {
                    let px = Float(x) / Float(size) * (halfSpan * 2.0) - halfSpan
                    let pz = Float(y) / Float(size) * (halfSpan * 2.0) - halfSpan
                    do {
                        // Decorative relief for the illustrated color texture.
                        let sourceX = min(255, x * 256 / size)
                        let sourceY = min(255, y * 256 / size)
                        let sourceIndex = sourceY * 256 + sourceX
                        let terrainHeight = BaduyWorld.height(px, pz)
                        // Convert terrain elevation into a continuous low-to-high
                        // palette. The texture is regenerated with each cache
                        // version so changes to this scale are visible on device.
                        let fallbackRatio = max(0, min(1, (terrainHeight + 8) / 42))
                        let heightRatio: Float
                        if let elevationData, elevationData.values.indices.contains(sourceIndex) {
                            heightRatio = Float(elevationData.values[sourceIndex] - minimumElevation)
                                / Float(elevationRange)
                        } else {
                            heightRatio = fallbackRatio
                        }
                        let slopeX = (BaduyWorld.height(px + 1, pz) - BaduyWorld.height(px - 1, pz)) / 2
                        let slopeZ = (BaduyWorld.height(px, pz + 1) - BaduyWorld.height(px, pz - 1)) / 2
                        // A restrained directional relief gives the terrain some
                        // depth without changing its original illustrated style.
                        let relief = Double(max(-0.05, min(0.05, (-slopeX - slopeZ) * 0.09)))
                        // Broad, continuous variation reads as land cover at
                        // map scale. Avoid high-frequency pixel noise, which
                        // looked blocky when the user zoomed into the map.
                        let smoothX = Float(x) / Float(size)
                        let smoothY = Float(y) / Float(size)
                        let grain = (sin(smoothX * 19 + smoothY * 11) * 0.018)
                            + (cos(smoothX * 7 - smoothY * 15) * 0.012)

                        // Forest -> sage -> warm bamboo green. Smoothstep keeps
                        // the transition soft without visible color bands.
                        let ratio = Double(fallbackRatio) * 2
                        let segment = min(Int(ratio), 1)
                        let t = ratio - Double(segment)
                        let blend = t * t * (3 - 2 * t)
                        let color = stops[segment] * (1 - blend) + stops[segment + 1] * blend
                        let heightShade = (Double(heightRatio) - 0.5) * 0.025
                        let shade = relief * 0.25 + heightShade + Double(grain) * 0.08
                        let r = max(0, min(1, color.x + shade))
                        let g = max(0, min(1, color.y + shade))
                        let b = max(0, min(1, color.z + shade))

                        let offset = (y * size + x) * 4
                        pixels[offset] = UInt8((r * 255).rounded())
                        pixels[offset + 1] = UInt8((g * 255).rounded())
                        pixels[offset + 2] = UInt8((b * 255).rounded())
                    }
                }
            }

            // One image draw replaces millions of Core Graphics fill calls.
            let data = Data(pixels)
            if let provider = CGDataProvider(data: data as CFData),
               let raster = CGImage(width: size, height: size,
                                    bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: size * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil,
                                    shouldInterpolate: true, intent: .defaultIntent) {
                UIImage(cgImage: raster).draw(in: CGRect(x: 0, y: 0, width: size, height: size))
            }

            // Subtle woven-diamond texture inspired by Baduy textile motifs.
            // Low opacity prevents the motif from competing with roads, DEM
            // contours, houses, and location labels.
            cg.saveGState()
            cg.setStrokeColor(UIColor(red: 0.14, green: 0.27, blue: 0.29, alpha: 0.045).cgColor)
            cg.setLineWidth(2)
            let motifSpacing: CGFloat = 128
            let motifRadius: CGFloat = 13
            var row = 0
            var motifY: CGFloat = 72
            while motifY < CGFloat(size) {
                var motifX: CGFloat = row.isMultiple(of: 2) ? 72 : 136
                while motifX < CGFloat(size) {
                    let diamond = UIBezierPath()
                    diamond.move(to: CGPoint(x: motifX, y: motifY - motifRadius))
                    diamond.addLine(to: CGPoint(x: motifX + motifRadius, y: motifY))
                    diamond.addLine(to: CGPoint(x: motifX, y: motifY + motifRadius))
                    diamond.addLine(to: CGPoint(x: motifX - motifRadius, y: motifY))
                    diamond.close()
                    diamond.stroke()

                    let inner = UIBezierPath()
                    let innerRadius = motifRadius * 0.45
                    inner.move(to: CGPoint(x: motifX, y: motifY - innerRadius))
                    inner.addLine(to: CGPoint(x: motifX + innerRadius, y: motifY))
                    inner.addLine(to: CGPoint(x: motifX, y: motifY + innerRadius))
                    inner.addLine(to: CGPoint(x: motifX - innerRadius, y: motifY))
                    inner.close()
                    inner.stroke()
                    motifX += motifSpacing
                }
                row += 1
                motifY += motifSpacing
            }
            cg.restoreGState()

            // 3. TREE CLUSTER TEXTURES (Stippled forest foliage matching the woodblock print)
            cg.setFillColor(UIColor(red: 0.20, green: 0.36, blue: 0.28, alpha: 0.20).cgColor)
            for i in 0..<260 {
                let seed = Float(i) * 1.618
                let fx = sin(seed * 7.1) * 115.0 + 30.0
                let fz = cos(seed * 4.3) * 135.0 + 110.0
                let pt = toPoint(SIMD3<Float>(fx, 0, fz))
                let treeR: CGFloat = CGFloat(2.5 + 2.0 * sin(seed * 3.0))
                cg.fillEllipse(in: CGRect(x: pt.x - treeR, y: pt.y - treeR * 1.5, width: treeR * 2, height: treeR * 3))
            }

            // 4. WATERWAYS & RIVERS (Sungai Ciujung flowing between Ciboleger & Kaduketug)
            let riverColor = UIColor(red: 0.39, green: 0.64, blue: 0.68, alpha: 0.94)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            // Sungai Ciujung: flows south past Jembatan Ciujung [-35, 75]
            let ciujungRiver = UIBezierPath()
            var started = false
            for step in 0...200 {
                let z = Float(step) * 2.6 - 260
                let curve = -35.0 + 38.0 * sin((z - 75.0) / 60.0) + 12.0 * cos(z / 24.0)
                let pt = toPoint(SIMD3<Float>(curve, 0, z))
                if !started { ciujungRiver.move(to: pt); started = true }
                else { ciujungRiver.addLine(to: pt) }
            }
            riverColor.setStroke()
            ciujungRiver.lineWidth = 6.0
            ciujungRiver.stroke()

            // Tributary river branch to the east
            let eastRiver = UIBezierPath()
            started = false
            for step in 0...160 {
                let z = Float(step) * 3.0 - 240
                let x = 110.0 + 24.0 * sin(z / 45.0)
                let pt = toPoint(SIMD3<Float>(x, 0, z))
                if !started { eastRiver.move(to: pt); started = true }
                else { eastRiver.addLine(to: pt) }
            }
            eastRiver.lineWidth = 3.5
            eastRiver.stroke()

            let landmarks = BaduyLandmark.samples
            // Illustrated Waypoint Nodes / Rings on Landmark Centers (as drawn on the map)
            for lm in landmarks {
                let centerPt = toPoint(lm.position)
                cg.setFillColor(UIColor(red: 0.08, green: 0.12, blue: 0.16, alpha: 0.95).cgColor)
                cg.fillEllipse(in: CGRect(x: centerPt.x - 5.5, y: centerPt.y - 5.5, width: 11, height: 11))
                cg.setFillColor(UIColor(red: 0.96, green: 0.92, blue: 0.78, alpha: 1.0).cgColor)
                cg.fillEllipse(in: CGRect(x: centerPt.x - 3.5, y: centerPt.y - 3.5, width: 7, height: 7))
            }

            // Buildings are rendered as lightweight procedural RealityKit lumbung models.
            // 6. VINTAGE BORDER
            let borderStroke = UIColor(red: 0.035, green: 0.13, blue: 0.23, alpha: 0.86)
            borderStroke.setStroke()
            cg.setLineWidth(2.5)
            cg.stroke(CGRect(x: 14, y: 14, width: size - 28, height: size - 28))
            cg.stroke(CGRect(x: 22, y: 22, width: size - 44, height: size - 44))
        }
        return image
    }
}
