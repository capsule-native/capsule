//
//  StorageDashboardModelTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import XCTest

@testable import CapsuleDomain

@MainActor
final class StorageDashboardModelTests: XCTestCase {
    func testRefreshLoadsUsageAndRecommendsOnlyReclaimable() async {
        let backend = MockBackend()  // images & containers reclaimable > 0, volumes == 0
        let model = StorageDashboardModel(
            backend: backend, normalize: { _ in .unknown(message: "stub") })
        await model.refresh()
        guard case .loaded = model.loadState else { return XCTFail("expected loaded") }
        XCTAssertEqual(model.recommendations.map(\.category), [.images, .containers])
        XCTAssertEqual(model.totalReclaimableBytes, 974_934_016 + 454_991_872)
    }
    func testReclaimDelegatesToClosure() async {
        var reclaimed: [StorageCategory] = []
        let model = StorageDashboardModel(
            backend: MockBackend(), normalize: { _ in .unknown(message: "stub") },
            onReclaim: { reclaimed.append($0) })
        await model.refresh()
        model.reclaim(.images)
        XCTAssertEqual(reclaimed, [.images])
    }
    func testRefresh_failure_unavailable() async {
        let backend = MockBackend()
        backend.failure = .nonZeroExit(command: "system df", code: 1, stderr: "daemon down")
        let model = StorageDashboardModel(
            backend: backend, normalize: { _ in .unknown(message: "stub") })
        await model.refresh()
        if case .unavailable = model.loadState {} else { XCTFail("expected .unavailable") }
    }
}
