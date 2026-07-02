//
//  StubHTTPDataFetcher.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  An `HTTPDataFetching` test double that replays canned `(Data, HTTPURLResponse)` pairs
//  (or a seeded error) and records every `URLRequest` it receives, so `DockerHubClient`
//  can be exercised end-to-end (URL building → decoding → error mapping) without ever
//  touching the network — mirroring `StubProcessRunner` for the CLI adapter.

import Foundation

@testable import CapsuleRegistryClient

final class StubHTTPDataFetcher: HTTPDataFetching, @unchecked Sendable {
    private let lock = NSLock()

    /// FIFO queue of canned responses consumed one per `data(for:)` call; when it runs
    /// dry, the last-seeded response is repeated so single-seed tests stay terse.
    private var responses: [(Data, HTTPURLResponse)] = []
    /// When set, `data(for:)` throws this instead of returning a response.
    var error: Error?

    private var recorded: [URLRequest] = []

    /// Every request the stub has been asked to perform, in call order.
    var requests: [URLRequest] {
        withLock { recorded }
    }

    var lastRequest: URLRequest? {
        withLock { recorded.last }
    }

    /// Enqueues one canned response, force-building the `HTTPURLResponse` (fine in tests).
    func seed(
        _ data: Data, status: Int = 200, headers: [String: String]? = nil,
        url: URL = URL(string: "https://hub.docker.com/")!
    ) {
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        withLock { responses.append((data, response)) }
    }

    /// Convenience for seeding a UTF-8 JSON body.
    func seed(json: String, status: Int = 200, headers: [String: String]? = nil) {
        seed(Data(json.utf8), status: status, headers: headers)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next = try withLock { () throws -> (Data, HTTPURLResponse) in
            recorded.append(request)
            if let error { throw error }
            guard let first = responses.first else {
                throw URLError(.resourceUnavailable)  // test forgot to seed a response
            }
            if responses.count > 1 { responses.removeFirst() }
            return first
        }
        return next
    }

    /// Synchronous critical section — keeps `NSLock` out of `async` contexts.
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
