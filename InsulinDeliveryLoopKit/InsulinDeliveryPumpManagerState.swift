//
//  InsulinDeliveryPumpManagerState.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2020-03-13.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit
import InsulinDeliveryServiceKit

// Primarily used for testing
private struct DateGeneratorWrapper {
    let dateGenerator: () -> Date
}

extension DateGeneratorWrapper: Equatable {
    static func == (lhs: DateGeneratorWrapper, rhs: DateGeneratorWrapper) -> Bool {
        return true
    }
}

public struct InsulinDeliveryPumpManagerState: RawRepresentable, Equatable {

    public typealias RawValue = PumpManager.RawStateValue
    
    private enum InsulinDeliveryPumpManagerStateKey: String {
        case annunciationsPendingConfirmation
        case basalRateSchedule
        case expirationReminderTimeBeforeExpiration
        case finalizedDoses
        case lastPumpTime
        case lastStatusDate
        case lowReservoirWarningThresholdInUnits
        case notificationSettingsState
        case onboardingCompleted
        case onboardingVideosWatched
        case pendingInsulinDeliveryCommand
        case previousPumpRemainingLifetime
        case pumpActivatedAt
        case pumpConfiguration
        case pumpState
        case replacementWorkflowState
        case suspendState
        case totalInsulinDelivery
        case unfinalizedBoluses
        case unfinalizedSuspendDetected
        case unfinalizedTempBasal
        case version
    }

    public var alarmCode: Int?

    public var basalRateSchedule: BasalRateSchedule

    public var maxBolusUnits: Double {
        pumpConfiguration.bolusMaximum
    }
    
    public var lastStatusDate: Date?
    
    public var pumpActivatedAt: Date?

    public var suspendState: SuspendState?

    public var timeZone: TimeZone {
        get {
            basalRateSchedule.timeZone
        }
        set {
            basalRateSchedule.timeZone = newValue
        }
    }

    public var lastPumpTime: Date?

    public var totalInsulinDelivery: Double?
    
    public static let version = 1

    public var pumpState: IDPumpState {
        didSet {
            // only use changes to the therapy state
            guard pumpState.deviceInformation?.therapyControlState != oldValue.deviceInformation?.therapyControlState else { return }
            
            switch pumpState.deviceInformation?.therapyControlState {
            case .stop:
                if pumpState.deviceInformation?.pumpOperationalState.isAnActivePumpState != true {
                    // the pump is not ready to deliver insulin
                    suspendState = nil
                } else if !isSuspended {
                    suspendState = .suspended(dateGenerator())
                }
            case .run:
                if suspendState == nil || isSuspended { suspendState = .resumed(dateGenerator()) }
            default:
                break
            }
        }
    }
    
    public var pumpConfiguration: PumpConfiguration

    var finalizedDoses: [UnfinalizedDose]
    
    public var unfinalizedBoluses: [BolusID: UnfinalizedDose]
    
    public var unfinalizedTempBasal: UnfinalizedDose?

    public var unfinalizedSuspendDetected: Bool?

    var pendingInsulinDeliveryCommand: PendingInsulinDeliveryCommand?

    var annunciationsPendingConfirmation: Set<GeneralAnnunciation>

    var previousPumpRemainingLifetime: [String: TimeInterval] = [:]

    public var lowReservoirWarningThresholdInUnits: Int = PumpConfiguration.defaultConfiguration.reservoirLevelWarningThresholdInUnits

    public var expirationReminderTimeBeforeExpiration: TimeInterval = PumpConfiguration.defaultConfiguration.expiryWarningDuration

    public var isSuspended: Bool {
        guard case .resumed = suspendState else { return true }
        return false
    }

    public var suspendedAt: Date? {
        guard case .suspended(let suspendedAt) = suspendState else { return nil }
        return suspendedAt
    }
    
    // Temporal state not persisted
    
    internal enum ActiveTransition: Equatable {
        case startingBolus
        case cancelingBolus
        case startingTempBasal
        case cancelingTempBasal
        case suspendingPump
        case resumingPump
    }
    
    internal var activeTransition: ActiveTransition?
        
