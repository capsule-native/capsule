//
//  LibexecPluginScanner.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The concrete `PluginDiscovering` for the composition root. It scans the two libexec
//  plugin directories the `container` resolver itself names and surfaces each `container-*`
//  executable as a plugin. It lives here (not the domain) so the filesystem walk stays out of
//  `CapsuleDomain`, which must remain Process- and IO-free.

import CapsuleDomain
import Foundation

struct LibexecPluginScanner: PluginDiscovering {
    private let directories: [String]
    private let fileManager: FileManager

    init(
        directories: [String] = [
            "/usr/local/libexec/container-plugins",
            "/usr/local/libexec/container/plugins",
        ],
        fileManager: FileManager = .default
    ) {
        self.directories = directories
        self.fileManager = fileManager
    }

    func installedPlugins() -> [PluginInfo] {
        let prefix = "container-"
        var seen: Set<String> = []
        var result: [PluginInfo] = []
        for directory in directories {
            let entries = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
            for entry in entries.sorted() where entry.hasPrefix(prefix) {
                let path = (directory as NSString).appendingPathComponent(entry)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                    !isDirectory.boolValue,
                    fileManager.isExecutableFile(atPath: path)
                else { continue }
                let name = String(entry.dropFirst(prefix.count))
                guard !name.isEmpty, seen.insert(name).inserted else { continue }
                result.append(PluginInfo(name: name, path: path))
            }
        }
        return result
    }
}
