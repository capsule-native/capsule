//
//  MachineValidationTests.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import XCTest

@testable import CapsuleDomain

final class MachineValidationTests: XCTestCase {
    func test_image() {
        XCTAssertNotNil(MachineValidation.imageProblem(""))
        XCTAssertNil(MachineValidation.imageProblem("alpine:3.22"))
    }
    func test_cpus() {
        XCTAssertNil(MachineValidation.cpusProblem(""))  // empty → default
        XCTAssertNil(MachineValidation.cpusProblem("4"))
        XCTAssertNotNil(MachineValidation.cpusProblem("0"))
        XCTAssertNotNil(MachineValidation.cpusProblem("-2"))
        XCTAssertNotNil(MachineValidation.cpusProblem("x"))
    }
    func test_memory() {
        XCTAssertNil(MachineValidation.memoryProblem(""))  // empty → default
        XCTAssertNil(MachineValidation.memoryProblem("8G"))
        XCTAssertNil(MachineValidation.memoryProblem("512M"))
        XCTAssertNotNil(MachineValidation.memoryProblem("8"))
        XCTAssertNotNil(MachineValidation.memoryProblem("lots"))
    }
    func test_homeMount() {
        XCTAssertNil(MachineValidation.homeMountProblem("rw"))
        XCTAssertNotNil(MachineValidation.homeMountProblem("maybe"))
    }
    func test_derivedName() {
        XCTAssertEqual(MachineValidation.derivedName(fromImage: "alpine:3.22"), "alpine-3-22")
        XCTAssertEqual(MachineValidation.derivedName(fromImage: "ubuntu:24.04"), "ubuntu-24-04")
        XCTAssertEqual(
            MachineValidation.derivedName(fromImage: "docker.io/library/alpine:3.22"), "alpine-3-22"
        )
    }
    func test_nameProblem() {
        XCTAssertNil(MachineValidation.nameProblem(""))  // empty → will be derived
        XCTAssertNil(MachineValidation.nameProblem("dev"))  // valid
        XCTAssertNotNil(MachineValidation.nameProblem("Dev"))  // uppercase
        XCTAssertNotNil(MachineValidation.nameProblem("a.b"))  // dot not allowed
        XCTAssertNotNil(MachineValidation.nameProblem("-x"))  // leading hyphen
        XCTAssertNotNil(MachineValidation.nameProblem("x-"))  // trailing hyphen
    }
}