    private let dateGeneratorWrapper: DateGeneratorWrapper
    private func dateGenerator() -> Date {
        return dateGeneratorWrapper.dateGenerator()
    }

    // Indicates that the user has completed onboarding
    public var onboardingCompleted: Bool = false
    
    // Onboarding videos, by name, that the user has already watched
    public var onboardingVideosWatched: [String] = []
    
    public struct ReplacementWorkflowState: RawRepresentable, Equatable {
        public typealias RawValue = PumpManager.RawStateValue
        
        public func lastPumpReplacementDateOrDefault(_ now: @escaping () -> Date = Date.init) -> Date {
            return lastPumpReplacementDate ?? now()
        }
        
        private enum ReplacementWorkflowStateKey: String {
            case milestoneProgress
            case pumpSetupState
            case wasWorkflowCanceled
            case lastPumpReplacementDate
            case doesPumpNeedsReplacement
        }

        public var milestoneProgress: [Int] = []
        public var pumpSetupState: PumpSetupState?
        public var wasWorkflowCanceled: Bool
        public var lastPumpReplacementDate: Date?
        public var doesPumpNeedsReplacement: Bool

        public var isWorkflowIncomplete: Bool {
            guard !milestoneProgress.isEmpty else {
                return wasWorkflowCanceled
            }

            return true
        }
        
        public func updatedAfterReplacingPump(_ now: @escaping () -> Date = Date.init) -> ReplacementWorkflowState {
            let lastPumpReplacementDate = lastPumpReplacementDateOrDefault(now)
            let pumpSetupState: PumpSetupState? = nil
            return updatedWith(milestoneProgress: [],
                               pumpSetupState: pumpSetupState,
                               lastPumpReplacementDate: lastPumpReplacementDate,
                               doesPumpNeedsReplacement: false)
        }
        
        public var canceled: ReplacementWorkflowState {
            let pumpSetupState: PumpSetupState? = nil
            return updatedWith(milestoneProgress: [],
                               pumpSetupState: pumpSetupState,
                               wasWorkflowCanceled: true)
        }
        
        internal func updatedWith(milestoneProgress: [Int]? = nil,
                                  pumpSetupState: PumpSetupState?? = nil,
                                  wasWorkflowCanceled: Bool? = nil,
                                  lastPumpReplacementDate: Date? = nil,
                                  doesPumpNeedsReplacement: Bool? = nil) -> ReplacementWorkflowState {
            return ReplacementWorkflowState(milestoneProgress: milestoneProgress ?? self.milestoneProgress,
                                            pumpSetupState: pumpSetupState ?? self.pumpSetupState,
                                            wasWorkflowCanceled: wasWorkflowCanceled ?? self.wasWorkflowCanceled,
                                            lastPumpReplacementDate: lastPumpReplacementDate ?? self.lastPumpReplacementDate,
                                            doesPumpNeedsReplacement: doesPumpNeedsReplacement ?? self.doesPumpNeedsReplacement)
        }
        
        init() {
            self.init(milestoneProgress: [], pumpSetupState: nil, wasWorkflowCanceled: false, lastPumpReplacementDate: nil, doesPumpNeedsReplacement: false)
        }
        
        init(milestoneProgress: [Int],
             pumpSetupState: PumpSetupState?,
             wasWorkflowCanceled: Bool,
             lastPumpReplacementDate: Date?,
             doesPumpNeedsReplacement: Bool = false) {
            self.milestoneProgress = milestoneProgress
            self.pumpSetupState = pumpSetupState
            self.wasWorkflowCanceled = wasWorkflowCanceled
            self.lastPumpReplacementDate = lastPumpReplacementDate
            self.doesPumpNeedsReplacement = doesPumpNeedsReplacement
        }

        public var rawValue: RawValue {
            var rawValue: RawValue = [:]
            rawValue[ReplacementWorkflowStateKey.milestoneProgress.rawValue] = milestoneProgress
            rawValue[ReplacementWorkflowStateKey.pumpSetupState.rawValue] = pumpSetupState?.rawValue
            rawValue[ReplacementWorkflowStateKey.wasWorkflowCanceled.rawValue] = wasWorkflowCanceled
            rawValue[ReplacementWorkflowStateKey.lastPumpReplacementDate.rawValue] = lastPumpReplacementDate
            rawValue[ReplacementWorkflowStateKey.doesPumpNeedsReplacement.rawValue] = doesPumpNeedsReplacement
            return rawValue
        }

