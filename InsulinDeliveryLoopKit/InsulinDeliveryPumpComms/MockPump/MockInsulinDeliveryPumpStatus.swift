//
//  MockInsulinDeliveryPumpStatus.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2021-09-13.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm
import InsulinDeliveryServiceKit
import BluetoothCommonKit

public struct MockInsulinDeliveryPumpStatus {

    public var pumpState: IDPumpState
    
    public var pumpConfiguration: PumpConfiguration

    public var totalInsulinDelivered: Double {
        return basalDelivered + bolusDelivered + activeBolusDeliveryStatus.insulinDelivered
    }

    public var basalDelivered: Double

    public var bolusDelivered: Double

    public var totalPrimingInsulin: Double

    public var basalProfile: [BasalSegment]?
    
    public var basalRateScheduleStartDate: Date?
    
    public private(set) var tempBasal: UnfinalizedDose? {
        didSet {
            if let oldValue = oldValue {
                pumpState.activeTempBasalDeliveryStatus.insulinDelivered = oldValue.units * oldValue.progress(at: Date())
            }
        }
    }

    // used for tracking the bolus being delivered
    private var bolus: UnfinalizedDose?
    // used for reporting bolus delivery
    public private(set) var activeBolusDeliveryStatus: BolusDeliveryStatus {
        get {
            pumpState.activeBolusDeliveryStatus
        }
        set {
            if newValue != pumpState.activeBolusDeliveryStatus {
                pumpState.activeBolusDeliveryStatus = newValue
            }
        }
    }

    public var activeBolusUpdateHandler: ((BolusDeliveryStatus) -> Void)?

    private var lastDeliveryUpdate: Date

    public var initialReservoirLevel: Int {
        didSet {
            resetDeliveredInsulin()
            updateReservoirLevel()
        }
    }

    public var isAuthenticated: Bool

    public init(pumpState: IDPumpState = IDPumpState(),
                pumpConfiguration: PumpConfiguration = PumpConfiguration.defaultConfiguration,
                basalDelivered: Double = 0,
                bolusDelivered: Double = 0,
                totalPrimingInsulin: Double = 0,
                basalProfile: [BasalSegment]? = nil,
                basalRateScheduleStartDate: Date? = nil,
                tempBasal: UnfinalizedDose? = nil,
                lastDeliveryUpdate: Date = Date(),
                initialReservoirLevel: Int = 200,
                isAuthenticated: Bool = false)
    {
        self.pumpState = pumpState
        self.pumpConfiguration = pumpConfiguration
        self.basalDelivered = basalDelivered
        self.bolusDelivered = bolusDelivered
        self.totalPrimingInsulin = totalPrimingInsulin
        self.basalProfile = basalProfile
        self.basalRateScheduleStartDate = basalRateScheduleStartDate
        self.tempBasal = tempBasal
        self.lastDeliveryUpdate = lastDeliveryUpdate
        self.initialReservoirLevel = initialReservoirLevel
        self.isAuthenticated = isAuthenticated
        self.bolus = pumpState.activeBolusDeliveryStatus.unfinalizedBolus()

        self.pumpState.deviceInformation?.reservoirLevel = Double(initialReservoirLevel)
    }

    static var deviceInformation: DeviceInformation {
        DeviceInformation(identifier: MockInsulinDeliveryPumpStatus.identifier,
                          serialNumber: MockInsulinDeliveryPumpStatus.serialNumber,
                          firmwareRevision: "1.0",
                          hardwareRevision: "1.0",
                          batteryLevel: 100,
                          therapyControlState: .stop,
                          pumpOperationalState: .waiting,
                          reservoirLevel: 200,
                          reportedRemainingLifetime: InsulinDeliveryPumpManager.lifespan)
    }

    static var serialNumber: String { "12345678" }

    static var identifier: UUID { UUID(uuidString: "330A42B1-F4B8-43C6-91FA-1D67A4CB9ECF")! }

