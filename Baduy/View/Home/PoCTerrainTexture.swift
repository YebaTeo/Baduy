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

            // 1. BASE BACKGROUND: Vintage parchment / aged map paper
            let parchmentColor = UIColor(red: 0.88, green: 0.84, blue: 0.76, alpha: 1.0)
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

                        // Rich Deep Indigo gradient: Inner dark navy/charcoal (#131E2A) -> Rim deep slate blue (#22384B)
                        let r = max(0, min(1, 0.07 + Double(depthRatio) * 0.28 + Double(grain) * 0.4 + relief + contour))
                        let g = max(0, min(1, 0.15 + Double(depthRatio) * 0.25 + Double(grain) * 0.4 + relief + contour))
                        let b = max(0, min(1, 0.21 + Double(depthRatio) * 0.13 + Double(grain) * 0.4 + relief + contour))

                        UIColor(red: r, green: g, blue: b, alpha: 1).setFill()
                        cg.fill(CGRect(x: x, y: y, width: 2, height: 2))
                    }
                }
            }

            // 3. TREE CLUSTER TEXTURES (Stippled forest foliage matching the woodblock print)
            cg.setFillColor(UIColor(red: 0.18, green: 0.28, blue: 0.36, alpha: 0.7).cgColor)
            for i in 0..<260 {
                let seed = Float(i) * 1.618
                let fx = sin(seed * 7.1) * 115.0 + 30.0
                let fz = cos(seed * 4.3) * 135.0 + 110.0
                let pt = toPoint(SIMD3<Float>(fx, 0, fz))
                let treeR: CGFloat = CGFloat(2.5 + 2.0 * sin(seed * 3.0))
                cg.fillEllipse(in: CGRect(x: pt.x - treeR, y: pt.y - treeR * 1.5, width: treeR * 2, height: treeR * 3))
            }

            // 4. WATERWAYS & RIVERS (Sungai Ciujung flowing between Ciboleger & Kaduketug)
            let riverColor = UIColor(red: 0.44, green: 0.64, blue: 0.76, alpha: 0.92)
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

            // 5. AUTHENTIC MAP STREETS (Woodcut styled dashed tracks with junction beads)
            func drawWindingStreet(from: SIMD3<Float>, to: SIMD3<Float>, curveIntensity: Float = 0) {
                let steps = 40
                var pts: [CGPoint] = []
                for s in 0...steps {
                    let t = Float(s) / Float(steps)
                    var p = from + (to - from) * t
                    // Natural walking trail curvature following contours
                    p.x += sin(t * .pi) * curveIntensity
                    pts.append(toPoint(p))
                }

                // 5a. Dark outer path outline
                let borderPath = UIBezierPath()
                borderPath.move(to: pts[0])
                for pt in pts.dropFirst() { borderPath.addLine(to: pt) }
                UIColor(red: 0.08, green: 0.12, blue: 0.16, alpha: 0.92).setStroke()
                borderPath.lineWidth = 7.0
                borderPath.stroke()

                // 5b. Inner dashed cream street track matching the reference illustration
                let dashPath = UIBezierPath()
                dashPath.move(to: pts[0])
                for pt in pts.dropFirst() { dashPath.addLine(to: pt) }
                let dashes: [CGFloat] = [7.0, 4.0]
                dashPath.setLineDash(dashes, count: dashes.count, phase: 0)
                UIColor(red: 0.96, green: 0.92, blue: 0.78, alpha: 1.0).setStroke()
                dashPath.lineWidth = 3.8
                dashPath.stroke()
            }

            // Main Trail from Terminal -> Saung Info -> Jembatan Ciujung -> Kaduketug -> Kadujangkung
            let landmarks = BaduyLandmark.samples
            if landmarks.count >= 2 {
                for i in 0..<(landmarks.count - 1) {
                    let p0 = landmarks[i].position
                    let p1 = landmarks[i + 1].position
                    let curve: Float = (i % 2 == 0) ? 14.0 : -14.0
                    drawWindingStreet(from: p0, to: p1, curveIntensity: curve)
                }
            }

            // Regional entrance road from Leuwidamar & forest paths
            let sideAlleys: [(SIMD3<Float>, SIMD3<Float>)] = [
                (SIMD3<Float>(-500, 0, -580), SIMD3<Float>(40, 0, -180)),  // Northern main road
                (SIMD3<Float>(42, 0, -170), SIMD3<Float>(380, 0, -220)),   // Eastern hillside road
                (SIMD3<Float>(85, 0, -80), SIMD3<Float>(420, 0, 120)),     // Kaduketuk to eastern leuit
                (SIMD3<Float>(-50, 0, 140), SIMD3<Float>(-320, 0, 380))    // Southern deep trail
            ]
            for alley in sideAlleys {
                drawWindingStreet(from: alley.0, to: alley.1, curveIntensity: 20.0)
            }

            // Illustrated Waypoint Nodes / Rings on Landmark Centers (as drawn on the map)
            for lm in landmarks {
                let centerPt = toPoint(lm.position)
                cg.setFillColor(UIColor(red: 0.08, green: 0.12, blue: 0.16, alpha: 0.95).cgColor)
                cg.fillEllipse(in: CGRect(x: centerPt.x - 5.5, y: centerPt.y - 5.5, width: 11, height: 11))
                cg.setFillColor(UIColor(red: 0.96, green: 0.92, blue: 0.78, alpha: 1.0).cgColor)
                cg.fillEllipse(in: CGRect(x: centerPt.x - 3.5, y: centerPt.y - 3.5, width: 7, height: 7))
            }

            // 6. 2D BUILDING FOOTPRINT PLOTS
            func drawBuildingFootprint(at pos: SIMD3<Float>, width: CGFloat, height: CGFloat, angle: CGFloat) {
                let pt = toPoint(pos)
                cg.saveGState()
                cg.translateBy(x: pt.x, y: pt.y)
                cg.rotate(by: angle)

                // Dark outline
                let rect = CGRect(x: -width/2, y: -height/2, width: width, height: height)
                UIColor(red: 0.08, green: 0.11, blue: 0.15, alpha: 0.9).setFill()
                cg.fill(rect.insetBy(dx: -1.5, dy: -1.5))

                // Light cream/straw roof tone matching the illustrated map
                UIColor(red: 0.92, green: 0.86, blue: 0.72, alpha: 1.0).setFill()
                cg.fill(rect)

                // Ridge line
                UIColor(red: 0.28, green: 0.22, blue: 0.16, alpha: 0.85).setStroke()
                cg.setLineWidth(1.2)
                cg.strokeLineSegments(between: [CGPoint(x: -width/2, y: 0), CGPoint(x: width/2, y: 0)])
                cg.restoreGState()
            }

            for building in SettlementData.surroundingBuildings {
                drawBuildingFootprint(
                    at: building.position,
                    width: CGFloat(building.size.x * 2.2),
                    height: CGFloat(building.size.z * 2.2),
                    angle: CGFloat(building.rotationY)
                )
            }

            // 7. ENCLAVE LABELS & VINTAGE BORDER
            let borderStroke = UIColor(red: 0.14, green: 0.20, blue: 0.28, alpha: 0.85)
            borderStroke.setStroke()
            cg.setLineWidth(2.5)
            cg.stroke(CGRect(x: 14, y: 14, width: size - 28, height: size - 28))
            cg.stroke(CGRect(x: 22, y: 22, width: size - 44, height: size - 44))
        }
        return try TextureResource.generate(from: image.cgImage!, options: .init(semantic: .color))
    }
}