        public init?(rawValue: RawValue) {
            milestoneProgress = rawValue[ReplacementWorkflowStateKey.milestoneProgress.rawValue] as? [Int] ?? []
            wasWorkflowCanceled = rawValue[ReplacementWorkflowStateKey.wasWorkflowCanceled.rawValue] as? Bool ?? false
            lastPumpReplacementDate = rawValue[ReplacementWorkflowStateKey.lastPumpReplacementDate.rawValue] as? Date
            doesPumpNeedsReplacement = rawValue[ReplacementWorkflowStateKey.doesPumpNeedsReplacement.rawValue] as? Bool ?? false

            if let rawPumpSetupState = rawValue[ReplacementWorkflowStateKey.pumpSetupState.rawValue] as? PumpSetupState.RawValue {
                pumpSetupState = PumpSetupState(rawValue: rawPumpSetupState)
            }
        }
    }

    public var replacementWorkflowState: ReplacementWorkflowState
        
    public var notificationSettingsState: NotificationSettingsState

    public init(basalRateSchedule: BasalRateSchedule,
                maxBolusUnits: Double,
                pumpState: IDPumpState = IDPumpState(),
                pumpConfiguration: PumpConfiguration = PumpConfiguration.defaultConfiguration,
                unfinalizedBoluses: [BolusID: UnfinalizedDose] = [:],
                finalizedDoses: [UnfinalizedDose] = [],
                dateGenerator: @escaping () -> Date = Date.init)
    {
        self.basalRateSchedule = basalRateSchedule
        self.pumpState = pumpState
        self.pumpConfiguration = pumpConfiguration
        self.dateGeneratorWrapper = DateGeneratorWrapper(dateGenerator: dateGenerator)
        self.unfinalizedBoluses = unfinalizedBoluses
        self.finalizedDoses = finalizedDoses
        self.replacementWorkflowState = ReplacementWorkflowState()
        self.notificationSettingsState = .default
        self.annunciationsPendingConfirmation = []

        self.pumpConfiguration.bolusMaximum = maxBolusUnits
    }