    public static var withoutBasalProfile: MockInsulinDeliveryPumpStatus {
        MockInsulinDeliveryPumpStatus(pumpState: IDPumpState(deviceInformation: deviceInformation))
    }

    public static var withBasalProfile: MockInsulinDeliveryPumpStatus {
        var mockInsulinDeliveryPumpStatus = MockInsulinDeliveryPumpStatus.withoutBasalProfile

        let basalProfile = [BasalSegment(index: 1, rate: 1, duration: .hours(24))]
        mockInsulinDeliveryPumpStatus.basalProfile = basalProfile
        mockInsulinDeliveryPumpStatus.basalRateScheduleStartDate = Date()
        return mockInsulinDeliveryPumpStatus
    }

    mutating func updateDeliveryIfNeeded() {
        // only force an update if a bolus is running and it has been 10 seconds since the last update
        guard activeBolusDeliveryStatus.progressState.isOngoing,
              abs(lastDeliveryUpdate.timeIntervalSinceNow) > 10
        else { return }
        
        updateDelivery()
    }
    
    mutating func updateDelivery(until now: Date = Date()) {
        updateTempBasalDelivery(until: now)
        updateBasalDelivery(until: now)
        updateBolusDelivery(until: now)
        updateReservoirLevel()
        lastDeliveryUpdate = now
    }
    
    mutating private func updateBasalDelivery(until now: Date = Date()) {
        guard let basalProfile = basalProfile else { return }
        
        // Prevent crash when time has changed, and now is before lastDeliveryUpdate
        guard lastDeliveryUpdate < now else {
            return
        }

        // creates an array of segments that were delivered with a duration of the time delivered
        let deliveredBasalSegmentsSinceLastUpdate = basalProfile.segmentsDeliveredBetween(start: lastDeliveryUpdate, end: now)
        
        // calculate the basal delivered
        for deliveredBasalSegment in deliveredBasalSegmentsSinceLastUpdate {
            basalDelivered += deliveredBasalSegment.duration.hours * deliveredBasalSegment.rate
        }
        
        lastDeliveryUpdate = now
    }

    mutating private func updateTempBasalDelivery(until now: Date = Date()) {
        if let tempBasal = tempBasal, tempBasal.isFinished(at: now) {
            basalDelivered += tempBasal.units
            basalRateScheduleStartDate = tempBasal.endTime
            lastDeliveryUpdate = tempBasal.endTime ?? now
            self.tempBasal = nil
        }
    }

    mutating func setTempBasal(unitsPerHour: Double, durationInMinutes: UInt16, at now: Date = Date()) {
        updateDelivery(until: now)
        basalRateScheduleStartDate = nil
        tempBasal = UnfinalizedDose(decisionId: nil,
                                    tempBasalRate: unitsPerHour,
                                    startTime: now,
                                    duration: .minutes(Int(durationInMinutes)),
                                    scheduledCertainty: .certain)
    }

    mutating func cancelTempBasal(at now: Date = Date(), completion: @escaping ProcedureResultCompletion) {
        guard var tempBasal = tempBasal else { return }

        tempBasal.cancel(at: now)
        basalDelivered += tempBasal.units
        updateReservoirLevel()
        self.tempBasal = nil
        basalRateScheduleStartDate = now
        completion(.success)
    }

    mutating func endTempBasal(at now: Date = Date(), completion: @escaping (TimeInterval) -> Void) {
        guard var tempBasal = tempBasal else { return }

        tempBasal.cancel(at: now)
        basalDelivered += tempBasal.units
        updateReservoirLevel()
        self.tempBasal = nil
        basalRateScheduleStartDate = now
        let tempBasalDuration = tempBasal.duration ?? now.timeIntervalSince(tempBasal.startTime)
        completion(tempBasalDuration)
    }


    mutating func startEstimatingBolusProgress() {
        activeBolusDeliveryStatus.progressState = .estimatingProgress
        self.bolus?.scheduledCertainty = .uncertain
        activeBolusUpdateHandler?(activeBolusDeliveryStatus)
    }

