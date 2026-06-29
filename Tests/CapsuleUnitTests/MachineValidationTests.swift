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
}
