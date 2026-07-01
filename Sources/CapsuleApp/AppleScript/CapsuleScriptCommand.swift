//
//  CapsuleScriptCommand.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  Base class for Capsule's AppleScript verbs. NSScriptCommand.performDefaultImplementation is
//  synchronous, but every Capsule action is async, so the base suspends the command, runs the
//  work on the main actor, and resumes with the result — the documented pattern for async
//  scripting commands. Subclasses live here (in CapsuleApp, so `swift build`/CI compiles them);
//  the AppleScript runtime finds each by its @objc name declared in Capsule.sdef.
//

import CapsuleAutomation
import Foundation

/// Errors surfaced to AppleScript callers (mapped to `scriptErrorString`).
enum ScriptCommandError: LocalizedError {
    case missingParameter(String)

    var errorDescription: String? {
        switch self {
        case let .missingParameter(name):
            return "The \(name) parameter is required."
        }
    }
}

/// Shared async bridge for Capsule's scripting commands.
class CapsuleScriptCommand: NSScriptCommand {
    /// Subclasses perform their async work here and return the AppleScript result (or nil).
    func run(service: any AutomationService) async throws -> Any? { nil }

    override func performDefaultImplementation() -> Any? {
        let service: any AutomationService
        do {
            service = try AutomationRuntime.requireService()
        } catch {
            fail(with: error)
            return nil
        }
        suspendExecution()
        Task { @MainActor in
            do {
                let result = try await self.run(service: service)
                self.resumeExecution(withResult: result)
            } catch {
                self.fail(with: error)
                self.resumeExecution(withResult: nil)
            }
        }
        return nil
    }

    /// Records a failure so AppleScript reports it (`errOSAScriptError` + a message).
    func fail(with error: Error) {
        scriptErrorNumber = Int(errOSAScriptError)
        scriptErrorString = error.localizedDescription
    }

    /// The command's direct parameter as a non-empty string, or throws ``ScriptCommandError``.
    func requireDirectString(_ name: String) throws -> String {
        guard let value = directParameter as? String, !value.isEmpty else {
            throw ScriptCommandError.missingParameter(name)
        }
        return value
    }

    /// A named argument as a string, or throws when required and absent/empty.
    func requireArgument(_ key: String, name: String) throws -> String {
        guard let value = evaluatedArguments?[key] as? String, !value.isEmpty else {
            throw ScriptCommandError.missingParameter(name)
        }
        return value
    }

    /// An optional named string argument.
    func optionalArgument(_ key: String) -> String? {
        (evaluatedArguments?[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