    mutating func isActiveBolusDeliveryInProgress() -> Bool {
        guard activeBolusDeliveryStatus.progressState == .estimatingProgress else { return activeBolusDeliveryStatus.progressState == .inProgress }

        activeBolusDeliveryStatus.progressState = .inProgress
        updateBolusDelivery()
        return activeBolusDeliveryStatus.progressState == .inProgress
    }

    mutating private func updateBolusDelivery(until now: Date = Date()) {
        if let bolus = bolus,
           activeBolusDeliveryStatus != .noActiveBolus,
           activeBolusDeliveryStatus.progressState != .estimatingProgress
        {
            self.bolus?.scheduledCertainty = .certain
            if bolus.isFinished(at: now) {
                bolusDelivered += bolus.units
                activeBolusDeliveryStatus.insulinDelivered = bolus.units
                activeBolusDeliveryStatus.endTime = now
                activeBolusDeliveryStatus.progressState = .completed
                activeBolusUpdateHandler?(activeBolusDeliveryStatus)
                resetBolusDeliveryStatus()
            } else if let startTime = activeBolusDeliveryStatus.startTime,
                      now.timeIntervalSince(startTime) >= 0
            {
                let insulinDelivered = now.timeIntervalSince(startTime) * InsulinDeliveryPumpManager.estimatedBolusDeliveryRate
                let remainingDuration = (activeBolusDeliveryStatus.insulinProgrammed - insulinDelivered) / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate
                self.bolus?.endTime = now.addingTimeInterval(remainingDuration)

                let progress = insulinDelivered / activeBolusDeliveryStatus.insulinProgrammed
                activeBolusDeliveryStatus.insulinDelivered = insulinDelivered.roundedToHundredths
                activeBolusDeliveryStatus.progressState = progress > 0 ? .inProgress : .noActiveBolus
                activeBolusUpdateHandler?(activeBolusDeliveryStatus)
            } else {
                // bolus has not started yet
                activeBolusDeliveryStatus.insulinDelivered = 0
                activeBolusDeliveryStatus.progressState = .noActiveBolus
                activeBolusUpdateHandler?(activeBolusDeliveryStatus)
            }
        }
    }

    mutating func setBolus(_ amount: Double, at now: Date = Date()) {
        self.bolus = UnfinalizedDose(decisionId: nil,
                                     bolusAmount: amount,
                                     startTime: now,
                                     scheduledCertainty: .certain)
        activeBolusDeliveryStatus = BolusDeliveryStatus(id: (activeBolusDeliveryStatus.id ?? 0) + 1,
                                                        progressState: .inProgress,
                                                        type: .fast,
                                                        insulinProgrammed: amount,
                                                        insulinDelivered: 0,
                                                        startTime: now)
    }

    mutating private func resetBolusDeliveryStatus() {
        activeBolusUpdateHandler = nil
        activeBolusDeliveryStatus = .noActiveBolus
        self.bolus = nil
    }

    mutating func cancelBolus(at now: Date = Date(), completion: @escaping (DeviceCommResult<BolusDeliveryStatus>) -> Void) {
        guard var bolus = bolus else {
            return
        }

        if bolus.isFinished(at: now) {
            updateBolusDelivery(until: now)
            completion(.success(activeBolusDeliveryStatus))
            activeBolusDeliveryStatus = .noActiveBolus
            return
        }

        bolus.cancel(at: now)

        bolusDelivered += bolus.units
        activeBolusDeliveryStatus.insulinDelivered = bolus.units
        activeBolusDeliveryStatus.progressState = .canceled
        activeBolusDeliveryStatus.endTime = now

        activeBolusUpdateHandler?(activeBolusDeliveryStatus)
        completion(.success(activeBolusDeliveryStatus))

        resetBolusDeliveryStatus()
    }

