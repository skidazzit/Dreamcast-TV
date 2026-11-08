// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Foundation
import Security

/// The website's approved account values. Never print or log this value.
nonisolated struct MovieBoxWebSession: Codable, Sendable, Equatable {
    let ui: String
    let ci: String?

    init?(ui: String, ci: String?) {
        let cleanUI = ui.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUI.isEmpty, cleanUI.count <= 4096 else { return nil }
        if let ci, ci.count > 4096 { return nil }
        self.ui = cleanUI
        self.ci = ci?.isEmpty == true ? nil : ci
    }
}

nonisolated enum MovieBoxWebSessionStore {
    private static let service = "com.dreamcast.moviebox.web"
    private static let account = "approved-session"

    private static var key: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> MovieBoxWebSession? {
        var query = key
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(MovieBoxWebSession.self, from: data)
    }

    static func save(_ session: MovieBoxWebSession) throws {
        let data = try JSONEncoder().encode(session)
        var attributes = key
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess { return }
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            guard SecItemUpdate(key as CFDictionary, update as CFDictionary) == errSecSuccess else {
                throw MovieBoxWebSessionError.storageFailed
            }
            return
        }
        throw MovieBoxWebSessionError.storageFailed
    }

    static func clear() throws {
        let status = SecItemDelete(key as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MovieBoxWebSessionError.storageFailed
        }
    }
}

nonisolated enum MovieBoxWebSessionError: LocalizedError, Sendable {
    case storageFailed

    var errorDescription: String? {
        "Could not save or remove the MovieBox login. Please try again."
    }
}
