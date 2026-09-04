//
//  WiredConnectionManager.swift
//  invis
//
//  Wired Physical Connection Manager for Raspberry Pi Pico Dongle.
//  Strictly communicates over physical wired USB:
//  - macOS: Direct USB CDC-ACM Virtual Serial (/dev/cu.usbmodem*) via POSIX termios
//  - iOS: USB CDC-NCM Ethernet-over-USB via Link-Local TCP/HTTP (192.168.7.1)
//

import Foundation
import CoreLocation
import Combine
import Network

#if os(macOS)
import Darwin
#endif

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
        case .connecting: return "Connecting to Pico..."
        case .connected: return "Pico Dongle Connected"
        }
    }
}

// MARK: - Transport Mode
public enum TransportMode: String, CaseIterable, Sendable {
    case auto = "Auto Detect"
    case usbSerial = "USB Serial (CDC-ACM)"
    case usbEthernet = "USB Ethernet (CDC-NCM)"
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

    // Network transport (iOS / NCM)
    private var nwConnection: NWConnection?
    private let picoIP = "192.168.7.1"
    private let picoTCPPort: UInt16 = 9000
    private let picoHTTPPort: UInt16 = 8080

    #if os(macOS)
    // POSIX Serial transport (macOS / CDC-ACM)
    private var serialFileDescriptor: Int32 = -1
    private var activePortPath: String?
    private let serialReadQueue = DispatchQueue(label: "com.invis.serialReadQueue", qos: .userInitiated)
    private nonisolated(unsafe) var isReadingSerial = false
    #endif

