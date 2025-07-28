//
//  UnfinalizedDose.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2020-05-29.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit

public struct UnfinalizedDose: RawRepresentable, Equatable, CustomStringConvertible, Hashable {
    public typealias RawValue = [String: Any]

    private enum UnfinalizedDoseKey: String {
        case automatic
        case rawDoseType
        case duration
        case programmedUnits
        case programmedRate
        case rawScheduledCertainty
        case startTime
        case units
    }
    
    enum DoseType: Int, Codable {
        case bolus = 0
        case tempBasal
        case suspend
        case resume
    }

    enum ScheduledCertainty: Int, Codable {
        case certain = 0
        case uncertain

        public var localizedDescription: String {
            switch self {
            case .certain:
                return LocalizedString("Certain", comment: "String describing a dose that was certainly scheduled")
            case .uncertain:
                return LocalizedString("Uncertain", comment: "String describing a dose that was possibly scheduled")
            }
        }
    }

    static fileprivate let insulinFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter
    }()

    static fileprivate let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    fileprivate var uniqueKey: Data {
        return "\(doseType) \(programmedUnits ?? units) \(ISO8601DateFormatter().string(from: startTime))".data(using: .utf8)!
    }

    let doseType: DoseType

    public var units: Double
    
    var programmedUnits: Double? // Tracks the programmed units, as boluses may be canceled before finishing, at which point units would reflect actual delivered volume.
    
    var programmedRate: Double?  // Tracks the original temp rate, as during finalization the units are discretized to pump pulses, changing the actual rate
    
    let startTime: Date
    
    var duration: TimeInterval?
    
    var scheduledCertainty: ScheduledCertainty

    var endTime: Date? {
        get {
            return duration != nil ? startTime.addingTimeInterval(duration!) : nil
        }
        set {
            duration = newValue?.timeIntervalSince(startTime)
        }
    }

    var wasCanceled: Bool {
        programmedUnits != nil
    }
    
    // Units per hour
    public var rate: Double {
        guard let duration = duration,
              duration != 0
        else { return 0 }
        return units / duration.hours
    }

    public func progress(at date: Date) -> Double {
        guard let duration = duration else {
            return 0
        }
        let elapsed = -startTime.timeIntervalSince(date)
        return min(max(elapsed, 0) / duration, 1)
    }

    public func isFinished(at date: Date) -> Bool {
        return progress(at: date) >= 1
    }
    
    public func finalizedUnits(at date: Date) -> Double? {
        guard isFinished(at: date) else {
            return nil
        }
        return units
    }

    var automatic: Bool?

    init(bolusAmount: Double, startTime: Date, scheduledCertainty: ScheduledCertainty, automatic: Bool? = false) {
        self.doseType = .bolus
        self.units = bolusAmount
        self.startTime = startTime
        self.duration = TimeInterval(bolusAmount / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate)
        self.scheduledCertainty = scheduledCertainty
        self.programmedUnits = nil
        self.automatic = automatic
    }

    init(tempBasalRate: Double, startTime: Date, duration: TimeInterval, scheduledCertainty: ScheduledCertainty, automatic: Bool? = true) {
        self.doseType = .tempBasal
        self.units = tempBasalRate * duration.hours
        self.startTime = startTime
        self.duration = duration
        self.scheduledCertainty = scheduledCertainty
        self.programmedUnits = nil
        self.automatic = automatic
    }

    init(suspendStartTime: Date, scheduledCertainty: ScheduledCertainty, automatic: Bool? = false) {
        self.doseType = .suspend
        self.units = 0
        self.startTime = suspendStartTime
        self.scheduledCertainty = scheduledCertainty
        self.automatic = automatic
    }

    init(resumeStartTime: Date, scheduledCertainty: ScheduledCertainty, automatic: Bool? = false) {
        self.doseType = .resume
        self.units = 0
        self.startTime = resumeStartTime
        self.scheduledCertainty = scheduledCertainty
        self.automatic = automatic
    }

    public mutating func cancel(at date: Date, insulinDelivered: Double? = nil) {

        let newDuration = max(0, date.timeIntervalSince(startTime))

        guard !wasCanceled else {
            // If insulin delivered is provided, update both the duration and delivered amount
            if let insulinDelivered = insulinDelivered {
                units = insulinDelivered
                duration = newDuration
            }
            return
        }

        programmedUnits = units

        let oldRate = rate

        if doseType == .tempBasal {
            programmedRate = oldRate
        }

        duration = newDuration

        if let insulinDelivered = insulinDelivered {
            units = insulinDelivered
        } else if let duration = duration {
            units = min(units, oldRate * duration.hours)
        }
    }

    public var description: String {
        let unitsStr = UnfinalizedDose.insulinFormatter.string(from: units) ?? ""
        let startTimeStr = UnfinalizedDose.shortDateFormatter.string(from: startTime)
        let durationStr = duration?.format(using: [.minute, .second]) ?? ""
        switch doseType {
        case .bolus:
            if let programmedUnits = programmedUnits {
                let programmedUnitsStr = UnfinalizedDose.insulinFormatter.string(from: programmedUnits) ?? "?"
                return String(format: LocalizedString("InterruptedBolus: %1$@ U (%2$@ U scheduled) %3$@ %4$@ %5$@", comment: "The format string describing a bolus that was interrupted. (1: The amount delivered)(2: The amount scheduled)(3: Start time of the dose)(4: duration)(5: scheduled certainty)"), unitsStr, programmedUnitsStr, startTimeStr, durationStr, scheduledCertainty.localizedDescription)
            } else {
                return String(format: LocalizedString("Bolus: %1$@U %2$@ %3$@ %4$@", comment: "The format string describing a bolus. (1: The amount delivered)(2: Start time of the dose)(3: duration)(4: scheduled certainty)"), unitsStr, startTimeStr, durationStr, scheduledCertainty.localizedDescription)
            }
        case .tempBasal:
            let rateStr = NumberFormatter.localizedString(from: NSNumber(value: programmedRate ?? rate), number: .decimal)
            return String(format: LocalizedString("TempBasal: %1$@ U/hour %2$@ %3$@ %4$@", comment: "The format string describing a temp basal. (1: The rate)(2: Start time)(3: duration)(4: scheduled certainty"), rateStr, startTimeStr, durationStr, scheduledCertainty.localizedDescription)
        case .suspend:
            return String(format: LocalizedString("Suspend: %1$@ %2$@", comment: "The format string describing a suspend. (1: Time)(2: Scheduled certainty"), startTimeStr, scheduledCertainty.localizedDescription)
        case .resume:
            return String(format: LocalizedString("Resume: %1$@ %2$@", comment: "The format string describing a resume. (1: Time)(2: Scheduled certainty"), startTimeStr, scheduledCertainty.localizedDescription)
        }
    }

    public var eventTitle: String {
        switch doseType {
        case .bolus:
            return NSLocalizedString("Bolus", comment: "Pump Event title for UnfinalizedDose with doseType of .bolus")
        case .resume:
            return NSLocalizedString("Resume", comment: "Pump Event title for UnfinalizedDose with doseType of .resume")
        case .suspend:
            return NSLocalizedString("Suspend", comment: "Pump Event title for UnfinalizedDose with doseType of .suspend")
        case .tempBasal:
            return NSLocalizedString("Temp Basal", comment: "Pump Event title for UnfinalizedDose with doseType of .tempBasal")
        }
    }

    // RawRepresentable
    public init?(rawValue: RawValue) {
        guard
            let rawDoseType = rawValue[UnfinalizedDoseKey.rawDoseType.rawValue] as? Int,
            let doseType = DoseType(rawValue: rawDoseType),
            let units = rawValue[UnfinalizedDoseKey.units.rawValue] as? Double,
            let startTime = rawValue[UnfinalizedDoseKey.startTime.rawValue] as? Date,
            let rawScheduledCertainty = rawValue[UnfinalizedDoseKey.rawScheduledCertainty.rawValue] as? Int,
            let scheduledCertainty = ScheduledCertainty(rawValue: rawScheduledCertainty)
            else {
                return nil
        }

        self.doseType = doseType
        self.units = units
        self.startTime = startTime
        self.scheduledCertainty = scheduledCertainty

        if let programmedUnits = rawValue[UnfinalizedDoseKey.programmedUnits.rawValue] as? Double {
            self.programmedUnits = programmedUnits
        }

        if let programmedRate = rawValue[UnfinalizedDoseKey.programmedRate.rawValue] as? Double {
            self.programmedRate = programmedRate
        }

        if let duration = rawValue[UnfinalizedDoseKey.duration.rawValue] as? Double {
            self.duration = duration
        }

        self.automatic = rawValue[UnfinalizedDoseKey.automatic.rawValue] as? Bool
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [
            UnfinalizedDoseKey.rawDoseType.rawValue: doseType.rawValue,
            UnfinalizedDoseKey.units.rawValue: units,
            UnfinalizedDoseKey.startTime.rawValue: startTime,
            UnfinalizedDoseKey.rawScheduledCertainty.rawValue: scheduledCertainty.rawValue
        ]

        if let programmedUnits = programmedUnits {
            rawValue[UnfinalizedDoseKey.programmedUnits.rawValue] = programmedUnits
        }

        if let programmedRate = programmedRate {
            rawValue[UnfinalizedDoseKey.programmedRate.rawValue] = programmedRate
        }

        if let duration = duration {
            rawValue[UnfinalizedDoseKey.duration.rawValue] = duration
        }

        if let automatic = automatic {
            rawValue[UnfinalizedDoseKey.automatic.rawValue] = automatic
        }

        return rawValue
    }
}