    mutating private func updateReservoirLevel() {
        let reservoirLevel = max(Double(initialReservoirLevel) - totalInsulinDelivered - totalPrimingInsulin, 0)
        pumpState.deviceInformation?.reservoirLevel = reservoirLevel
    }

    mutating public func pumpPrimed(_ amount: Double = 0.5) {
        totalPrimingInsulin += amount
        updateReservoirLevel()
    }

    mutating private func resetDeliveredInsulin() {
        basalDelivered = 0
        bolusDelivered = 0
        totalPrimingInsulin = 0
    }

    mutating public func startInsulinDelivery(at now: Date = Date()) {
        basalRateScheduleStartDate = now
    }

    mutating public func suspendInsulinDelivery(at now: Date = Date()) {
        cancelBolus(at: now, completion: { _ in })
        cancelTempBasal(at: now, completion: { _ in })
        updateDelivery(until: now)
        basalRateScheduleStartDate = nil
    }

    mutating public func updateReservoirRemaining(_ reservoirRemaining: Double) {
        basalDelivered = Double(initialReservoirLevel) - reservoirRemaining - bolusDelivered - activeBolusDeliveryStatus.insulinDelivered - totalPrimingInsulin
        updateReservoirLevel()
    }
}

extension MockInsulinDeliveryPumpStatus: RawRepresentable {
    public typealias RawValue = [String: Any]

    private enum MockInsulinDeliveryPumpStatusKey: String {
        case basalDelivered
        case basalProfile
        case basalRateScheduleStartDate
        case bolusDelivered
        case initialReservoirLevel
        case isAuthenticated
        case lastDeliveryUpdate
        case pumpConfiguration
        case pumpState
        case tempBasal
        case totalPrimingInsulin
    }

    public init?(rawValue: RawValue) {
        guard
            let basalDelivered = rawValue[MockInsulinDeliveryPumpStatusKey.basalDelivered.rawValue] as? Double,
            let bolusDelivered = rawValue[MockInsulinDeliveryPumpStatusKey.bolusDelivered.rawValue] as? Double,
            let initialReservoirLevel = rawValue[MockInsulinDeliveryPumpStatusKey.initialReservoirLevel.rawValue] as? Int,
            let isAuthenticated = rawValue[MockInsulinDeliveryPumpStatusKey.isAuthenticated.rawValue] as? Bool,
            let lastDeliveryUpdate = rawValue[MockInsulinDeliveryPumpStatusKey.lastDeliveryUpdate.rawValue] as? Date,
            let rawConfiguration = rawValue[MockInsulinDeliveryPumpStatusKey.pumpConfiguration.rawValue] as? Data,
            let pumpConfiguration = try? PropertyListDecoder().decode(PumpConfiguration.self, from: rawConfiguration),
            let rawPumpState = rawValue[MockInsulinDeliveryPumpStatusKey.pumpState.rawValue] as? IDPumpState.RawValue,
            let pumpState = IDPumpState(rawValue: rawPumpState),
            let totalPrimingInsulin = rawValue[MockInsulinDeliveryPumpStatusKey.totalPrimingInsulin.rawValue] as? Double
        else {
            return nil
        }

        self.basalDelivered = basalDelivered

        if let rawBasalProfile = rawValue[MockInsulinDeliveryPumpStatusKey.basalProfile.rawValue] as? Data {
            self.basalProfile = try? PropertyListDecoder().decode([BasalSegment].self, from: rawBasalProfile)
        }

        self.basalRateScheduleStartDate = rawValue[MockInsulinDeliveryPumpStatusKey.basalRateScheduleStartDate.rawValue] as? Date

        if let rawTempBasal = rawValue[MockInsulinDeliveryPumpStatusKey.tempBasal.rawValue] as? UnfinalizedDose.RawValue {
            self.tempBasal = UnfinalizedDose(rawValue: rawTempBasal)
        }

        self.bolus = pumpState.activeBolusDeliveryStatus.unfinalizedBolus()
        self.bolusDelivered = bolusDelivered
        self.initialReservoirLevel = initialReservoirLevel
        self.isAuthenticated = isAuthenticated
        self.lastDeliveryUpdate = lastDeliveryUpdate
        self.pumpConfiguration = pumpConfiguration
        self.pumpState = pumpState
        self.totalPrimingInsulin = totalPrimingInsulin
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [
            MockInsulinDeliveryPumpStatusKey.basalDelivered.rawValue: basalDelivered,
            MockInsulinDeliveryPumpStatusKey.bolusDelivered.rawValue: bolusDelivered,
            MockInsulinDeliveryPumpStatusKey.initialReservoirLevel.rawValue: initialReservoirLevel,
            MockInsulinDeliveryPumpStatusKey.isAuthenticated.rawValue: isAuthenticated,
            MockInsulinDeliveryPumpStatusKey.lastDeliveryUpdate.rawValue: lastDeliveryUpdate,
            MockInsulinDeliveryPumpStatusKey.pumpState.rawValue: pumpState.rawValue,
            MockInsulinDeliveryPumpStatusKey.totalPrimingInsulin.rawValue: totalPrimingInsulin,
        ]

        let rawBasalProfile = try? PropertyListEncoder().encode(basalProfile)
        rawValue[MockInsulinDeliveryPumpStatusKey.basalProfile.rawValue] = rawBasalProfile
        
        let rawConfiguration = try? PropertyListEncoder().encode(pumpConfiguration)
        rawValue[MockInsulinDeliveryPumpStatusKey.pumpConfiguration.rawValue] = rawConfiguration

        rawValue[MockInsulinDeliveryPumpStatusKey.basalRateScheduleStartDate.rawValue] = basalRateScheduleStartDate
        rawValue[MockInsulinDeliveryPumpStatusKey.tempBasal.rawValue] = tempBasal?.rawValue

        return rawValue
    }
}