    public init?(rawValue: RawValue) {
        guard
            let _ = rawValue[InsulinDeliveryPumpManagerStateKey.version.rawValue] as? Int,
            let rawBasalRateSchedule = rawValue[InsulinDeliveryPumpManagerStateKey.basalRateSchedule.rawValue] as? BasalRateSchedule.RawValue,
            let basalRateSchedule = BasalRateSchedule(rawValue: rawBasalRateSchedule),
            let rawPumpState = rawValue[InsulinDeliveryPumpManagerStateKey.pumpState.rawValue] as? IDPumpState.RawValue,
            let pumpState = IDPumpState(rawValue: rawPumpState),
            let rawConfiguration = rawValue[InsulinDeliveryPumpManagerStateKey.pumpConfiguration.rawValue] as? Data,
            let pumpConfiguration = try? PropertyListDecoder().decode(PumpConfiguration.self, from: rawConfiguration),
            let onboardingCompleted = rawValue[InsulinDeliveryPumpManagerStateKey.onboardingCompleted.rawValue] as? Bool
            else
        {
            return nil
        }
        
        self.dateGeneratorWrapper = DateGeneratorWrapper(dateGenerator: Date.init)

        self.basalRateSchedule = basalRateSchedule
        self.pumpState = pumpState
        self.pumpConfiguration = pumpConfiguration
        self.lastStatusDate = rawValue[InsulinDeliveryPumpManagerStateKey.lastStatusDate.rawValue] as? Date
        self.pumpActivatedAt = rawValue[InsulinDeliveryPumpManagerStateKey.pumpActivatedAt.rawValue] as? Date
        self.onboardingCompleted = onboardingCompleted
        self.onboardingVideosWatched = rawValue[InsulinDeliveryPumpManagerStateKey.onboardingVideosWatched.rawValue] as? [String] ?? []
        self.notificationSettingsState = (rawValue[InsulinDeliveryPumpManagerStateKey.notificationSettingsState.rawValue] as? NotificationSettingsState.RawValue)
            .flatMap { NotificationSettingsState(rawValue: $0) } ?? .default

        self.totalInsulinDelivery = rawValue[InsulinDeliveryPumpManagerStateKey.totalInsulinDelivery.rawValue] as? Double

        if let rawSuspendState = rawValue[InsulinDeliveryPumpManagerStateKey.suspendState.rawValue] as? SuspendState.RawValue {
            self.suspendState = SuspendState(rawValue: rawSuspendState)
        }

        if let rawUnfinalizedBoluses = rawValue[InsulinDeliveryPumpManagerStateKey.unfinalizedBoluses.rawValue] as? Data,
        let unfinalizedBoluses = try? PropertyListDecoder().decode([BolusID: UnfinalizedDose].self, from: rawUnfinalizedBoluses)
        {
            self.unfinalizedBoluses = unfinalizedBoluses
        } else {
            self.unfinalizedBoluses = [:]
        }

        self.unfinalizedSuspendDetected = rawValue[InsulinDeliveryPumpManagerStateKey.unfinalizedSuspendDetected.rawValue] as? Bool

        if let rawUnfinalizedTempBasal = rawValue[InsulinDeliveryPumpManagerStateKey.unfinalizedTempBasal.rawValue] as? UnfinalizedDose.RawValue {
          self.unfinalizedTempBasal = UnfinalizedDose(rawValue: rawUnfinalizedTempBasal)
        }

        if let rawPendingInsulinDeliveryCommand = rawValue[InsulinDeliveryPumpManagerStateKey.pendingInsulinDeliveryCommand.rawValue] as? PendingInsulinDeliveryCommand.RawValue {
            self.pendingInsulinDeliveryCommand = PendingInsulinDeliveryCommand(rawValue: rawPendingInsulinDeliveryCommand)
        }

        if let rawFinalizedDoses = rawValue[InsulinDeliveryPumpManagerStateKey.finalizedDoses.rawValue] as? [UnfinalizedDose.RawValue] {
            self.finalizedDoses = rawFinalizedDoses.compactMap( { UnfinalizedDose(rawValue: $0) } )
        } else {
            self.finalizedDoses = []
        }

        if let rawReplacementWorkflowState = rawValue[InsulinDeliveryPumpManagerStateKey.replacementWorkflowState.rawValue] as? ReplacementWorkflowState.RawValue,
           let replacementWorkflowState = ReplacementWorkflowState(rawValue: rawReplacementWorkflowState)
        {
            self.replacementWorkflowState = replacementWorkflowState
        } else {
            self.replacementWorkflowState = ReplacementWorkflowState()
        }

        self.annunciationsPendingConfirmation = []
        if let rawAnnunciations = rawValue[InsulinDeliveryPumpManagerStateKey.annunciationsPendingConfirmation.rawValue] as? [GeneralAnnunciation.RawValue] {
            for rawAnnunciation in rawAnnunciations {
                if let annunciation = GeneralAnnunciation(rawValue: rawAnnunciation) {
                    self.annunciationsPendingConfirmation.insert(annunciation)
                }
            }
        }

        self.lastPumpTime = rawValue[InsulinDeliveryPumpManagerStateKey.lastPumpTime.rawValue] as? Date

        self.lowReservoirWarningThresholdInUnits = rawValue[InsulinDeliveryPumpManagerStateKey.lowReservoirWarningThresholdInUnits.rawValue] as? Int ?? PumpConfiguration.defaultConfiguration.reservoirLevelWarningThresholdInUnits

        self.expirationReminderTimeBeforeExpiration = rawValue[InsulinDeliveryPumpManagerStateKey.expirationReminderTimeBeforeExpiration.rawValue] as? TimeInterval ?? PumpConfiguration.defaultConfiguration.expiryWarningDuration

        if let rawPreviousPumpRemainingLifetime = rawValue[InsulinDeliveryPumpManagerStateKey.previousPumpRemainingLifetime.rawValue] as? Data,
           let previousPumpRemainingLifetime = try? PropertyListDecoder().decode([String: TimeInterval].self, from: rawPreviousPumpRemainingLifetime)
        {
            self.previousPumpRemainingLifetime = previousPumpRemainingLifetime
        } else {
            self.previousPumpRemainingLifetime = [:]
        }
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [
            InsulinDeliveryPumpManagerStateKey.version.rawValue: InsulinDeliveryPumpManagerState.version,
            InsulinDeliveryPumpManagerStateKey.basalRateSchedule.rawValue: basalRateSchedule.rawValue,
            InsulinDeliveryPumpManagerStateKey.pumpState.rawValue: pumpState.rawValue,
            InsulinDeliveryPumpManagerStateKey.finalizedDoses.rawValue: finalizedDoses.map( { $0.rawValue }),
            InsulinDeliveryPumpManagerStateKey.onboardingCompleted.rawValue: onboardingCompleted
        ]

        let rawConfiguration = try? PropertyListEncoder().encode(pumpConfiguration)
        rawValue[InsulinDeliveryPumpManagerStateKey.pumpConfiguration.rawValue] = rawConfiguration
        rawValue[InsulinDeliveryPumpManagerStateKey.lastStatusDate.rawValue] = lastStatusDate
        rawValue[InsulinDeliveryPumpManagerStateKey.pumpActivatedAt.rawValue] = pumpActivatedAt
        rawValue[InsulinDeliveryPumpManagerStateKey.totalInsulinDelivery.rawValue] = totalInsulinDelivery
        rawValue[InsulinDeliveryPumpManagerStateKey.suspendState.rawValue] = suspendState?.rawValue
        rawValue[InsulinDeliveryPumpManagerStateKey.unfinalizedSuspendDetected.rawValue] = unfinalizedSuspendDetected
        rawValue[InsulinDeliveryPumpManagerStateKey.unfinalizedTempBasal.rawValue] = unfinalizedTempBasal?.rawValue
        rawValue[InsulinDeliveryPumpManagerStateKey.pendingInsulinDeliveryCommand.rawValue] = pendingInsulinDeliveryCommand?.rawValue
        rawValue[InsulinDeliveryPumpManagerStateKey.notificationSettingsState.rawValue] = notificationSettingsState.rawValue
        rawValue[InsulinDeliveryPumpManagerStateKey.replacementWorkflowState.rawValue] = replacementWorkflowState.rawValue
        rawValue[InsulinDeliveryPumpManagerStateKey.onboardingVideosWatched.rawValue] = onboardingVideosWatched
        rawValue[InsulinDeliveryPumpManagerStateKey.annunciationsPendingConfirmation.rawValue] = annunciationsPendingConfirmation.map { $0.rawValue }
        rawValue[InsulinDeliveryPumpManagerStateKey.lastPumpTime.rawValue] = lastPumpTime
        rawValue[InsulinDeliveryPumpManagerStateKey.lowReservoirWarningThresholdInUnits.rawValue] = lowReservoirWarningThresholdInUnits
        rawValue[InsulinDeliveryPumpManagerStateKey.expirationReminderTimeBeforeExpiration.rawValue] = expirationReminderTimeBeforeExpiration

        let rawUnfinalizedBoluses = try? PropertyListEncoder().encode(unfinalizedBoluses)
        rawValue[InsulinDeliveryPumpManagerStateKey.unfinalizedBoluses.rawValue] = rawUnfinalizedBoluses

        let rawPreviousPumpRemainingLifetime = try? PropertyListEncoder().encode(previousPumpRemainingLifetime)
        rawValue[InsulinDeliveryPumpManagerStateKey.previousPumpRemainingLifetime.rawValue] = rawPreviousPumpRemainingLifetime

        return rawValue
    }
}

