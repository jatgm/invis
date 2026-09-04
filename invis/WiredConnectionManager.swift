//
//  WiredConnectionManager.swift
//  invis
//
//  Wired Physical Connection Manager for iOS.
//  Strictly communicates over physical wired USB:
//  - MacBook USB-C Cable: Inbound NWListener on port 9000 accepts usbmuxd tunnel from Mac bridge
//  - Raspberry Pi Pico: Outbound NWConnection to 192.168.7.1:9000 over USB CDC-NCM Ethernet
//  - iOS Simulator: Outbound fallback to 127.0.0.1:9000
//

import Foundation
import CoreLocation
import Combine
import Network

// MARK: - Connection Status Enum
public enum ConnectionStatus: Equatable, Sendable {
    case disconnected(reason: String)
    case connecting(detail: String)
    case connected(latencyMs: Double, firmwareVersion: String, transport: String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var statusTitle: String {
        switch self {
        case .disconnected: return "Hardware Disconnected"
        case .connecting: return "Connecting to Firmware..."
        case .connected: return "Firmware Connected"
        }
    }
}

// MARK: - Transport Mode
public enum TransportMode: String, CaseIterable, Sendable {
    case auto = "Auto Detect"
    case macUsb = "MacBook USB-C (usbmux)"
    case picoEthernet = "Pico USB OTG (CDC-NCM)"
}

// MARK: - Log Entry
public struct ActivityLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let tag: String // "TX", "RX", "INFO", "WARN", "ERR"
    public let message: String

    public init(tag: String, message: String) {
        self.timestamp = Date()
        self.tag = tag
        self.message = message
    }

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Wired Connection Manager
@MainActor
public final class WiredConnectionManager: ObservableObject {
    public static let shared = WiredConnectionManager()

    // Published UI States
    @Published public var status: ConnectionStatus = .disconnected(reason: "Plug in iPhone or Raspberry Pi Pico via USB")
    @Published public var transportMode: TransportMode = .auto
    @Published public var activeTransportName: String = "None"
    @Published public var connectedDeviceName: String? = nil
    @Published public var connectedDeviceModel: String? = nil
    @Published public var currentSpoofedLocation: CLLocationCoordinate2D? = nil
    @Published public var isSpoofingActive: Bool = false
    @Published public var isRoutePlaying: Bool = false
    @Published public var isRoutePaused: Bool = false
    @Published public var routeProgress: Double = 0.0 // 0.0 to 1.0
    @Published public var routeRemainingSeconds: TimeInterval = 0
    @Published public var pingLatencyMs: Double = 0.0
    @Published public var logs: [ActivityLogEntry] = []

    // Micro-jitter settings
    @Published public var naturalDriftEnabled: Bool = false
    @Published public var driftRadiusMeters: Double = 1.0

    // Internal timers & workers
    private var heartbeatTimer: Timer?
    private var routeTimer: Timer?
    private var portWatcherTimer: Timer?

    // Route playback state
    private var plannedRouteSteps: [WaypointStep] = []
    private var currentRouteStepIndex: Int = 0
    private var isLoopingRoute: Bool = false

    // Active Network transport
    private var activeConnection: NWConnection?
    private var nwListener: NWListener?
    private let listenerPort: UInt16 = 9000
    private let picoIP = "192.168.7.1"
    private let networkQueue = DispatchQueue(label: "com.invis.networkQueue", qos: .userInitiated)
    private var rxBuffer = Data()

    public init() {
        startHardwareDiscovery()
        log(tag: "INFO", message: "Invis iOS Firmware Interface Initialized. Listening on port \(listenerPort).")
    }

    deinit {
        // Safe cleanup
    }

    // MARK: - Logging Helper
    public func log(tag: String, message: String) {
        let entry = ActivityLogEntry(tag: tag, message: message)
        logs.append(entry)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    public func clearLogs() {
        logs.removeAll()
    }

    // MARK: - Hardware Discovery & Auto-Connect
    public func startHardwareDiscovery() {
        setupInboundUSBListener()

        portWatcherTimer?.invalidate()
        portWatcherTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollHardwareStatus()
            }
        }
        pollHardwareStatus()
    }

