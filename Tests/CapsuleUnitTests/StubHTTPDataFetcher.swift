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
    /// Routed responses, served (without consuming the FIFO queue) when the request URL
    /// contains the key — `searchRepositories` issues two CONCURRENT requests (v2 search
    /// + v3 logo index), so per-endpoint pairing must not depend on arrival order.
    private var routes: [(match: String, data: Data, response: HTTPURLResponse)] = []
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

    /// The first recorded request whose URL contains `match` — order-independent lookup
    /// for tests exercising the concurrent two-request search path.
    func request(withURLContaining match: String) -> URLRequest? {
        withLock { recorded.first { $0.url?.absoluteString.contains(match) == true } }
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

    /// Seeds a response served to any request whose URL contains `match` (first match
    /// wins, checked before the FIFO queue).
    func seed(
        _ data: Data, status: Int = 200, headers: [String: String]? = nil,
        whenURLContains match: String
    ) {
        let response = HTTPURLResponse(
            url: URL(string: "https://hub.docker.com/")!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: headers)!
        withLock { routes.append((match, data, response)) }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next = try withLock { () throws -> (Data, HTTPURLResponse) in
            recorded.append(request)
            if let error { throw error }
            if let url = request.url?.absoluteString,
                let route = routes.first(where: { url.contains($0.match) })
            {
                return (route.data, route.response)
            }
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
