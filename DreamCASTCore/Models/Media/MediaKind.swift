// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  MediaKind.swift
//  DreamCAST
//
//  Type discriminator for any media item across the agnostic layer.
//

import Foundation

nonisolated enum MediaKind: String, Sendable, Hashable, Codable {
    case movie
    case show
    case season
    case episode
    case collection
    case playlist
    case person
    case unknown
}
