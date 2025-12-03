//  MoonPhaseRayTracer.swift
//      MoonPhaseRayTracer
//
//  Created by SNI on 2025/11/03.
//
//  Rereace.
//
//

import Foundation
#if canImport(SceneKit)
import SceneKit
#endif
import CoreLocation
import UIKit

/// A simple ray‑tracing based moon‑phase renderer for iOS.
///
/// Design policy:
/// - Rendering responsibility only:
///   This package focuses on turning a given phase value into a rendered moon image.
///   The recommended API is `renderMoonImage(phase:size:options:)`.
/// - Backward compatibility:
///   `renderMoonImage(for:location:size:)` remains for convenience. It computes a
///   simple phase approximation from date. Location is accepted and, if unavailable,
///   falls back to Kyoto City. Note: the lunar phase (fraction of illumination)
///   does not depend on observer location; location matters for apparent orientation
///   or topocentric coordinates, which we may support in future.
/// - Robustness:
///   Always returns non‑nil PNG data. If the texture cannot be loaded or SceneKit
///   snapshot fails, a CoreGraphics fallback (simple white disk on black) is used.
/// - Resources:
///   A high‑resolution `fullMoon.png` is expected under the package Resources.
///   If not found, rendering continues with a flat material.
/// - Future options:
///   `RenderingOptions` is provided to allow future extension such as bright limb
///   position angle, orientation correction, exposure, gamma and antialiasing.
public struct MoonPhaseRayTracer {

    // MARK: - Public Options

    /// Rendering options for future extensions.
    public struct RenderingOptions {
        /// Antialiasing level for SceneKit snapshot (default: 4x).
        public var antialiasing: Antialiasing
        /// Exposure multiplier (simple brightness gain applied to SceneKit light).
        /// 1.0 = neutral.
        public var exposure: CGFloat
        /// Gamma correction to be applied post render (reserved; not applied in v1).
        public var gamma: CGFloat
        /// Apparent bright limb position angle in degrees (north through east).
        /// Reserved for future orientation control.
        public var brightLimbPositionAngle: CGFloat?
        /// Orientation correction (radians) to rotate the rendered moon around view axis.
        /// Reserved for future control.
        public var orientationCorrection: CGFloat?

        public init(antialiasing: Antialiasing = .x4,
                    exposure: CGFloat = 1.0,
                    gamma: CGFloat = 1.0,
                    brightLimbPositionAngle: CGFloat? = nil,
                    orientationCorrection: CGFloat? = nil) {
            self.antialiasing = antialiasing
            self.exposure = exposure
            self.gamma = gamma
            self.brightLimbPositionAngle = brightLimbPositionAngle
            self.orientationCorrection = orientationCorrection
        }

        public enum Antialiasing {
            case none, x2, x4

            #if canImport(SceneKit)
            var scnMode: SCNAntialiasingMode {
                switch self {
                case .none: return .none
                case .x2:   return .multisampling2X
                case .x4:   return .multisampling4X
                }
            }
            #endif
        }
    }

    // MARK: - Constants

    private static let synodicPeriod: Double = 29.530588861
    private static let moonRadius: CGFloat = 1.0
    private static let lightDistance: Float = 10.0
    private static let textureName: String = "fullMoon"
    private static let kyotoLocation = CLLocationCoordinate2D(latitude: 35.0116, longitude: 135.7681)

    // MARK: - Recommended API (phase input)

    /// Renders a PNG moon image for a given phase fraction.
    ///
    /// - Parameters:
    ///   - phase: Fractional phase in [0, 1], where 0=new, 0.5=full, 1=new.
    ///   - size: Output image size in pixels (square recommended).
    ///   - options: Rendering options (antialiasing, exposure, etc.).
    /// - Returns: PNG data (non‑nil guaranteed; uses fallback if necessary).
    public static func renderMoonImage(phase: Double,
                                       size: CGSize = CGSize(width: 512, height: 512),
                                       options: RenderingOptions = .init()) -> Data {
        let clampedPhase = max(0.0, min(1.0, phase))
        #if canImport(SceneKit)
        if let data = renderWithSceneKit(phase: clampedPhase, size: size, options: options) {
            return data
        }
        #endif
        // Fallback (SceneKit unavailable or snapshot failed)
        return fallback2DImage(size: size)
    }

    // MARK: - Backward-compatible API (date/location input)

