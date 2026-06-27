//
//  OutputParser.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//

import CapsuleBackend
import Foundation

/// Parses CLI stdout into backend value types.
public enum OutputParser {
    public static func parseContainers(json data: Data) throws -> [ContainerSummary] {
        do {
            return try JSONDecoder().decode([ContainerSummary].self, from: data)
        } catch {
            throw BackendError.decodingFailed(String(describing: error))
        }
    }

    public static func parseImages(json data: Data) throws -> [ImageSummary] {
        do {
            return try JSONDecoder().decode([ImageSummary].self, from: data)
        } catch {
            throw BackendError.decodingFailed(String(describing: error))
        }
    }
}
