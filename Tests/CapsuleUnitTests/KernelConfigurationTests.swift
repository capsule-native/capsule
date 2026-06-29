//
//  KernelConfigurationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  TDD — argv assertions for KernelConfiguration. Run RED before the value types exist,
//  then GREEN once Step 3 lands.

import CapsuleBackend
import XCTest

final class KernelConfigurationTests: XCTestCase {

    func testRecommendedArgvIgnoresOtherFlagsExceptForce() {
        let argv = KernelConfiguration(source: .recommended, arch: .arm64, force: false).arguments
        XCTAssertEqual(argv, ["system", "kernel", "set", "--recommended"])
    }

    func testLocalBinaryArgv() {
        let argv = KernelConfiguration(
            source: .localBinary(path: "/k/vmlinux"), arch: .arm64, force: true
        ).arguments
        XCTAssertEqual(
            argv,
            ["system", "kernel", "set", "--arch", "arm64", "--binary", "/k/vmlinux", "--force"])
    }

    func testRemoteTarArgvWithMember() {
        let argv = KernelConfiguration(
            source: .remoteTar(url: "https://x/k.tar", member: "boot/vmlinux"),
            arch: .amd64,
            force: false
        ).arguments
        XCTAssertEqual(
            argv,
            [
                "system", "kernel", "set", "--arch", "amd64", "--tar", "https://x/k.tar",
                "--binary", "boot/vmlinux",
            ])
    }

    func testRemoteTarArgvWithoutMember() {
        let argv = KernelConfiguration(
            source: .remoteTar(url: "https://x/k.tar", member: nil),
            arch: .amd64,
            force: false
        ).arguments
        XCTAssertEqual(
            argv,
            ["system", "kernel", "set", "--arch", "amd64", "--tar", "https://x/k.tar"])
    }

    func testRecommendedWithForce() {
        let argv = KernelConfiguration(source: .recommended, arch: .amd64, force: true).arguments
        XCTAssertEqual(argv, ["system", "kernel", "set", "--recommended", "--force"])
    }

    func testKernelArchIsCaseIterable() {
        XCTAssertEqual(KernelArch.allCases.count, 2)
        XCTAssertTrue(KernelArch.allCases.contains(.arm64))
        XCTAssertTrue(KernelArch.allCases.contains(.amd64))
    }

    func testKernelSourceIsEquatable() {
        XCTAssertEqual(KernelSource.recommended, KernelSource.recommended)
        XCTAssertEqual(
            KernelSource.localBinary(path: "/k/vmlinux"),
            KernelSource.localBinary(path: "/k/vmlinux"))
        XCTAssertNotEqual(KernelSource.recommended, KernelSource.localBinary(path: "/k/vmlinux"))
    }
}
