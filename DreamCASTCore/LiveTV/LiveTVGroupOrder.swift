// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2026 DreamCAST TV contributors

import Foundation

/// One saved order for Live TV category groups across playlist refreshes.
/// New groups are appended alphabetically; removed groups are ignored until they return.
enum LiveTVGroupOrder {
    static let storageKey = "liveTVPlaylistGroupOrder"

    static func saved() -> [String] {
        guard let data = UserDefaults.standard.string(forKey: storageKey)?.data(using: .utf8),
              let names = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return names
    }

    nonisolated static func ordered(_ groups: [String], saved: [String]) -> [String] {
        let available = Set(groups.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        var seen = Set<String>()
        let preferred = saved.filter { available.contains($0) && seen.insert($0).inserted }
        return preferred + available.subtracting(seen).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func move(_ group: String, up: Bool, among groups: [String]) {
        var current = ordered(groups, saved: saved())
        guard let index = current.firstIndex(of: group) else { return }
        let next = index + (up ? -1 : 1)
        guard current.indices.contains(next) else { return }
        current.swapAt(index, next)
        save(current)
    }

    static func save(_ orderedGroups: [String]) {
        guard let data = try? JSONEncoder().encode(orderedGroups),
              let value = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(value, forKey: storageKey)
    }
}
