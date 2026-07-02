//
//  ContainerCLIReleaseTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleBackend

final class ContainerCLIReleaseTests: XCTestCase {
    private func asset(_ name: String) -> ContainerCLIReleaseAsset {
        ContainerCLIReleaseAsset(name: name, downloadURL: "https://example.com/\(name)")
    }

    func testPrefersUnversionedSignedPackage() {
        let release = ContainerCLIRelease(
            tag: "1.0.0",
            assets: [
                asset("container-1.0.0-installer-signed.pkg"),
                asset("container-installer-signed.pkg"),
            ])
        XCTAssertEqual(release.signedInstallerAsset?.name, "container-installer-signed.pkg")
    }

    func testFallsBackToVersionedSignedPackage() {
        let release = ContainerCLIRelease(
            tag: "1.0.0",
            assets: [
                asset("container-dSYM.zip"),
                asset("container-installer-unsigned.pkg"),
                asset("container-1.0.0-installer-signed.pkg"),
            ])
        XCTAssertEqual(
            release.signedInstallerAsset?.name, "container-1.0.0-installer-signed.pkg")
    }

    func testNeverSelectsUnsignedPackage() {
        let release = ContainerCLIRelease(
            tag: "1.0.0",
            assets: [asset("container-installer-unsigned.pkg"), asset("container-dSYM.zip")])
        XCTAssertNil(release.signedInstallerAsset)
    }

    func testMockStreamsSeededLinesAndWritesDestination() async throws {
        let mock = MockContainerReleaseSource()
        let release = try await mock.latestRelease()
        XCTAssertEqual(release.tag, "1.2.3")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("capsule-test-\(UUID().uuidString).pkg")
        defer { try? FileManager.default.removeItem(at: destination) }
        var lines: [String] = []
        let signed = try XCTUnwrap(release.signedInstallerAsset)
        for try await line in mock.downloadPackage(signed, to: destination) {
            lines.append(line.text)
        }
        XCTAssertEqual(lines.last, "100%")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(mock.lastDownloadedAsset?.name, signed.name)
    }

    func testMockFailurePropagates() async {
        let mock = MockContainerReleaseSource()
        mock.failure = .network(message: "offline")
        do {
            _ = try await mock.latestRelease()
            XCTFail("expected a throw")
        } catch let error as ContainerReleaseError {
            XCTAssertEqual(error, .network(message: "offline"))
        } catch { XCTFail("unexpected error \(error)") }
    }
}