    /// Renders a PNG representation of the Moon for the specified date and location.
    ///
    /// Notes:
    /// - The lunar phase (fraction of illumination) does not depend on observer location.
    ///   Location is reserved for future use (apparent orientation, bright limb angle).
    /// - Location handling policy:
    ///   If a valid location is supplied, it is accepted; if nil or otherwise unavailable,
    ///   Kyoto City is used as a safe fallback (for potential future orientation logic).
    ///
    /// - Parameters:
    ///   - date: Date/time for which to compute the Moon phase (simple synodic approximation).
    ///   - location: Observer location if available; if not, Kyoto fallback is assumed.
    ///   - size: Output image size in pixels (square recommended).
    /// - Returns: PNG data (non‑nil guaranteed).
    public static func renderMoonImage(for date: Date,
                                       location: CLLocationCoordinate2D?,
                                       size: CGSize = CGSize(width: 512, height: 512)) -> Data {
        // Compute simple approximate phase (0=new, 0.5=full, 1=new).
        let phase = fractionalPhase(for: date)

        // Location policy (reserved for future orientation control).
        let _ = location ?? kyotoLocation

        return renderMoonImage(phase: phase, size: size, options: .init())
    }

    // MARK: - Phase approximation (simple)

    /// Simple synodic-period based phase fraction in [0, 1).
    public static func fractionalPhase(for date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let referenceComponents = DateComponents(calendar: calendar,
                                                 timeZone: calendar.timeZone,
                                                 year: 2001, month: 1, day: 1)
        let referenceDate = calendar.date(from: referenceComponents)!
        let secondsSinceReference = date.timeIntervalSince(referenceDate)
        let daysSinceReference = secondsSinceReference / 86400.0
        let phase = daysSinceReference / synodicPeriod
        return phase - floor(phase)
    }

    // MARK: - SceneKit path

    #if canImport(SceneKit)
    private static func renderWithSceneKit(phase: Double,
                                           size: CGSize,
                                           options: RenderingOptions) -> Data? {
        // Convert phase to [0, 2π): New at 0, Full at π.
        let phaseAngle = Float(phase * 2.0 * Double.pi)

        // Scene
        let scene = SCNScene()

        // Moon geometry
        let sphere = SCNSphere(radius: moonRadius)
        if let texture = loadMoonTexture() {
            let material = SCNMaterial()
            material.diffuse.contents = texture
            material.isDoubleSided = false
            sphere.materials = [material]
        } else {
            // Texture missing: use a neutral gray material
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: 0.85, alpha: 1.0)
            material.isDoubleSided = false
            sphere.materials = [material]
        }
        let moonNode = SCNNode(geometry: sphere)
        scene.rootNode.addChildNode(moonNode)
        moonNode.position = SCNVector3Zero

        // Directional light (Sun)
        let lightNode = SCNNode()
        let light = SCNLight()
        light.type = .directional
        light.color = UIColor(white: min(max(options.exposure, 0.0), 4.0), alpha: 1.0)
        lightNode.light = light
        let lx = cos(phaseAngle) * lightDistance
        let lz = sin(phaseAngle) * lightDistance
        lightNode.position = SCNVector3(x: lx, y: 0, z: lz)
        lightNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(lightNode)

        // Camera
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 3.0)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        // Optional: orientation correction around view axis (reserved for future)
        if let correction = options.orientationCorrection, correction != 0 {
            let rot = SCNMatrix4MakeRotation(Float(correction), 0, 0, 1)
            moonNode.transform = SCNMatrix4Mult(moonNode.transform, rot)
        }

        // Offscreen renderer
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode

        // Snapshot
        let renderSize = CGSize(width: max(1, size.width), height: max(1, size.height))
        let image = renderer.snapshot(atTime: 0.0, with: renderSize, antialiasingMode: options.antialiasing.scnMode)

        // Return PNG or fall back
        if let data = image.pngData() {
            return data
        } else {
            return fallback2DImage(size: renderSize)
        }
    }

    /// Attempts to load the moon texture from the module bundle.
    /// Tries Bundle.module first, then falls back to Bundle.main.
    private static func loadMoonTexture() -> UIImage? {
        // 1) Package resource
        if let url = Bundle.module.url(forResource: textureName, withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            return img
        }
        // 2) App bundle fallback (optional duplicate asset)
        if let url = Bundle.main.url(forResource: textureName, withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            return img
        }
        // 3) Named lookup in module (less reliable with SPM, but try)
        if let img = UIImage(named: textureName, in: Bundle.module, compatibleWith: nil) {
            return img
        }
        // 4) Named lookup in main bundle
        if let img = UIImage(named: textureName) {
            return img
        }
        return nil
    }
    #endif

    // MARK: - Final 2D fallback (non‑nil guarantee)

    /// Draws a simple white disk on black background and returns PNG data.
    private static func fallback2DImage(size: CGSize) -> Data {
        let w = max(1, Int(size.width))
        let h = max(1, Int(size.height))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let img = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let r = min(w, h)
            let inset = CGFloat(r) * 0.15
            let circleRect = CGRect(x: inset,
                                    y: inset,
                                    width: CGFloat(r) - inset * 2,
                                    height: CGFloat(r) - inset * 2)
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: circleRect)
        }
        // pngData() is non‑optional
        return img.pngData()!
    }
}
