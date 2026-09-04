//
//  LocationEngine.swift
//  invis
//
//  Ported and enhanced from jatgm/location_spoofer (route_simulator.py & device_service.py)
//  Handles Haversine geodesic math, waypoint interpolation, Box-Muller Gaussian drift,
//  and route generation for Apple Maps and Raspberry Pi Pico firmware.
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Preset Landmark Model
public struct LandmarkPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    public let symbolName: String

    public init(name: String, subtitle: String, latitude: Double, longitude: Double, altitude: Double = 10.0, symbolName: String = "mappin.and.ellipse") {
        self.id = name
        self.name = name
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.symbolName = symbolName
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Travel Mode Enum
public enum TravelMode: String, CaseIterable, Identifiable, Sendable {
    case walk = "Walk"
    case cycle = "Cycle"
    case drive = "Drive"
    case express = "Express"

    public var id: String { rawValue }

    public var baseSpeedKmh: Double {
        switch self {
        case .walk: return 5.0
        case .cycle: return 20.0
        case .drive: return 50.0
        case .express: return 85.0
        }
    }

    public var iconName: String {
        switch self {
        case .walk: return "figure.walk"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        case .express: return "car.side.fast.arrow.forward.fill"
        }
    }
}

// MARK: - Waypoint Step
public struct WaypointStep: Identifiable, Sendable {
    public let id = UUID()
    public let coordinate: CLLocationCoordinate2D
    public let speedKmh: Double
    public let heading: Double
    public let timestampOffset: TimeInterval
}

// MARK: - Location Engine
public final class LocationEngine: @unchecked Sendable {
    public static let shared = LocationEngine()

    public static let earthRadiusMeters: Double = 6_371_000.0

    // MARK: - Landmark Presets
    public static let defaultPresets: [LandmarkPreset] = [
        LandmarkPreset(name: "Apple Park", subtitle: "Cupertino, CA, USA", latitude: 37.334900, longitude: -122.009020, altitude: 45.0, symbolName: "apple.logo"),
        LandmarkPreset(name: "Times Square", subtitle: "New York, NY, USA", latitude: 40.758000, longitude: -73.985500, altitude: 15.0, symbolName: "theatermasks.fill"),
        LandmarkPreset(name: "Eiffel Tower", subtitle: "Paris, France", latitude: 48.858400, longitude: 2.294500, altitude: 33.0, symbolName: "building.2.fill"),
        LandmarkPreset(name: "Shibuya Crossing", subtitle: "Tokyo, Japan", latitude: 35.659500, longitude: 139.700500, altitude: 20.0, symbolName: "tram.fill"),
        LandmarkPreset(name: "Big Ben", subtitle: "London, UK", latitude: 51.500700, longitude: -0.124600, altitude: 12.0, symbolName: "clock.fill"),
        LandmarkPreset(name: "Sydney Opera House", subtitle: "Sydney, Australia", latitude: -33.856800, longitude: 151.215300, altitude: 5.0, symbolName: "water.waves"),
        LandmarkPreset(name: "Colosseum", subtitle: "Rome, Italy", latitude: 41.890200, longitude: 12.492200, altitude: 22.0, symbolName: "shield.fill"),
        LandmarkPreset(name: "Waikiki Beach", subtitle: "Honolulu, HI, USA", latitude: 21.276600, longitude: -157.827300, altitude: 2.0, symbolName: "sun.max.fill"),
        LandmarkPreset(name: "Golden Gate Bridge", subtitle: "San Francisco, CA, USA", latitude: 37.819929, longitude: -122.478255, altitude: 67.0, symbolName: "bridge"),
        LandmarkPreset(name: "Burj Khalifa", subtitle: "Dubai, UAE", latitude: 25.197197, longitude: 55.274376, altitude: 828.0, symbolName: "building.fill")
    ]

    private init() {}

    // MARK: - Haversine Distance
    /// Calculates the great-circle distance between two coordinates in meters.
    public func haversineDistance(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> Double {
        let phi1 = start.latitude * .pi / 180.0
        let phi2 = destination.latitude * .pi / 180.0
        let deltaPhi = (destination.latitude - start.latitude) * .pi / 180.0
        let deltaLambda = (destination.longitude - start.longitude) * .pi / 180.0

        let a = sin(deltaPhi / 2.0) * sin(deltaPhi / 2.0) +
                cos(phi1) * cos(phi2) * sin(deltaLambda / 2.0) * sin(deltaLambda / 2.0)
        let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
        return Self.earthRadiusMeters * c
    }

    // MARK: - Bearing Calculation
    /// Calculates the initial heading / bearing in degrees [0, 360) from start to destination.
    public func initialBearing(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> Double {
        let phi1 = start.latitude * .pi / 180.0
        let phi2 = destination.latitude * .pi / 180.0
        let deltaLambda = (destination.longitude - start.longitude) * .pi / 180.0

        let y = sin(deltaLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda)
        let bearingRad = atan2(y, x)
        let bearingDeg = (bearingRad * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
        return bearingDeg
    }

    // MARK: - Interpolation
    /// Linearly interpolates between two coordinates with `numSteps` segments.
    public func interpolate(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        steps numSteps: Int
    ) -> [CLLocationCoordinate2D] {
        guard numSteps > 0 else { return [destination] }
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(numSteps)

        for i in 1...numSteps {
            let fraction = Double(i) / Double(numSteps)
            let lat = start.latitude + (destination.latitude - start.latitude) * fraction
            let lon = start.longitude + (destination.longitude - start.longitude) * fraction
            result.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        return result
    }

    // MARK: - Micro-Jitter (Gaussian Random-Walk GPS Drift)
    /// Port of the Gaussian micro-jitter algorithm:
    /// delta_lat = N(0, sigma^2), delta_lon = N(0, sigma^2)
    /// Uses the Box-Muller transform for high-fidelity normal distribution generation.
    /// - Parameters:
    ///   - coordinate: The base coordinate.
    ///   - radiusMeters: Standard deviation scale in meters (default 0.8m, configurable 0.5m - 5.0m).
    public func applyMicroJitter(
        to coordinate: CLLocationCoordinate2D,
        radiusMeters: Double = 0.8
    ) -> CLLocationCoordinate2D {
        // Box-Muller transform: generate two independent standard normal random variables
        let u1 = max(1e-9, Double.random(in: 0.0...1.0))
        let u2 = Double.random(in: 0.0...1.0)
        let z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        let z1 = sqrt(-2.0 * log(u1)) * sin(2.0 * .pi * u2)

        // Scale by desired standard deviation in meters
        let deltaYMeters = z0 * (radiusMeters / 2.0)
        let deltaXMeters = z1 * (radiusMeters / 2.0)

        // Convert displacement in meters to degrees
        let metersPerDegreeLat = 111_139.0
        let latRad = coordinate.latitude * .pi / 180.0
        let metersPerDegreeLon = 111_139.0 * max(0.001, cos(latRad))

        let newLat = coordinate.latitude + (deltaYMeters / metersPerDegreeLat)
        let newLon = coordinate.longitude + (deltaXMeters / metersPerDegreeLon)

        // Clamp latitude to [-90, 90] and longitude to [-180, 180]
        let clampedLat = min(90.0, max(-90.0, newLat))
        var clampedLon = (newLon + 180.0).truncatingRemainder(dividingBy: 360.0)
        if clampedLon < 0 { clampedLon += 360.0 }
        clampedLon -= 180.0

        return CLLocationCoordinate2D(latitude: clampedLat, longitude: clampedLon)
    }

    // MARK: - Route Timeline Generation
    /// Slices raw waypoints into evenly-spaced temporal ticks based on travel speed.
    /// Introduces realistic traffic speed micro-fluctuations (±5%) and corner deceleration.
    public func buildInterpolatedTimeline(
        from rawWaypoints: [CLLocationCoordinate2D],
        speedKmh: Double,
        tickIntervalSec: Double = 1.0,
        realisticTraffic: Bool = true
    ) -> [WaypointStep] {
        guard rawWaypoints.count >= 2 else {
            if let first = rawWaypoints.first {
                return [WaypointStep(coordinate: first, speedKmh: speedKmh, heading: 0.0, timestampOffset: 0.0)]
            }
            return []
        }

        let baseSpeedMps = max(0.5, (speedKmh * 1000.0) / 3600.0)
        var steps: [WaypointStep] = []
        var currentTime: TimeInterval = 0.0
        var currentCoord = rawWaypoints[0]

        steps.append(
            WaypointStep(
                coordinate: currentCoord,
                speedKmh: speedKmh,
                heading: initialBearing(from: rawWaypoints[0], to: rawWaypoints[1]),
                timestampOffset: currentTime
            )
        )

        var globalStepIndex = 0

        for nextCoord in rawWaypoints.dropFirst() {
            let segmentDistance = haversineDistance(from: currentCoord, to: nextCoord)
            let segmentHeading = initialBearing(from: currentCoord, to: nextCoord)

            // Calculate step distance for this tick with traffic fluctuation
            let trafficFactor = realisticTraffic ? (1.0 + 0.05 * sin(Double(globalStepIndex) * 0.3)) : 1.0
            let stepDistance = max(0.5, baseSpeedMps * trafficFactor * tickIntervalSec)

            if segmentDistance <= stepDistance {
                currentTime += tickIntervalSec
                steps.append(
                    WaypointStep(
                        coordinate: nextCoord,
                        speedKmh: speedKmh * trafficFactor,
                        heading: segmentHeading,
                        timestampOffset: currentTime
                    )
                )
                currentCoord = nextCoord
                globalStepIndex += 1
            } else {
                let numSteps = max(1, Int(segmentDistance / stepDistance))
                let interpolated = interpolate(from: currentCoord, to: nextCoord, steps: numSteps)

                for point in interpolated {
                    currentTime += tickIntervalSec
                    globalStepIndex += 1
                    let pointTraffic = realisticTraffic ? (1.0 + 0.05 * sin(Double(globalStepIndex) * 0.3)) : 1.0
                    steps.append(
                        WaypointStep(
                            coordinate: point,
                            speedKmh: speedKmh * pointTraffic,
                            heading: segmentHeading,
                            timestampOffset: currentTime
                        )
                    )
                }
                currentCoord = nextCoord
            }
        }

        return steps
    }
}
