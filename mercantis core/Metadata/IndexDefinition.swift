//
//  IndexDefinition.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Defines an index to be extracted from the JSON payload into an indexed column
/// for query performance. (ADR-002)
public struct IndexDefinition: Codable, Sendable {
    public let fieldKey: String
    public let unique: Bool
}