extension InsulinDeliveryPumpManagerState: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            "* pumpActivatedAt: \(String(describing: pumpActivatedAt))",
            "* timeZone: \(timeZone)",
            "* lastPumpTime: \(String(describing: lastPumpTime))",
            "* suspendState: \(String(describing: suspendState))",
            "* basalRateSchedule: \(basalRateSchedule)",
            "* pumpState: \(pumpState)",
            "* pumpConfiguration: \(pumpConfiguration)",
            "* finalizedDoses: \(finalizedDoses)",
            "* unfinalizedBoluses: \(String(describing: unfinalizedBoluses))",
            "* unfinalizedTempBasal: \(String(describing: unfinalizedTempBasal))",
            "* lastReplacementDates: \(replacementWorkflowState.lastPumpReplacementDate.map {"\($0)"} ?? "")",
            "* notificationSettingsState: \(notificationSettingsState)",
            "* lastStatusDate: \(String(describing: lastStatusDate?.description(with: .current)))",
            "* lastCommsDate: \(String(describing: pumpState.lastCommsDate?.description(with: .current)))",
            "* onboardingCompleted: \(onboardingCompleted)",
            "* replacementWorkflowState: \(String(describing: replacementWorkflowState))",
            "* annunciationsPendingConfirmation: \(annunciationsPendingConfirmation)",
            "* lowReservoirWarningThresholdInUnits: \(lowReservoirWarningThresholdInUnits)",
            "* expirationReminderTimeBeforeExpiration: \(expirationReminderTimeBeforeExpiration)",
            "* previousPumpRemainingLifetime: \(previousPumpRemainingLifetime)",
            ].joined(separator: "\n")
    }
}

