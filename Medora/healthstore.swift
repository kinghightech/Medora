//
//  healthstore.swift
//  Medora
//
//  Created by Aahish Abbani on 6/11/26.
//

import Combine
import Foundation
import HealthKit

struct HealthDataSummary {
    var caloriesBurned = "No data available"
    var steps = "No data available"
    var sleep = "No data available"
}

final class HealthStore: ObservableObject {
    @Published private(set) var summary = HealthDataSummary()
    @Published private(set) var isLoading = false

    private let calendar = Calendar.current

    private let noDataText = "No data available"

    func requestAccessAndLoadData() async -> Bool {
        guard let context = Self.makeHealthContext() else {
            return false
        }

        isLoading = true
        defer { isLoading = false }

        // Best effort: even if the authorization request errors (OS hiccups,
        // repeat prompts), the user still gets into the app. Queries against
        // unauthorized or empty types simply produce "No data available",
        // and the refresh button can retry later.
        try? await requestAuthorization(store: context.store, readTypes: context.readTypes)
        await loadHealthData(using: context)
        return true
    }

    func refreshHealthData() async {
        guard let context = Self.makeHealthContext() else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        await loadHealthData(using: context)
    }

    private func requestAuthorization(store: HKHealthStore, readTypes: Set<HKObjectType>) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthStoreError.authorizationFailed)
                }
            }
        }
    }

    private func loadHealthData(using context: HealthContext) async {
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        // "Last night" must work at any hour, including just after midnight,
        // so look back a full day rather than using rigid calendar-day edges.
        let sleepWindowStart = calendar.date(byAdding: .hour, value: -24, to: now) ?? todayStart

        // Each metric loads independently so one failure can't wipe out the others.
        let stepsValue = await todayTotal(
            store: context.store,
            type: context.stepType,
            unit: .count(),
            todayStart: todayStart,
            now: now
        )
        let calorieValue = await todayTotal(
            store: context.store,
            type: context.calorieType,
            unit: .kilocalorie(),
            todayStart: todayStart,
            now: now
        )
        let sleepDuration = (try? await sleepDuration(
            store: context.store,
            type: context.sleepType,
            start: sleepWindowStart,
            end: now
        )) ?? nil

        summary = HealthDataSummary(
            caloriesBurned: formatCalories(calorieValue),
            steps: formatSteps(stepsValue),
            sleep: formatSleep(sleepDuration)
        )
    }

    /// Today's total for a metric, distinguishing "zero so far today" from
    /// "nothing readable at all": HealthKit returns the same empty result for
    /// both, so when today is empty we probe the past week — any history means
    /// today is a genuine 0 (shown as "0 steps"), while a silent week usually
    /// means access is off or the metric was never recorded ("No data available").
    private func todayTotal(
        store: HKHealthStore,
        type: HKQuantityType,
        unit: HKUnit,
        todayStart: Date,
        now: Date
    ) async -> Double? {
        let todayValue = (try? await cumulativeQuantity(
            store: store, type: type, unit: unit, start: todayStart, end: now
        )) ?? nil
        if let todayValue {
            return todayValue
        }

        let weekStart = calendar.date(byAdding: .day, value: -7, to: now) ?? todayStart
        let weekValue = (try? await cumulativeQuantity(
            store: store, type: type, unit: unit, start: weekStart, end: now
        )) ?? nil
        return weekValue != nil ? 0 : nil
    }

    private func cumulativeQuantity(
        store: HKHealthStore,
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    // HealthKit reports an error when no samples exist in the
                    // range; that's an empty value, not a failure.
                    if (error as? HKError)?.code == .errorNoData {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                let value = result?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }

            store.execute(query)
        }
    }

    private func sleepDuration(
        store: HKHealthStore,
        type: HKCategoryType,
        start: Date,
        end: Date
    ) async throws -> TimeInterval? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    if (error as? HKError)?.code == .errorNoData {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let sleepSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }

                let sleepIntervals = sleepSamples.compactMap { sample -> SleepInterval? in
                    guard Self.asleepValues.contains(sample.value) else {
                        return nil
                    }

                    let clippedStart = max(sample.startDate, start)
                    let clippedEnd = min(sample.endDate, end)

                    guard clippedEnd > clippedStart else {
                        return nil
                    }

                    return SleepInterval(start: clippedStart, end: clippedEnd)
                }

                guard !sleepIntervals.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: Self.mergedDuration(for: sleepIntervals))
            }

            store.execute(query)
        }
    }

    private static func makeHealthContext() -> HealthContext? {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        return HealthContext(
            store: HKHealthStore(),
            stepType: stepType,
            calorieType: calorieType,
            sleepType: sleepType
        )
    }

    private func formatSteps(_ value: Double?) -> String {
        guard let value else {
            return noDataText
        }

        return "\(Int(value.rounded())) steps"
    }

    private func formatCalories(_ value: Double?) -> String {
        guard let value else {
            return noDataText
        }

        return "\(Int(value.rounded())) kcal"
    }

    private func formatSleep(_ duration: TimeInterval?) -> String {
        guard let duration, duration > 0 else {
            return noDataText
        }

        let totalMinutes = Int((duration / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return "\(hours) hr \(minutes) min"
        }

        if hours > 0 {
            return "\(hours) hr"
        }

        return "\(minutes) min"
    }

    nonisolated private static let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue
    ]

    nonisolated private static func mergedDuration(for intervals: [SleepInterval]) -> TimeInterval {
        let sortedIntervals = intervals.sorted { $0.start < $1.start }
        var mergedIntervals: [SleepInterval] = []

        for interval in sortedIntervals {
            guard let last = mergedIntervals.last else {
                mergedIntervals.append(interval)
                continue
            }

            if interval.start <= last.end {
                mergedIntervals[mergedIntervals.count - 1] = SleepInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                mergedIntervals.append(interval)
            }
        }

        return mergedIntervals.reduce(0) { total, interval in
            total + interval.end.timeIntervalSince(interval.start)
        }
    }
}

private struct SleepInterval {
    let start: Date
    let end: Date
}

private struct HealthContext {
    let store: HKHealthStore
    let stepType: HKQuantityType
    let calorieType: HKQuantityType
    let sleepType: HKCategoryType

    var readTypes: Set<HKObjectType> {
        [stepType, calorieType, sleepType]
    }
}

private enum HealthStoreError: Error {
    case authorizationFailed
}
