//
//  DNSModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Local DNS domain management: an unprivileged list (empty vs. failure) plus create/delete
//  that hand the privileged argv to an injected Terminal closure — never the backend.

import CapsuleBackend
import CapsuleDiagnostics
import XCTest

@testable import CapsuleDomain

@MainActor
final class DNSModelTests: XCTestCase {
    func testRefreshLoadsDomains() async {
        let backend = MockBackend(
            dnsDomains: [DNSDomainSummary(domain: "test", localhostIP: "127.0.0.1")])
        let model = DNSModel(backend: backend, runPrivilegedInTerminal: { _ in })

        await model.refresh()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.domains.map(\.domain), ["test"])
        XCTAssertEqual(model.domains.first?.localhostIP, "127.0.0.1")
    }

    func testRefreshEmptyIsLoadedNotUnavailable() async {
        let backend = MockBackend(dnsDomains: [])
        let model = DNSModel(backend: backend, runPrivilegedInTerminal: { _ in })

        await model.refresh()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(
            model.domains.isEmpty, "an empty list is loaded, rendered 'No local DNS domains'")
    }

    func testRefreshFailureIsUnavailableNotEmpty() async {
        let backend = MockBackend(dnsDomains: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container system dns list", code: 1, stderr: "Connection refused")
        let model = DNSModel(backend: backend, runPrivilegedInTerminal: { _ in })

        await model.refresh()

        guard case .unavailable = model.loadState else {
            return XCTFail("a load failure must be .unavailable, not an empty list")
        }
    }

    func testRefreshSurfacesPermissionRequired() async {
        let backend = MockBackend(dnsDomains: [])
        backend.failure = BackendError.nonZeroExit(
            command: "container system dns list", code: 1,
            stderr: "must run as an administrator")
        let model = DNSModel(
            backend: backend,
            normalize: { ErrorNormalizer.normalize($0) },
            runPrivilegedInTerminal: { _ in })

        await model.refresh()

        guard case let .unavailable(detail) = model.loadState else {
            return XCTFail("expected .unavailable")
        }
        XCTAssertEqual(detail.title, "Administrator access required")
        XCTAssertTrue(detail.recoveryActions.contains(.grantPermission(.administrator)))
    }
}