public enum SuspendState: Equatable, RawRepresentable {
    public typealias RawValue = [String: Any]

    private enum SuspendStateType: Int {
        case suspended, resumed
    }

    case suspended(Date)
    case resumed(Date)

    public init?(rawValue: RawValue) {
        guard let rawSuspendStateType = rawValue["type"] as? SuspendStateType.RawValue,
            let date = rawValue["date"] as? Date,
            let suspendStateType = SuspendStateType(rawValue: rawSuspendStateType) else
        {
                return nil
        }
        switch suspendStateType {
        case .suspended:
            self = .suspended(date)
        case .resumed:
            self = .resumed(date)
        }
    }

    public var rawValue: RawValue {
        switch self {
        case .suspended(let date):
            return [
                "type": SuspendStateType.suspended.rawValue,
                "date": date
            ]
        case .resumed(let date):
            return [
                "type": SuspendStateType.resumed.rawValue,
                "date": date
            ]
        }
    }
}

public protocol InsulinDeliveryPumpManagerStatePublisher: AnyObject {
    var state: InsulinDeliveryPumpManagerState { get }
    var isPumpConnected: Bool { get }
    func addPumpManagerStateObserver(_ observer: InsulinDeliveryPumpManagerStateObserver, queue: DispatchQueue)
    func removePumpManagerStateObserver(_ observer: InsulinDeliveryPumpManagerStateObserver)
}

public protocol InsulinDeliveryPumpManagerStateObserver: AnyObject {
    func pumpManagerDidUpdateState(_ pumpManager: InsulinDeliveryPumpManager, _ state: InsulinDeliveryPumpManagerState)
}

// FOR PREVIEWS AND TESTS ONLY
extension InsulinDeliveryPumpManagerState {
    public static var forPreviewsAndTests: InsulinDeliveryPumpManagerState {
        let basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0)])!
        let pumpState = IDPumpState(deviceInformation: DeviceInformation(identifier: UUID(), serialNumber: "12345678", reportedRemainingLifetime: InsulinDeliveryPumpManager.lifespan))
        let pumpConfiguration = PumpConfiguration.defaultConfiguration
        var state = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule, maxBolusUnits: 10.0, pumpState: pumpState, pumpConfiguration: pumpConfiguration)
        state.suspendState = SuspendState.resumed(Date())
        return state
    }
}

extension InsulinDeliveryPumpManagerState {
    public func getLifespan() -> TimeInterval {
        InsulinDeliveryPumpManager.lifespan
    }

    public func getExpirationDate() -> Date? {
        pumpState.deviceInformation?.estimatedExpirationDate
    }
}
