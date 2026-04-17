//
//  WebSocketClient.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-10.
//

import Foundation
import Combine
import FirebaseAuth

/// A robust WebSocket client using `URLSessionWebSocketTask`.
///
/// Connects to the Go backend's WebSocket Hub, continuously listens for
/// incoming `WSEvent` JSON messages, and publishes them via a Combine subject.
/// Includes automatic reconnection with exponential backoff.
final class WebSocketClient: ObservableObject {

    // MARK: - Public Interface

    /// Publishes decoded `WSEvent` objects received from the server.
    let eventSubject = PassthroughSubject<WSEvent, Never>()

    /// Whether the WebSocket transport layer is active.
    @Published private(set) var isConnected: Bool = false

    /// Whether we have confirmed server reachability (first successful message received).
    @Published private(set) var isConnectedToServer: Bool = false

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private let baseURL: String

    /// Controls reconnection backoff (seconds).
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0

    /// Prevents multiple concurrent reconnect attempts.
    private var isReconnecting: Bool = false

    /// Combine-driven keep-alive ping timer.
    private var pingCancellable: AnyCancellable?

    /// Whether reconnect attempts are allowed.
    private var shouldReconnect: Bool = true

    /// True while an async connect/token-fetch flow is running.
    private var isConnecting: Bool = false

    /// Connect attempt identity to prevent stale async connect completion.
    private var activeConnectID: UUID?

    // MARK: - Init

    init(baseURL: String = Config.wsBaseURL) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Connection Lifecycle

    /// Opens the WebSocket connection and starts the receive loop.
    func connect(forceReconnect: Bool = false) {
        shouldReconnect = true

        if forceReconnect, webSocketTask != nil {
            pingCancellable?.cancel()
            pingCancellable = nil
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
            isConnected = false
            isConnectedToServer = false
            isConnecting = false
            activeConnectID = nil
        }

        guard webSocketTask == nil else { return }
        guard !isConnecting else { return }

        guard let currentUser = Auth.auth().currentUser else {
            print("[WS] Connection aborted: User session not ready.")
            return
        }
        _ = currentUser

        isConnecting = true
        let connectID = UUID()
        activeConnectID = connectID

        Task { [weak self] in
            guard let self = self else { return }
            defer { self.isConnecting = false }

            let token: String
            do {
                token = try await AuthManager.getIDToken()
            } catch {
                print("[WS] Token fetch failed: \(error.localizedDescription)")
                return
            }

            guard self.activeConnectID == connectID else { return }
            guard self.shouldReconnect else { return }
            guard self.webSocketTask == nil else { return }

            let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
            let urlString = self.baseURL + "?token=\(encodedToken)"

            guard let url = URL(string: urlString) else {
                print("[WS] Invalid URL for connect")
                return
            }

            var request = URLRequest(url: url)
            request.setValue("iOS", forHTTPHeaderField: "X-Client-Type")

            let task = self.session.webSocketTask(with: request)
            self.webSocketTask = task
            task.resume()

            self.isReconnecting = false

            print("[WS] Connected to \(urlString)")
            self.receiveLoop(task: task)
            self.startPingTimer()
        }
    }

    /// Gracefully closes the WebSocket connection.
    func disconnect(reason: String? = nil) {
        shouldReconnect = false
        activeConnectID = nil
        isConnecting = false
        isReconnecting = false

        pingCancellable?.cancel()
        pingCancellable = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)

        if let reason {
            print("[WS] Connection explicitly closed (\(reason)).")
        } else {
            print("[WS] Connection explicitly closed.")
        }

        webSocketTask = nil
        isConnected = false
        isConnectedToServer = false
        print("[WS] Disconnected")
    }

    // MARK: - Receive Loop

    /// Continuously listens for incoming messages and decodes them as `WSEvent`.
    private func receiveLoop(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self = self else { return }
            guard self.webSocketTask === task else { return }

            switch result {
            case .success(let message):
                // Server confirmed reachable on first successful receive
                if !self.isConnectedToServer {
                    DispatchQueue.main.async { self.isConnectedToServer = true }
                }

                if !self.isConnected {
                    DispatchQueue.main.async { self.isConnected = true }
                    self.reconnectDelay = 1.0
                }

                self.handleMessage(message)
                self.receiveLoop(task: task)

            case .failure(let error):
                let shouldAttemptReconnect = self.shouldReconnect
                print("[WS] Receive error: \(error.localizedDescription) [reconnect=\(shouldAttemptReconnect)]")
                self.handleDisconnect(unexpected: shouldAttemptReconnect)
            }
        }
    }

    /// Parses the incoming WebSocket message into a `WSEvent`.
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            guard let d = text.data(using: .utf8) else { return }
            data = d
        case .data(let d):
            data = d
        @unknown default:
            return
        }

        do {
            let event = try JSONDecoder().decode(WSEvent.self, from: data)
            print("[WS] Event received: \(event.type)")
            DispatchQueue.main.async {
                self.eventSubject.send(event)
            }
        } catch {
            print("[WS] JSON decode error: \(error.localizedDescription)")
        }
    }

    // MARK: - Keep-Alive Ping (25s for Cloud Run)

    /// Starts a Combine timer that sends a WebSocket ping every 25 seconds.
    /// Keeps the Cloud Run load balancer from killing the idle connection.
    private func startPingTimer() {
        pingCancellable?.cancel()
        pingCancellable = Timer
            .publish(every: 25.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.webSocketTask != nil else {
                    self?.pingCancellable?.cancel()
                    self?.pingCancellable = nil
                    return
                }
                self.webSocketTask?.sendPing { error in
                    if let error = error {
                        let shouldAttemptReconnect = self.shouldReconnect
                        print("[WS] Ping failed: \(error.localizedDescription) [reconnect=\(shouldAttemptReconnect)]")
                        self.pingCancellable?.cancel()
                        self.pingCancellable = nil
                        self.handleDisconnect(unexpected: shouldAttemptReconnect)
                        return
                    }

                    if !self.isConnected {
                        DispatchQueue.main.async { self.isConnected = true }
                        self.reconnectDelay = 1.0
                    }
                }
            }
    }

    // MARK: - Reconnection

    /// Handles an unexpected disconnection and triggers reconnect.
    private func handleDisconnect(unexpected: Bool) {
        pingCancellable?.cancel()
        pingCancellable = nil
        activeConnectID = nil
        isConnecting = false

        let shouldAttemptReconnect = unexpected && shouldReconnect

        DispatchQueue.main.async {
            self.webSocketTask = nil
            self.isConnected = false
            self.isConnectedToServer = false

            guard shouldAttemptReconnect else {
                print("[WS] Reconnect skipped (unexpected=\(unexpected), shouldReconnect=\(self.shouldReconnect))")
                return
            }

            self.attemptReconnect()
        }
    }

    /// Reconnects with exponential backoff.
    private func attemptReconnect() {
        guard shouldReconnect else { return }
        guard webSocketTask == nil else { return }
        guard !isConnecting else { return }
        guard !isReconnecting else { return }
        isReconnecting = true

        let delay = reconnectDelay
        print("[WS] Reconnecting in \(delay)s...")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.isReconnecting = false

            guard self.shouldReconnect else { return }
            guard self.webSocketTask == nil else { return }

            // Double the delay for next attempt, capped
            self.reconnectDelay = min(self.reconnectDelay * 2, self.maxReconnectDelay)

            DispatchQueue.main.async {
                self.connect()
            }
        }
    }
}