fileprivate extension AbsoluteScheduleValue {
    var endTimeFromStartOfDay: TimeInterval {
        endDate.timeIntervalSince(Calendar.current.startOfDay(for: startDate))
    }
}

fileprivate extension TimeInterval {
    var fromStartOfDay: TimeInterval {
        self.truncatingRemainder(dividingBy: TimeInterval.days(1))
    }
}

extension MockInsulinDeliveryPumpStatus: Equatable {
    public static func == (lhs: MockInsulinDeliveryPumpStatus, rhs: MockInsulinDeliveryPumpStatus) -> Bool {
        return lhs.pumpState == rhs.pumpState &&
            lhs.basalDelivered == rhs.basalDelivered &&
            lhs.bolusDelivered == rhs.bolusDelivered &&
            lhs.totalPrimingInsulin == rhs.totalPrimingInsulin &&
            lhs.basalProfile == rhs.basalProfile &&
            lhs.basalRateScheduleStartDate == rhs.basalRateScheduleStartDate &&
            lhs.tempBasal == rhs.tempBasal &&
            lhs.bolus == rhs.bolus &&
            lhs.activeBolusDeliveryStatus == rhs.activeBolusDeliveryStatus &&
            lhs.lastDeliveryUpdate == rhs.lastDeliveryUpdate &&
            lhs.initialReservoirLevel == rhs.initialReservoirLevel
    }
}

extension UnfinalizedDose {
    func bolusDeliveryStatus(at now: Date = Date()) -> BolusDeliveryStatus {
        let progressState: BolusProgressState
        let progress = progress(at: now)
        let programmedUnits = programmedUnits ?? units
        if progress >= 1 {
            progressState = .completed
        } else if progress > 0 {
            progressState = .inProgress
        } else {
            progressState = .noActiveBolus
        }
        return BolusDeliveryStatus(id: 1,
                                   progressState: progressState,
                                   type: .fast,
                                   insulinProgrammed: programmedUnits,
                                   insulinDelivered: progress * programmedUnits)
    }
}
