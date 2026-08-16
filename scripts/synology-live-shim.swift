import Foundation

// Stands in for the app's MetricReading, which lives in MetricsSampler.swift
// alongside IOKit and Mach code that will not compile outside the app target.
// Same shape and same initialiser, so the client and parsers compile unchanged.
nonisolated struct MetricReading: Equatable, Sendable {
    let value: Double?
    let auxiliaryValue: Double?
    let capacity: Double?

    init(value: Double?, auxiliaryValue: Double? = nil, capacity: Double? = nil) {
        self.value = value
        self.auxiliaryValue = auxiliaryValue
        self.capacity = capacity
    }
}