private extension TimeInterval {
    func format(using units: NSCalendar.Unit) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = units
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropLeading
        formatter.maximumUnitCount = 2

        return formatter.string(from: self)
    }
}

extension NewPumpEvent {
    init(_ dose: UnfinalizedDose, at date: Date, isFinalized: Bool) {
        let entry = DoseEntry(dose, at: date, isFinalized: isFinalized)
        self.init(date: dose.startTime, dose: entry, raw: dose.uniqueKey, title: dose.eventTitle)
    }
}

extension DoseEntry {
    init (_ dose: UnfinalizedDose, at date: Date, isFinalized: Bool = false) {
        switch dose.doseType {
        case .bolus:
            self = DoseEntry(type: .bolus, startDate: dose.startTime, endDate: dose.endTime, value: dose.programmedUnits ?? dose.units, unit: .units, deliveredUnits: dose.finalizedUnits(at: date), automatic: dose.automatic, isMutable: !isFinalized, wasProgrammedByPumpUI: false)
        case .tempBasal:
            self = DoseEntry(type: .tempBasal, startDate: dose.startTime, endDate: dose.endTime, value: dose.programmedRate ?? dose.rate, unit: .unitsPerHour, deliveredUnits: dose.finalizedUnits(at: date), automatic: dose.automatic, isMutable: !isFinalized)
        case .suspend:
            self = DoseEntry(suspendDate: dose.startTime, automatic: dose.automatic)
        case .resume:
            self = DoseEntry(resumeDate: dose.startTime, automatic: dose.automatic)
        }
    }
}

extension UnfinalizedDose {
    func doseEntry(at date: Date, isFinalized: Bool) -> DoseEntry {
        return DoseEntry(self, at: date, isFinalized: isFinalized)
    }
}

extension UnfinalizedDose: Codable { }
