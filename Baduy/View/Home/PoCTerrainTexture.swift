import UIKit
import RealityKit

enum TerrainTexture {
    static func make() throws -> TextureResource {
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
            for y in stride(from: 0, to: size, by: 2) {
                for x in stride(from: 0, to: size, by: 2) {
                    let px = Float(x) / Float(size) * (halfSpan * 2.0) - halfSpan
                    let pz = Float(y) / Float(size) * (halfSpan * 2.0) - halfSpan
                    do {
                        // Use the same height function as the terrain mesh.
                        let terrainHeight = BaduyWorld.height(px, pz)
                        let depthRatio = max(0, min(1, (terrainHeight + 5) / 35))
                        let slopeX = (BaduyWorld.height(px + 1, pz) - BaduyWorld.height(px - 1, pz)) / 2
                        let slopeZ = (BaduyWorld.height(px, pz + 1) - BaduyWorld.height(px, pz - 1)) / 2
                        let relief = Double(max(-0.10, min(0.10, (-slopeX - slopeZ) * 0.14)))
                        let contour = abs(terrainHeight / 3 - (terrainHeight / 3).rounded()) < 0.025 ? -0.045 : 0.0
                        let grain = (sin(Float(x * 17 + y * 43)) * 0.04) + (cos(Float(x * 37 - y * 19)) * 0.03)

                        // Lower ground is deep forest green; ridges become a
                        // warm leaf green. This keeps relief readable while
                        // matching natural Baduy materials.
                        let r = max(0, min(1, 0.18 + Double(depthRatio) * 0.27 + Double(grain) * 0.25 + relief + contour))
                        let g = max(0, min(1, 0.32 + Double(depthRatio) * 0.28 + Double(grain) * 0.30 + relief + contour))
                        let b = max(0, min(1, 0.27 + Double(depthRatio) * 0.12 + Double(grain) * 0.20 + relief + contour))

                        UIColor(red: r, green: g, blue: b, alpha: 1).setFill()
                        cg.fill(CGRect(x: x, y: y, width: 2, height: 2))
                    }
                }
            }

            // Subtle woven-diamond texture inspired by Baduy textile motifs.
            // Low opacity prevents the motif from competing with roads, DEM
            // contours, houses, and location labels.
            cg.saveGState()
            cg.setStrokeColor(UIColor(red: 0.035, green: 0.13, blue: 0.23, alpha: 0.10).cgColor)
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
            cg.setFillColor(UIColor(red: 0.055, green: 0.22, blue: 0.16, alpha: 0.62).cgColor)
            for i in 0..<260 {
                let seed = Float(i) * 1.618
                let fx = sin(seed * 7.1) * 115.0 + 30.0
                let fz = cos(seed * 4.3) * 135.0 + 110.0
                let pt = toPoint(SIMD3<Float>(fx, 0, fz))
                let treeR: CGFloat = CGFloat(2.5 + 2.0 * sin(seed * 3.0))
                cg.fillEllipse(in: CGRect(x: pt.x - treeR, y: pt.y - treeR * 1.5, width: treeR * 2, height: treeR * 3))
            }

            // 4. WATERWAYS & RIVERS (Sungai Ciujung flowing between Ciboleger & Kaduketug)
            let riverColor = UIColor(red: 0.27, green: 0.53, blue: 0.64, alpha: 0.94)
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

            // Buildings are rendered only as RealityKit lumbung models.
            // 6. VINTAGE BORDER
            let borderStroke = UIColor(red: 0.035, green: 0.13, blue: 0.23, alpha: 0.86)
            borderStroke.setStroke()
            cg.setLineWidth(2.5)
            cg.stroke(CGRect(x: 14, y: 14, width: size - 28, height: size - 28))
            cg.stroke(CGRect(x: 22, y: 22, width: size - 44, height: size - 44))
        }
        return try TextureResource.generate(from: image.cgImage!, options: .init(semantic: .color))
    }
}