    public init() {
        startHardwareDiscovery()
        log(tag: "INFO", message: "Invis Location Engine Initialized. Ready for wired USB connection.")
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
        portWatcherTimer?.invalidate()
        portWatcherTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollHardwareStatus()
            }
        }
        pollHardwareStatus()
    }

    private func pollHardwareStatus() {
        if status.isConnected { return }

        #if os(macOS)
        if transportMode == .auto || transportMode == .usbSerial {
            if let port = scanForPicoSerialPort() {
                connectSerial(portPath: port)
                return
            }
        }
        #endif

        #if os(macOS)
        probeUsbEthernet(host: "127.0.0.1")
        #else
        if transportMode == .auto || transportMode == .usbEthernet {
            probeUsbEthernet(host: "192.168.7.1")
        }
        #endif
    }

    // MARK: - macOS POSIX Serial Implementation (CDC-ACM)
    #if os(macOS)
    private func scanForPicoSerialPort() -> String? {
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(atPath: "/dev")
            // Raspberry Pi Pico USB CDC-ACM presents as /dev/cu.usbmodem*
            let modemPorts = files.filter { $0.hasPrefix("cu.usbmodem") || $0.hasPrefix("cu.usbserial") }
            if let first = modemPorts.first {
                return "/dev/" + first
            }
        } catch {
            log(tag: "ERR", message: "Failed to scan /dev: \(error.localizedDescription)")
        }
        return nil
    }

    public func connectSerial(portPath: String) {
        closeSerial()
        status = .connecting(detail: "Opening \(portPath)...")
        log(tag: "INFO", message: "Connecting to USB CDC-ACM device at \(portPath)")

        let fd = open(portPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            status = .disconnected(reason: "Failed to open \(portPath)")
            log(tag: "ERR", message: "POSIX open() error \(errno): \(String(cString: strerror(errno)))")
            return
        }

        // Configure termios for 115200 8N1 raw mode
        var tty = termios()
        if tcgetattr(fd, &tty) != 0 {
            close(fd)
            status = .disconnected(reason: "tcgetattr failed")
            log(tag: "ERR", message: "tcgetattr error \(errno)")
            return
        }

        cfsetispeed(&tty, speed_t(B115200))
        cfsetospeed(&tty, speed_t(B115200))

        // 8-bit chars, disable parity, 1 stop bit
        tty.c_cflag = (tty.c_cflag & ~tcflag_t(PARENB | CSTOPB | CSIZE)) | tcflag_t(CS8 | CLOCAL | CREAD)
        tty.c_iflag = 0
        tty.c_oflag = 0
        tty.c_lflag = 0

        // Non-blocking reads
        tty.c_cc.16 = 0 // VMIN
        tty.c_cc.17 = 1 // VTIME (0.1s timeout)

        if tcsetattr(fd, TCSANOW, &tty) != 0 {
            close(fd)
            status = .disconnected(reason: "tcsetattr failed")
            log(tag: "ERR", message: "tcsetattr error \(errno)")
            return
        }

        self.serialFileDescriptor = fd
        self.activePortPath = portPath
        self.activeTransportName = "USB CDC-ACM (\(portPath))"

        startSerialReadLoop()
        startHeartbeat()
        sendPing()
    }

    private func closeSerial() {
        isReadingSerial = false
        if serialFileDescriptor >= 0 {
            close(serialFileDescriptor)
            serialFileDescriptor = -1
        }
        activePortPath = nil
    }

    private func startSerialReadLoop() {
        guard serialFileDescriptor >= 0 else { return }
        isReadingSerial = true
        let fd = self.serialFileDescriptor

        serialReadQueue.async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 1024)
            var lineAccumulator = Data()

            while let self = self, self.isReadingSerial {
                let bytesRead = read(fd, &buffer, buffer.count)
                if bytesRead > 0 {
                    let chunk = Data(buffer[0..<bytesRead])
                    lineAccumulator.append(chunk)

                    // Extract newline delimited lines
                    while let newlineIndex = lineAccumulator.firstIndex(of: 0x0A) {
                        let lineData = lineAccumulator.subdata(in: 0..<newlineIndex)
                        lineAccumulator.removeSubrange(0...newlineIndex)

                        if let lineString = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !lineString.isEmpty {
                            Task { @MainActor in
                                self.handleIncomingPacket(lineString)
                            }
                        }
                    }
                } else if bytesRead < 0 && errno != EAGAIN {
                    // Cable was disconnected
                    Task { @MainActor in
                        self.handleCableDisconnect(reason: "Physical USB connection severed")
                    }
                    break
                }
                usleep(20_000) // 20ms poll
            }
        }
    }
    #endif

    // MARK: - iOS & Network Transport Implementation (CDC-NCM / Local Emulator)
    private func probeUsbEthernet(host: String = "192.168.7.1") {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: picoTCPPort)!)
        let params = NWParameters.tcp
        let conn = NWConnection(to: endpoint, using: params)

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.nwConnection = conn
                    self.activeTransportName = host == "127.0.0.1" ? "iPhone USB Direct (CoreDevice / usbmux)" : "USB CDC-NCM Ethernet (\(host):\(self.picoTCPPort))"
                    self.startNetworkReceiveLoop()
                    self.startHeartbeat()
                    self.sendPing()
                case .waiting(let error):
                    conn.cancel()
                    if host == "192.168.7.1" {
                        self.probeUsbEthernet(host: "127.0.0.1")
                    } else {
                        if !self.status.isConnected {
                            self.status = .disconnected(reason: "Plug in iPhone or Raspberry Pi Pico via USB")
                        }
                    }
                case .failed(let error):
                    conn.cancel()
                    if host == "192.168.7.1" {
                        // Fallback: check if local mock emulator is running on MacBook
                        self.probeUsbEthernet(host: "127.0.0.1")
                    } else {
                        if !self.status.isConnected {
                            self.status = .disconnected(reason: "Plug in iPhone or Raspberry Pi Pico via USB")
                        }
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }

        let queue = DispatchQueue(label: "com.invis.networkQueue")
        conn.start(queue: queue)
    }

    private func startNetworkReceiveLoop() {
        guard let conn = nwConnection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let data = data, let packetStr = String(data: data, encoding: .utf8) {
                    let lines = packetStr.components(separatedBy: "\n")
                    for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        self.handleIncomingPacket(line)
                    }
                }
                if isComplete || error != nil {
                    self.handleCableDisconnect(reason: "Wired network endpoint disconnected")
                    return
                }
                if self.nwConnection != nil {
                    self.startNetworkReceiveLoop()
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
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: []),
              var jsonString = String(data: jsonData, encoding: .utf8) else { return }

        jsonString += "\n"

        // macOS Serial
        #if os(macOS)
        if serialFileDescriptor >= 0 {
            let bytes = Array(jsonString.utf8)
            bytes.withUnsafeBufferPointer { ptr in
                _ = write(self.serialFileDescriptor, ptr.baseAddress, bytes.count)
            }
            if let cmd = dict["cmd"] as? String, cmd != "ping" {
                log(tag: "TX", message: "[\(cmd.uppercased())] \(jsonString.trimmingCharacters(in: .newlines))")
            }
            return
        }
        #endif

        // iOS / Network Socket
        if let conn = nwConnection {
            let data = jsonString.data(using: .utf8)!
            conn.send(content: data, completion: .contentProcessed({ _ in }))
            if let cmd = dict["cmd"] as? String, cmd != "ping" {
                log(tag: "TX", message: "[\(cmd.uppercased())] \(jsonString.trimmingCharacters(in: .newlines))")
            }
            return
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
                rtt = 1.8
            }
            self.pingLatencyMs = rtt
            let version = (dict["version"] as? String) ?? "RP2040 v1.3.3"
            
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

    private func handleCableDisconnect(reason: String) {
        log(tag: "WARN", message: "Cable disconnected: \(reason)")
        #if os(macOS)
        closeSerial()
        #endif
        nwConnection?.cancel()
        nwConnection = nil
        stopHeartbeat()
        status = .disconnected(reason: reason)

        // Failsafe: hold last location state without crash
    }

    public func disconnect() {
        #if os(macOS)
        closeSerial()
        #endif
        nwConnection?.cancel()
        nwConnection = nil
        stopHeartbeat()
        status = .disconnected(reason: "Manually disconnected")
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
