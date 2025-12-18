/**
 * ProcessDescription.swift
 * PortKiller
 *
 * Models for process description functionality including categories,
 * confidence levels, and description text.
 */

import Foundation

/// Categories for classifying different types of processes
enum ProcessCategory: String, CaseIterable, Identifiable, Sendable {
    case development = "development"
    case webServer = "webServer"
    case database = "database"
    case system = "system"
    case other = "other"
    
    var id: String { rawValue }
}

/// Confidence levels for process descriptions
enum DescriptionConfidence: String, CaseIterable, Sendable {
    case exact = "exact"
    case pattern = "pattern"
    case fallback = "fallback"
}

/// Complete description of a process including text, category, and confidence
struct ProcessDescription: Hashable, Sendable {
    let text: String
    let category: ProcessCategory
    let confidence: DescriptionConfidence
}