    // MARK: - Inbound USB-C Listener (for MacBook usbmuxd tunnel)
    private func setupInboundUSBListener() {
        if nwListener != nil { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: listenerPort) else { return }
            let listener = try NWListener(using: params, on: port)

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.log(tag: "INFO", message: "USB listener ready on port \(self.listenerPort) (ready for Mac bridge).")
                    case .failed(let error):
                        self.log(tag: "WARN", message: "USB listener failed: \(error.localizedDescription)")
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] newConnection in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.log(tag: "INFO", message: "Incoming connection received on port \(self.listenerPort)!")
                    self.bindConnection(newConnection, transportName: "MacBook USB-C (usbmux)")
                }
            }

            listener.start(queue: networkQueue)
            self.nwListener = listener
        } catch {
            log(tag: "ERR", message: "Failed to create USB listener on port \(listenerPort): \(error.localizedDescription)")
        }
    }

    private func pollHardwareStatus() {
        if status.isConnected { return }

        // Probe Pico USB-NCM Ethernet gadget (192.168.7.1)
        if transportMode == .auto || transportMode == .picoEthernet {
            probeOutboundEndpoint(host: picoIP, port: listenerPort, transportName: "Pico Dongle (USB-NCM)")
        }

        #if targetEnvironment(simulator)
        // In simulator, probe local MacBook host
        if transportMode == .auto {
            probeOutboundEndpoint(host: "127.0.0.1", port: listenerPort, transportName: "Simulator Mock Dongle")
        }
        #endif
    }

    // MARK: - Outbound Prober (for Pico Dongle & Simulator)
    private func probeOutboundEndpoint(host: String, port: UInt16, transportName: String) {
        guard !status.isConnected, activeConnection == nil else { return }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let params = NWParameters.tcp
        let conn = NWConnection(to: endpoint, using: params)

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if self.activeConnection == nil {
                        self.log(tag: "INFO", message: "Connected to outbound endpoint \(host):\(port)")
                        self.bindConnection(conn, transportName: transportName)
                    } else {
                        conn.cancel()
                    }
                case .failed, .waiting:
                    conn.cancel()
                default:
                    break
                }
            }
        }

        conn.start(queue: networkQueue)
    }

    // MARK: - Bind Active Connection & Receive Loop
    private func bindConnection(_ conn: NWConnection, transportName: String) {
        // Disconnect previous if any
        if activeConnection !== conn {
            activeConnection?.cancel()
        }
        activeConnection = conn
        activeTransportName = transportName
        rxBuffer.removeAll()

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.activeConnection === conn else { return }
                switch state {
                case .ready:
                    self.log(tag: "INFO", message: "Physical link ready: \(transportName)")
                    self.startHeartbeat()
                    self.sendPing()
                case .failed(let error):
                    self.log(tag: "WARN", message: "Link failed: \(error.localizedDescription)")
                    self.handleDisconnect(reason: error.localizedDescription)
                case .cancelled:
                    self.handleDisconnect(reason: "Connection cancelled")
                default:
                    break
                }
            }
        }

        if conn.state == .setup {
            conn.start(queue: networkQueue)
        } else if conn.state == .ready {
            startHeartbeat()
            sendPing()
        }

        startReceiveLoop(conn)
    }

    private func startReceiveLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.activeConnection === conn else { return }

                if let data = data, !data.isEmpty {
                    self.rxBuffer.append(data)
                    while let newlineIndex = self.rxBuffer.firstIndex(of: 0x0A) { // '\n'
                        let lineData = self.rxBuffer.prefix(upTo: newlineIndex)
                        self.rxBuffer.removeSubrange(0...newlineIndex)
                        if let packetStr = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !packetStr.isEmpty {
                            self.handleIncomingPacket(packetStr)
                        }
                    }
                }

                if isComplete || error != nil {
                    self.handleDisconnect(reason: "Physical USB connection severed")
                    return
                }

                if self.activeConnection === conn {
                    self.startReceiveLoop(conn)
                }
            }
        }
    }

    // MARK: - Packet Dispatcher & Heartbeat
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendPing()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func sendPing() {
        let sentTimestamp = Date().timeIntervalSince1970
        let payload: [String: Any] = [
            "cmd": "ping",
            "ts": sentTimestamp
        ]
        sendJSON(payload)
    }

    public func sendJSON(_ dict: [String: Any]) {
        guard let conn = activeConnection else { return }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: []),
              var jsonString = String(data: jsonData, encoding: .utf8) else { return }

        jsonString += "\n"
        let data = jsonString.data(using: .utf8)!
        conn.send(content: data, completion: .contentProcessed({ _ in }))

        if let cmd = dict["cmd"] as? String, cmd != "ping" {
            log(tag: "TX", message: "[\(cmd.uppercased())] \(jsonString.trimmingCharacters(in: .newlines))")
        }
    }

    private func handleIncomingPacket(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Handle pong
        if let statusStr = dict["status"] as? String, statusStr == "pong" {
            let now = Date().timeIntervalSince1970
            let rtt: Double
            if let ts = dict["ts"] as? Double {
                rtt = max(0.5, (now - ts) * 1000.0)
            } else {
                rtt = 1.5
            }
            self.pingLatencyMs = rtt
            let version = (dict["version"] as? String) ?? "Firmware v1.3.3"

            if let devName = dict["device_name"] as? String {
                self.connectedDeviceName = devName
            }
            if let model = dict["model"] as? String {
                self.connectedDeviceModel = model
            }

            self.status = .connected(latencyMs: rtt, firmwareVersion: version, transport: self.activeTransportName)
            return
        }

        // Handle command acknowledgment
        if let cmd = dict["cmd"] as? String {
            log(tag: "RX", message: "ACK \(cmd.uppercased()): \(jsonString)")
        } else {
            log(tag: "RX", message: jsonString)
        }
    }

    private func handleDisconnect(reason: String) {
        log(tag: "WARN", message: "Disconnected: \(reason)")
        activeConnection?.cancel()
        activeConnection = nil
        rxBuffer.removeAll()
        stopHeartbeat()
        status = .disconnected(reason: reason)
    }

    public func disconnect() {
        handleDisconnect(reason: "Manually disconnected")
    }

    // MARK: - Spoofing API Commands
    /// Instant teleport to coordinate
    public func teleport(to coordinate: CLLocationCoordinate2D, altitude: Double = 15.0) {
        var finalCoord = coordinate
        if naturalDriftEnabled {
            finalCoord = LocationEngine.shared.applyMicroJitter(to: coordinate, radiusMeters: driftRadiusMeters)
        }

        currentSpoofedLocation = finalCoord
        isSpoofingActive = true

        let payload: [String: Any] = [
            "cmd": "teleport",
            "lat": finalCoord.latitude,
            "lon": finalCoord.longitude,
            "alt": altitude
        ]
        sendJSON(payload)
        log(tag: "INFO", message: "Teleported to (\(String(format: "%.6f", finalCoord.latitude)), \(String(format: "%.6f", finalCoord.longitude)))")
    }

    /// Toggles micro-jitter drift
    public func setNaturalDrift(enabled: Bool, radiusMeters: Double = 1.0) {
        self.naturalDriftEnabled = enabled
        self.driftRadiusMeters = radiusMeters

        let payload: [String: Any] = [
            "cmd": "jitter",
            "enabled": enabled,
            "radius_meters": radiusMeters
        ]
        sendJSON(payload)
        log(tag: "INFO", message: "Micro-jitter drift \(enabled ? "enabled (\(String(format: "%.1f", radiusMeters))m)" : "disabled")")
    }

    /// Reset Killswitch: safely re-enables hardware GPS
    public func resetLocation() {
        stopRoute()
        isSpoofingActive = false
        currentSpoofedLocation = nil

        let payload: [String: Any] = [
            "cmd": "reset"
        ]
        sendJSON(payload)
        log(tag: "WARN", message: "RESET KILLSWITCH TRIGGERED. Physical GPS Restored.")
    }

    // MARK: - Route Simulation Controls
    public func startRoute(
        waypoints: [CLLocationCoordinate2D],
        speedKmh: Double,
        loop: Bool = false,
        realisticTraffic: Bool = true
    ) {
        guard waypoints.count >= 2 else { return }

        // Build high-resolution timeline
        let steps = LocationEngine.shared.buildInterpolatedTimeline(
            from: waypoints,
            speedKmh: speedKmh,
            tickIntervalSec: 1.0,
            realisticTraffic: realisticTraffic
        )

        guard !steps.isEmpty else { return }

        self.plannedRouteSteps = steps
        self.currentRouteStepIndex = 0
        self.isLoopingRoute = loop
        self.isRoutePlaying = true
        self.isRoutePaused = false
        self.isSpoofingActive = true

        // Notify Pico dongle of incoming route
        let rawPoints = waypoints.map { [$0.latitude, $0.longitude] }
        let payload: [String: Any] = [
            "cmd": "route",
            "points": rawPoints,
            "speed": speedKmh,
            "loop": loop,
            "traffic": realisticTraffic,
            "jitter": naturalDriftEnabled
        ]
        sendJSON(payload)
        log(tag: "INFO", message: "Started route simulation with \(waypoints.count) waypoints (\(steps.count) timeline ticks) at \(Int(speedKmh)) km/h")

        // Run local playback synchronization
        routeTimer?.invalidate()
        routeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickRouteSimulation()
            }
        }
        tickRouteSimulation()
    }

    private func tickRouteSimulation() {
        guard isRoutePlaying, !isRoutePaused else { return }

        if currentRouteStepIndex < plannedRouteSteps.count {
            let step = plannedRouteSteps[currentRouteStepIndex]
            var coord = step.coordinate
            if naturalDriftEnabled {
                coord = LocationEngine.shared.applyMicroJitter(to: coord, radiusMeters: driftRadiusMeters)
            }

            self.currentSpoofedLocation = coord
            self.routeProgress = Double(currentRouteStepIndex) / Double(max(1, plannedRouteSteps.count - 1))
            self.routeRemainingSeconds = Double(plannedRouteSteps.count - currentRouteStepIndex)

            // Stream tick to Pico
            let payload: [String: Any] = [
                "cmd": "teleport",
                "lat": coord.latitude,
                "lon": coord.longitude,
                "heading": step.heading,
                "speed": step.speedKmh
            ]
            sendJSON(payload)

            currentRouteStepIndex += 1
        } else {
            // Route finished
            if isLoopingRoute {
                currentRouteStepIndex = 0
                log(tag: "INFO", message: "Route loop cycle completed. Replaying from start.")
            } else {
                stopRoute()
                log(tag: "INFO", message: "Route simulation completed.")
            }
        }
    }

    public func pauseRoute() {
        guard isRoutePlaying else { return }
        isRoutePaused = true
        sendJSON(["cmd": "route_control", "action": "pause"])
        log(tag: "INFO", message: "Route paused.")
    }

    public func resumeRoute() {
        guard isRoutePlaying else { return }
        isRoutePaused = false
        sendJSON(["cmd": "route_control", "action": "resume"])
        log(tag: "INFO", message: "Route resumed.")
    }

    public func stopRoute() {
        routeTimer?.invalidate()
        routeTimer = nil
        isRoutePlaying = false
        isRoutePaused = false
        routeProgress = 0.0
        routeRemainingSeconds = 0
        currentRouteStepIndex = 0
        plannedRouteSteps.removeAll()
        sendJSON(["cmd": "route_control", "action": "stop"])
    }
}
