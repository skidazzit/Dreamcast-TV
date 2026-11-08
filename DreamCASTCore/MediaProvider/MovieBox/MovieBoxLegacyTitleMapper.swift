// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Foundation

/// Offline decoder for candidate field names found in the 16.5 iOS IPA.
/// This is not proof of the service's JSON response shape. Nothing here makes
/// requests, signs messages, or grants playback access.
nonisolated enum MovieBoxLegacyTitleMappingError: Error, Equatable {
    case missingIdentifier
    case missingTitle
}

nonisolated enum MovieBoxLegacyTitleMapper {
    static func decode(_ data: Data, kind: MovieBoxTitleKind) throws -> MovieBoxCatalogTitle {
        let record = try JSONDecoder().decode(Record.self, from: data)
        let candidateIDs = [record.id?.value, record.mid?.value, record.tid?.value, record.mb_id?.value]
        let validIDs = candidateIDs.compactMap { $0 }.filter { !$0.isEmpty }
        guard let id = validIDs.first else {
            throw MovieBoxLegacyTitleMappingError.missingIdentifier
        }
        let cleanedTitle = record.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title = cleanedTitle, !title.isEmpty else {
            throw MovieBoxLegacyTitleMappingError.missingTitle
        }
        let artwork = [record.thumbs, record.thumbs_min, record.thumbs_org, record.poster]
            .compactMap { raw -> URL? in
                if let raw, let url = URL(string: raw),
                   url.scheme?.lowercased() == "https", url.host != nil {
                    return url
                }
                return nil
            }
            .first

        let year = record.released.flatMap { Int($0.value.prefix(4)) }
        return MovieBoxCatalogTitle(
            id: id, kind: kind, title: title,
            synopsis: record.synopsis, releaseYear: year,
            posterURL: artwork
        )
    }

    private struct Record: Decodable {
        let id: StringOrInteger?
        let mid: StringOrInteger?
        let tid: StringOrInteger?
        let mb_id: StringOrInteger?
        let title: String?
        let synopsis: String?
        let released: StringOrInteger?
        let poster: String?
        let thumbs: String?
        let thumbs_min: String?
        let thumbs_org: String?
    }

    private struct StringOrInteger: Decodable {
        let value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                value = text
            } else if let number = try? container.decode(Int64.self) {
                value = String(number)
            } else {
                throw DecodingError.typeMismatch(
                    Self.self,
                    .init(codingPath: decoder.codingPath, debugDescription: "Expected a string or integer")
                )
            }
        }
    }
}
