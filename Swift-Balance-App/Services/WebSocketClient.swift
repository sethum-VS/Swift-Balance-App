//
//  WebSocketClient.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-10.
//

import Foundation
import Combine

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
    private let url: URL

    /// Controls reconnection backoff (seconds).
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0

    /// Prevents multiple concurrent reconnect attempts.
    private var isReconnecting: Bool = false

    // MARK: - Init

    init(url: URL = URL(string: APIConfig.wsURL)!) {
        self.url = url
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Connection Lifecycle

    /// Opens the WebSocket connection and starts the receive loop.
    func connect() {
        guard webSocketTask == nil else { return }

        var request = URLRequest(url: url)
        request.setValue("iOS", forHTTPHeaderField: "X-Client-Type")

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        isConnected = true
        reconnectDelay = 1.0
        isReconnecting = false

        print("[WS] Connected to \(url.absoluteString)")
        receiveLoop()
        schedulePing()
    }

    /// Gracefully closes the WebSocket connection.
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        isConnectedToServer = false
        isReconnecting = false
        print("[WS] Disconnected")
    }

    // MARK: - Receive Loop

    /// Continuously listens for incoming messages and decodes them as `WSEvent`.
    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                // Server confirmed reachable on first successful receive
                if !self.isConnectedToServer {
                    DispatchQueue.main.async { self.isConnectedToServer = true }
                }
                self.handleMessage(message)
                self.receiveLoop()

            case .failure(let error):
                print("[WS] Receive error: \(error.localizedDescription)")
                self.handleDisconnect()
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

    // MARK: - Keep-Alive Ping

    /// Sends a ping every 30 seconds to keep the connection alive.
    private func schedulePing() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self, self.isConnected else { return }
            self.webSocketTask?.sendPing { error in
                if let error = error {
                    print("[WS] Ping failed: \(error.localizedDescription)")
                    self.handleDisconnect()
                } else {
                    self.schedulePing()
                }
            }
        }
    }

    // MARK: - Reconnection

    /// Handles an unexpected disconnection and triggers reconnect.
    private func handleDisconnect() {
        DispatchQueue.main.async {
            self.webSocketTask = nil
            self.isConnected = false
            self.isConnectedToServer = false
        }
        attemptReconnect()
    }

    /// Reconnects with exponential backoff.
    private func attemptReconnect() {
        guard !isReconnecting else { return }
        isReconnecting = true

        print("[WS] Reconnecting in \(reconnectDelay)s...")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            guard let self = self else { return }
            self.isReconnecting = false

            // Double the delay for next attempt, capped
            self.reconnectDelay = min(self.reconnectDelay * 2, self.maxReconnectDelay)

            DispatchQueue.main.async {
                self.connect()
            }
        }
    }
}
