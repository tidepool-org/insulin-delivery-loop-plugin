//
//  InsulinDeliveryPumpManager.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2020-03-13.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import HealthKit
import UIKit
import os.log
import LoopAlgorithm
import LoopKit
import TidepoolSecurity
import InsulinDeliveryServiceKit
import BluetoothCommonKit

public protocol InsulinDeliveryPumpObserver: AnyObject {
    func didDiscoverPump(name: String?, identifier: UUID, serialNumber: String?, remainingLifetime: TimeInterval?)
    func pumpConnectionStatusChanged(connected: Bool)
    func pumpDidCompleteAuthentication(error: DeviceCommError?)
    func pumpDidCompleteConfiguration()
    func pumpDidCompleteTherapyUpdate()
    func pumpDidUpdateState()
    func pumpNotConfigured()
    func pumpEncounteredReservoirIssue()
}

public extension InsulinDeliveryPumpObserver {
    // observing specific events is optional
    func didDiscoverPump(name: String?, identifier: UUID, serialNumber: String?, remainingLifetime: TimeInterval?) { }
    func pumpConnectionStatusChanged(connected: Bool) { }
    func pumpDidCompleteAuthentication(error: DeviceCommError?) { }
    func pumpDidCompleteConfiguration() { }
    func pumpDidCompleteTherapyUpdate() { }
    func pumpDidUpdateState() { }
    func pumpNotConfigured() { }
    func pumpEncounteredReservoirIssue() { }
}

public enum InsulinDeliveryPumpStatusBadge {
    case lowBattery
    case timeSyncNeeded
}

open class InsulinDeliveryPumpManager: PumpManager, InsulinDeliveryPumpDelegate {
    typealias PreflightResult = Result<Void, PumpManagerError>
    
    public static var onboardingMaximumBasalScheduleEntryCount: Int { InsulinDeliveryPumpManager.maximumBasalScheduleEntryCount }

    public static var onboardingSupportedBasalRates: [Double] { InsulinDeliveryPumpManager.supportedBasalRates }

    public static var onboardingSupportedBolusVolumes: [Double] { InsulinDeliveryPumpManager.supportedBolusVolumes }

    public static var onboardingSupportedMaximumBolusVolumes: [Double] { InsulinDeliveryPumpManager.supportedMaximumBolusVolumes }

    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        TimeInterval(units / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate)
    }

    public func ensureCurrentPumpData(completion: ((Date?) -> Void)?) {
        guard !isInReplacementWorkflow else {
            log.default("Replacement workflow in progress. Wait until it is completed")
            completion?(lastSync)
            return
        }

        pump.updateStatus() { [weak self] result in
            self?.maybeUpdateStatusHighlight { [weak self] in
                completion?(self?.lastSync)
                
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    self.log.default("Error getting pump status: %{public}@", String(describing: error))
                    self.pumpDelegate.notify({ delegate in
                        delegate?.pumpManager(self, didError: PumpManagerError.communication(error))
                    })
                case .success(_):
                    // even if there are no doses to store, call reportCachedDoses to report lastSync
                    self.reportCachedDoses()
                }
            }

            // Check if time zone or dst changed or pump clock drift
            self?.checkForTimeOffsetChange()
            self?.checkForPumpClockDrift()
        }
    }

    open var localizedTitle: String {
        LocalizedString("Insulin Delivery Pump", comment: "Generic title of the pump manager")
    }

    public var isOnboarded: Bool {
        return state.onboardingCompleted
    }

    public func markOnboardingCompleted() {
        mutateState { state in
            state.onboardingCompleted = true
        }
    }

    public var replacementWorkflowState: InsulinDeliveryPumpManagerState.ReplacementWorkflowState {
        get {
            state.replacementWorkflowState
        }
        set {
            mutateState { state in
                state.replacementWorkflowState = newValue
            }
        }
    }
        
    public var notificationSettingsState: InsulinDeliveryPumpManagerState.NotificationSettingsState {
        get {
            state.notificationSettingsState
        }
        set {
            mutateState { state in
                state.notificationSettingsState = newValue
            }
        }
    }
    
    public var lastPumpReplacementDate:Date? {
        get {
            state.replacementWorkflowState.lastPumpReplacementDate
        }
        set {
            mutateState { state in
                state.replacementWorkflowState.lastPumpReplacementDate = newValue
            }
        }
    }

    public func updateReplacementWorkflowState(milestoneProgress: [Int], pumpSetupState: PumpSetupState?) {
        replacementWorkflowState = replacementWorkflowState.updatedWith(milestoneProgress: milestoneProgress,
                                                                        pumpSetupState: pumpSetupState,
                                                                        wasWorkflowCanceled: false)
    }

    public func replacementWorkflowCompleted() {
        retractAllAlertsResolvedByPumpReplacement()
        replacementWorkflowState = replacementWorkflowState.updatedAfterReplacingPump(dateGenerator)
        finalizeAllCachedDoses()
    }

    public func replacementWorkflowCanceled() {
        replacementWorkflowState = replacementWorkflowState.canceled
    }

    func retractAllAlertsResolvedByPumpReplacement() {
        reportPumpAlarmCleared()
        retractPumpExpirationReminderAlert()
        
        pumpDelegate.notify { delegate in
            delegate?.lookupAllUnretracted(managerIdentifier: self.pluginIdentifier) { [weak self] result in
                switch result {
                case .failure(let error):
                    self?.log.error("Failed to retract outstanding alerts: %{public}@", error.localizedDescription)
                case .success(let alerts):
                    let alertsToRetract = alerts
                        .filter {
                            (try? $0.alert.annunciationType().isResolvedByPumpReplacement) ?? false
                        }
                        .map {
                            $0.alert.identifier
                        }
                    self?.log.debug("Retracting alerts: %{public}@", alertsToRetract.debugDescription)
                    alertsToRetract
                        .forEach {
                            self?.retractAlert(identifier: $0)
                        }
                }
            }
        }
    }

    open var log: OSLog {
        OSLog(category: "InsulinDeliveryPumpManager")
    }
    
    public let pump: InsulinDeliveryPumpComms
        
    public static var managerIdentifier: String { "InsulinDeliveryPump" }
    
    public var pluginIdentifier: String { Self.managerIdentifier }
        
    public func roundToSupportedBasalRate(unitsPerHour: Double) -> Double {
         return supportedBasalRates.filter({$0 <= unitsPerHour}).max() ?? 0
    }
    
    public var supportedBasalRates: [Double] {
        return InsulinDeliveryPumpManager.supportedBasalRates
    }
    
    public func roundToSupportedBolusVolume(units: Double) -> Double {
        return InsulinDeliveryPumpManager.roundToSupportedBolusVolume(units: units)
    }

    public var supportedBolusVolumes: [Double] {
        return InsulinDeliveryPumpManager.supportedBolusVolumes
    }

    public var supportedMaximumBolusVolumes: [Double] {
        return InsulinDeliveryPumpManager.supportedMaximumBolusVolumes
    }
    
    public var maximumBasalScheduleEntryCount: Int {
        return InsulinDeliveryPumpManager.maximumBasalScheduleEntryCount
    }
    
    public var minimumBasalScheduleEntryDuration: TimeInterval {
        return InsulinDeliveryPumpManager.minimumBasalScheduleEntryDuration
    }
    
    public func setMaximumTempBasalRate(_ rate: Double) { }
    
    public var pumpRecordsBasalProfileStartEvents = false
    
    public var pumpReservoirCapacity: Double = InsulinDeliveryPumpManager.pumpReservoirCapacity
    
    public var reservoirLevel: Double? {
        return state.pumpState.deviceInformation?.reservoirLevel
    }
    
    private var lastReportedReservoirLevel: Double?
    
    private(set) public var lastSync: Date? {
        get {
            return state.lastStatusDate
        }
        set {
            mutateState { state in
                state.lastStatusDate = newValue
            }
        }
    }
    
    public var tidepoolSecurity: TidepoolSecurity?

    // NOTE: Must only be updated on .main
    public var pumpStatusHighlight: DeviceStatusHighlight?
    public var insulinDeliveryPumpStatusBadge: InsulinDeliveryPumpStatusBadge?
    
    @discardableResult private func mutateState(_ changes: (_ state: inout InsulinDeliveryPumpManagerState) -> Void) -> InsulinDeliveryPumpManagerState {
        return setStateWithResult({ state -> InsulinDeliveryPumpManagerState in
            changes(&state)
            return state
        })
    }

    private func setStateWithResult<ReturnType>(_ changes: (_ state: inout InsulinDeliveryPumpManagerState) -> ReturnType) -> ReturnType {
        var oldValue: InsulinDeliveryPumpManagerState!
        var returnValue: ReturnType!
        let newValue = lockedState.mutate { state in
            oldValue = state
            returnValue = changes(&state)
        }
        
        guard oldValue != newValue else {
            return returnValue
        }

        checkForExpirationReminderCondition(
            newRemainingLifetime: newValue.pumpState.deviceInformation?.reportedRemainingLifetime,
            oldRemainingLifeTime: oldValue.pumpState.deviceInformation?.reportedRemainingLifetime,
            newThreshold: newValue.expirationReminderTimeBeforeExpiration,
            oldThreshold: oldValue.expirationReminderTimeBeforeExpiration
        )

        maybeUpdateStatusHighlight(oldState: oldValue)
        
        pumpDelegate.notify { [weak self] delegate in
            guard let self else { return }
            
            if let newReservoirLevel = newValue.pumpState.deviceInformation?.reservoirLevel {
                let shouldReportReservoirLevel = lastReportedReservoirLevel == nil ? true : abs(self.lastReportedReservoirLevel!-newReservoirLevel) >= 5.0 // only report reservoir with each 5U of delivery or when the reservoir has been filled
                
                if shouldReportReservoirLevel {
                    self.lastReportedReservoirLevel = newReservoirLevel
                    reportCachedDoses() { [weak self] _ in
                        guard let self else { return }
                        
                        delegate?.pumpManager(self,
                                              didReadReservoirValue: newReservoirLevel,
                                              at: self.lastSync ?? self.now,
                                              completion: { _ in })
                    }
                }
            }
            
            delegate?.pumpManagerDidUpdateState(self)
        }
        
        pumpManagerStateObservers.forEach { observer in
            observer.pumpManagerDidUpdateState(self, newValue)
        }
        
        return returnValue
    }

    private func checkForLowReservoirCondition(newValue: Double?, oldValue: Double?) {
        guard let newValue = newValue, let oldValue = oldValue else {
            return
        }

        let threshold = Double(state.lowReservoirWarningThresholdInUnits)

        let annunciation = LowReservoirAnnunciation(identifier: 0, currentReservoirWarningLevel: state.lowReservoirWarningThresholdInUnits)
        let alert = Alert(with: annunciation, managerIdentifier: self.pluginIdentifier)

        if newValue <= threshold && oldValue > threshold {
            issueAlert(alert)
        }

        if newValue > oldValue + 1 {
            retractAlert(identifier: alert.identifier)
        }

    }

    private func checkForExpirationReminderCondition(
        newRemainingLifetime: TimeInterval?,
        oldRemainingLifeTime: TimeInterval?,
        newThreshold: TimeInterval,
        oldThreshold: TimeInterval
    ) {

        var wasAlerting: Bool
        var isAlerting: Bool

        if let oldRemainingLifeTime = oldRemainingLifeTime {
            wasAlerting = oldRemainingLifeTime < oldThreshold
        } else {
            wasAlerting = false
        }

        if let newRemainingLifetime = newRemainingLifetime {
            // If we're actually expired, do not alert reminder, as actual expiration alert should trigger,
            // and it's confusing to show the reminder (with negative time remaining) alongside the alert
            // that tells them the pump *is* expired.
            guard newRemainingLifetime > 0 else { return }

            isAlerting = newRemainingLifetime < newThreshold
        } else {
            isAlerting = false
        }

        let annunciation = PumpExpiresSoonAnnunciation(identifier: 0, timeRemaining: newRemainingLifetime)
        let alert = Alert(with: annunciation, managerIdentifier: self.pluginIdentifier)

        if !wasAlerting && isAlerting {
            issueAlert(alert)
        }

        if wasAlerting && !isAlerting {
            retractAlert(identifier: alert.identifier)
        }
    }

    private func notifyStatusObservers(oldStatus: PumpManagerStatus) {
        let status = self.status

        pumpDelegate.notify { delegate in
            delegate?.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
        }
        statusObservers.forEach { observer in
            observer.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
        }
    }
    
    private let lockedState: LoopKit.Locked<InsulinDeliveryPumpManagerState>
    
    public var state: InsulinDeliveryPumpManagerState {
        return lockedState.value
    }

    public var pumpTimeZone: TimeZone {
        state.timeZone
    }
    
    private func maybeUpdateStatusHighlight(oldState: InsulinDeliveryPumpManagerState? = nil, completion: (() -> Void)? = nil) {
        lookupLatestAnnunciation { [self] annunciationType in
            var shouldNotify: Bool
            if let oldState = oldState, status(for: oldState) != status(for: state) {
                shouldNotify = true
            } else {
                shouldNotify = false
            }
            let newStatusHighlight = Self.determinePumpStatusHighlight(state: state, latestAnnunciationType: annunciationType, isPumpConnected: isPumpConnected, now: dateGenerator)
            let oldStatusHighlight = self.pumpStatusHighlight
            if !newStatusHighlight.isEqual(to: oldStatusHighlight) || annunciationType?.statusBadge != insulinDeliveryPumpStatusBadge {
                pumpStatusHighlight = newStatusHighlight
                // Status badge should persist until replacement workflow, so unless `annunciationType` is nil (which
                // means there are no outstanding, unretracted, annunciations) keep the badge persistent.
                if annunciationType == nil || annunciationType?.statusBadge != nil {
                    // NOTE: if we ever have more than one type of badge, we may need to add a prioritization scheme
                    // here.  Right now there's only one, so last one wins.
                    insulinDeliveryPumpStatusBadge = annunciationType?.statusBadge
                }
                shouldNotify = true
            }
            
            if insulinDeliveryPumpStatusBadge == nil, isClockOffset {
                insulinDeliveryPumpStatusBadge = .timeSyncNeeded
                shouldNotify = true
            }

            if shouldNotify {
                self.notifyStatusObservers(oldStatus: self.status(for: oldState ?? self.state))
            }
            completion?()
        }
    }
    
    // Signal Loss
    private var signalLossCheckTimer: Timer?
    
    private func stopSignalLossCheckTimer() {
        logDelegateEvent()
        signalLossCheckTimer?.invalidate()
        signalLossCheckTimer = nil
    }
    
    private func scheduleSignalLossCheckTimer() {
        stopSignalLossCheckTimer()
        logDelegateEvent()

        // only schedule signal loss check if pump exists and comms occurred at some point
        guard deviceInformation != nil, lastSync != nil else { return }

        signalLossCheckTimer = Timer(timeInterval: InsulinDeliveryPumpManager.signalLossTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            logDelegateEvent("signal loss check fired. lastSync: \(String(describing: self.lastSync))")
            self.maybeUpdateStatusHighlight()
        }
        RunLoop.main.add(signalLossCheckTimer!, forMode: .default)
    }
    
    static let signalLossTimeout = TimeInterval.minutes(10.5)
    
    public static func isSignalLost(lastCommsDate: Date?, isPumpConnected: Bool, asOf now: @escaping () -> Date = Date.init) -> Bool {
        guard !isPumpConnected else { return false }
        guard let lastCommsDate = lastCommsDate else { return false }
        let now = now()
        return now.timeIntervalSince(lastCommsDate) > InsulinDeliveryPumpManager.signalLossTimeout
    }
    
    static func determinePumpStatusHighlight(state: InsulinDeliveryPumpManagerState, latestAnnunciationType: AnnunciationType?, isPumpConnected: Bool, now: @escaping () -> Date) -> DeviceStatusHighlight? {
        // There is a priority order to the status highlight. This determines it.
        if !state.onboardingCompleted {
            return CompleteSetupPumpStatusHighlight()
        } else if state.replacementWorkflowState.isWorkflowIncomplete {
            return IncompleteReplacementPumpStatusHighlight()
        } else if let statusHighlight = latestAnnunciationType?.statusHighlight {
            return statusHighlight
        } else if Self.isSignalLost(lastCommsDate: state.pumpState.lastCommsDate, isPumpConnected: isPumpConnected, asOf: now) ||
                    state.pendingInsulinDeliveryCommand != nil
        {
            return SignalLossPumpStatusHighlight()
        } else if state.isSuspended {
            return InsulinSuspendedPumpStatusHighlight()
        } else {
            return nil
        }
    }
    
    public func lookupLatestAnnunciation(_ completion: @escaping (AnnunciationType?) -> Void) {
        pumpDelegate.notify { delegate in
            delegate?.lookupAllUnretracted(managerIdentifier: self.pluginIdentifier) { [weak self] result in
                switch result {
                case .success(var alerts):
                    self?.log.debug("Highest priority annunciation type: %{public}@, Latest unretracted alerts: %{public}@",
                                   alerts.highestPriorityAnnunciationType().debugDescription,
                                   alerts.map { ($0.alert.identifier.alertIdentifier, $0.issuedDate) }.debugDescription)
                    completion(alerts.highestPriorityAnnunciationType())
                case .failure(let error):
                    self?.log.error("Failed to build pump status highlight: %{public}@", error.localizedDescription)
                    completion(nil)
                }
            }
        }
    }
    
    public var status: PumpManagerStatus {
        return status(for: state)
    }
    
    private func status(for state: InsulinDeliveryPumpManagerState) -> PumpManagerStatus {
        let pumpBatteryChargeRemaining = state.pumpState.deviceInformation?.batteryLevel.map { Double($0) / 100.0 }
        return PumpManagerStatus(
            timeZone: pumpTimeZone,
            device: device(for: state.pumpState.deviceInformation),
            pumpBatteryChargeRemaining: pumpBatteryChargeRemaining,
            basalDeliveryState: basalDeliveryState(for: state),
            bolusState: bolusState(for: state),
            insulinType: nil, // Not supporting insulin type yet
            deliveryIsUncertain: !state.replacementWorkflowState.isWorkflowIncomplete && state.pendingInsulinDeliveryCommand != nil // workflows have specific handling of uncertain commands
        )
    }

    private var pendingInsulinDeliveryCommand: PendingInsulinDeliveryCommand? {
        get {
            state.pendingInsulinDeliveryCommand
        }
        set {
            if state.pendingInsulinDeliveryCommand != newValue {
                mutateState { state in
                    state.pendingInsulinDeliveryCommand = newValue
                }
            }
        }
    }
    
    private var annunciationsPendingConfirmation: Set<GeneralAnnunciation> {
        get {
            state.annunciationsPendingConfirmation
        }
        set {
            if state.annunciationsPendingConfirmation != newValue {
                mutateState { state in
                    state.annunciationsPendingConfirmation = newValue
                }
            }
        }
    }

    private func basalDeliveryState(for state: InsulinDeliveryPumpManagerState) -> PumpManagerStatus.BasalDeliveryState? {
        if let transition = state.activeTransition {
            switch transition {
            case .suspendingPump:
                return .suspending
            case .resumingPump:
                return .resuming
            case .cancelingTempBasal:
                return .cancelingTempBasal
            case .startingTempBasal:
                return .initiatingTempBasal
            default:
                break
            }
        }
        
        if let tempBasal = state.unfinalizedTempBasal, !tempBasal.isFinished(at: now) {
            return .tempBasal(DoseEntry(tempBasal, at: now))
        }
        
        switch state.suspendState {
        case .resumed(let date):
            return .active(date)
        case .suspended(let date):
            guard !replacementWorkflowState.isWorkflowIncomplete else {
                // insulin delivery is suspended, but the workflow needs to be completed before it can be resumed
                return .pumpInoperable
            }

            guard deviceInformation?.pumpOperationalState == .ready else {
                // the pump is in a state where insulin delivery cannot be resumed
                logDelegateEvent("Pump cannot deliver insulin. pump operational state \(String(describing: deviceInformation?.pumpOperationalState))")
                return .pumpInoperable
            }

            return .suspended(date)
        case .none:
            return nil
        }
    }
    
    private func bolusState(for state: InsulinDeliveryPumpManagerState) -> PumpManagerStatus.BolusState {
        if let transition = state.activeTransition {
            switch transition {
            case .startingBolus:
                return .initiating
            case .cancelingBolus:
                return .canceling
            default:
                break
            }
        }

        guard let activeBolusID = state.pumpState.activeBolusDeliveryStatus.id,
              state.unfinalizedBoluses[activeBolusID] != nil,
              let activeBolus = state.pumpState.activeBolusDeliveryStatus.unfinalizedBolus(at: now)
        else {
            return .noBolus
        }
        
        return .inProgress(DoseEntry(activeBolus, at: now))
    }
    
    func setOnboardingVideosWatched(_ newValue: [String]) {
        mutateState { state in
            state.onboardingVideosWatched = newValue
        }
    }

    func storeCurrentPumpRemainingLifetime() {
        guard let pumpRemainingLifetime = deviceInformation?.estimatedRemainingLifeTime,
              let pumpSerialNumber = deviceInformation?.serialNumber
        else { return }
        mutateState { state in
            state.previousPumpRemainingLifetime.removeAll()
            state.previousPumpRemainingLifetime[pumpSerialNumber] = pumpRemainingLifetime
        }
    }
    
    private var statusObservers = WeakSynchronizedSet<PumpManagerStatusObserver>()
    
    public func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        if !statusObservers.contains(observer) {
            statusObservers.insert(observer, queue: queue)
        }
    }
    
    public func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        statusObservers.removeElement(observer)
    }
    
    private var pumpObservers = WeakSynchronizedSet<InsulinDeliveryPumpObserver>()

    public func addPumpObserver(_ observer: InsulinDeliveryPumpObserver, queue: DispatchQueue) {
        if !pumpObservers.contains(observer) {
            pumpObservers.insert(observer, queue: queue)
        }
    }

    public func removePumpObserver(_ observer: InsulinDeliveryPumpObserver) {
        pumpObservers.removeElement(observer)
    }

    private var pumpManagerStateObservers = WeakSynchronizedSet<InsulinDeliveryPumpManagerStateObserver>()

    public func addPumpManagerStateObserver(_ observer: InsulinDeliveryPumpManagerStateObserver, queue: DispatchQueue = .main) {
        if !pumpManagerStateObservers.contains(observer) {
            pumpManagerStateObservers.insert(observer, queue: queue)
        }
    }

    public func removePumpManagerStateObserver(_ observer: InsulinDeliveryPumpManagerStateObserver) {
        pumpManagerStateObservers.removeElement(observer)
    }

    public func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
        // TODO placeholder
    }
    
    public func setBasalSchedule(basalRateSchedule: BasalRateSchedule,
                                 timeZone: TimeZone,
                                 completion: @escaping (Error?) -> Void)
    {
        if state.isSuspended {
            self.pump.setBasalProfile(basalRateSchedule.basalProfile) { [weak self] result in
                switch result {
                case .success():
                    self?.mutateState { state in
                        state.basalRateSchedule = basalRateSchedule
                        state.timeZone = timeZone
                    }
                    completion(nil)
                case .failure(let error):
                    completion(InsulinDeliveryPumpManagerError(error))
                }
            }
        } else {
            suspendDelivery { error in
                guard error == nil else {
                    completion(error!)
                    return
                }
                
                self.pump.setBasalProfile(basalRateSchedule.basalProfile) { [weak self] result in
                    switch result {
                    case .success():
                        self?.mutateState { state in
                            state.basalRateSchedule = basalRateSchedule
                            state.timeZone = timeZone
                        }
                        self?.resumeDelivery() { error in
                            completion(error)
                        }
                    case .failure(let error):
                        completion(InsulinDeliveryPumpManagerError(error))
                    }
                }
            }
        }
    }

    public func setBasalSchedule(dailyItems: [RepeatingScheduleValue<Double>], completion: @escaping (Error?) -> Void) {
        guard dailyItems.allSatisfy({ pump.isValidBasalRate($0.value) }),
            let basalRateSchedule = BasalRateSchedule(dailyItems: dailyItems) else {
            completion(InsulinDeliveryPumpManagerError.invalidBasalSchedule)
            return
        }
        
        setBasalSchedule(basalRateSchedule: basalRateSchedule, timeZone: pumpTimeZone, completion: completion)
    }
    
    public func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter? {
        if case .inProgress(let dose) = bolusState(for: self.state) {
            return InsulinDeliveryDoseProgressTimerEstimator(dose: dose, pumpManager: self, reportingQueue: dispatchQueue)
        }
        return nil
    }

    public func enactBolus(decisionId: UUID?, units: Double, activationType: BolusActivationType, completion: @escaping (PumpManagerError?) -> Void) {
        let preflightResult = setStateWithResult({ state -> PreflightResult in
            if !pump.isConnected {
                logDelegateEvent("preflight failed. pump is not connected")
                return .failure(.connection(InsulinDeliveryPumpManagerError.commError(.disconnected)))
            }
            if !pump.isValidBolusVolume(units) {
                logDelegateEvent("preflight failed. invalid bolus volume")
                return .failure(.configuration(InsulinDeliveryPumpManagerError.invalidBolusVolume))
            }
            if pump.isBolusActive {
                logDelegateEvent("preflight failed. bolus is active")
                return .failure(.deviceState(InsulinDeliveryPumpManagerError.hasActiveCommand))
            }
            if state.suspendState == nil || state.replacementWorkflowState.isWorkflowIncomplete {
                logDelegateEvent("preflight failed. pump is not ready to bolus (suspend state is nil or in replacement workflow is incomplete: \(state.replacementWorkflowState.isWorkflowIncomplete)")
                return .failure(.deviceState(InsulinDeliveryPumpManagerError.commError(.deviceNotReady)))
            }
            if state.isSuspended {
                logDelegateEvent("preflight failed. pump is suspended")
                return .failure(.deviceState(InsulinDeliveryPumpManagerError.insulinDeliverySuspended))
            }
            
            state.activeTransition = .startingBolus
            return .success
        })

        switch preflightResult {
        case .success():
            // Round to nearest supported volume
            let enactUnits = roundToSupportedBolusVolume(units: units)
            let startDate = dateGenerator()

            pump.setBolus(enactUnits, activationType: activationType.idsBolusActivationType) { [weak self] result in
                switch result {
                case .success(let bolusDeliveryStatus):
                    guard let bolusID = bolusDeliveryStatus.id else {
                        fatalError("all boluses must have a bolus id")
                    }
                    self?.mutateState { state in
                        state.unfinalizedBoluses[bolusID] = UnfinalizedDose(decisionId: decisionId, bolusAmount: bolusDeliveryStatus.insulinProgrammed, startTime: startDate, scheduledCertainty: .certain, automatic: activationType.isAutomatic)
                        state.activeTransition = nil
                    }
                    self?.reportCachedDoses()
                    completion(nil)
                case .failure(let error):
                    self?.mutateState { state in
                        state.activeTransition = nil
                    }

                    guard !error.wasCommandUnacknowledged else {
                        self?.pendingInsulinDeliveryCommand = PendingInsulinDeliveryCommand(type: .bolus(enactUnits))
                        completion(.uncertainDelivery)
                        return
                    }
                    
                    guard error != .procedureNotApplicable else {
                        self?.logDelegateEvent("bolus is active")
                        completion(.deviceState(InsulinDeliveryPumpManagerError.hasActiveCommand))
                        return
                    }

                    completion(.communication(InsulinDeliveryPumpManagerError(error)))
                }
            }
        case .failure(let pumpManagerError):
            completion(pumpManagerError)
        }
    }
    
    public func cancelBolus(completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        let preflightResult = setStateWithResult({ state -> PreflightResult in
            if !pump.isConnected {
                logDelegateEvent("preflight failed. pump is not connected")
                return .failure(.connection(InsulinDeliveryPumpManagerError.commError(.disconnected)))
            }
            if state.isSuspended {
                logDelegateEvent("preflight failed. pump is suspended")
                return .failure(.deviceState(InsulinDeliveryPumpManagerError.insulinDeliverySuspended))
            }
            
            state.activeTransition = .cancelingBolus
            return .success
        })

        switch preflightResult {
        case .success:
            pump.cancelBolus() { [weak self] result in
                switch result {
                case .success(let bolusDeliveryStatus):
                    guard let bolusID = bolusDeliveryStatus.id else {
                        fatalError("all boluses must have a bolus id")
                    }
                    let now = self?.now ?? Date()
                    self?.mutateState { state in
                        state.unfinalizedBoluses[bolusID]?.cancel(at: now, insulinDelivered: bolusDeliveryStatus.insulinDelivered)
                        state.activeTransition = nil
                    }
                    let canceledBolus = self?.state.unfinalizedBoluses[bolusID]?.doseEntry(at: now, isFinalized: false)
                    self?.reportCachedDoses()
                    completion(.success(canceledBolus))
                case .failure(let error):
                    self?.mutateState { state in
                        state.activeTransition = nil
                    }

                    guard !error.wasCommandUnacknowledged else {
                        self?.pendingInsulinDeliveryCommand = PendingInsulinDeliveryCommand(type: .cancelBolus)
                        completion(.failure(.uncertainDelivery))
                        return
                    }

                    completion(.failure(.communication(InsulinDeliveryPumpManagerError(error))))
                }
            }
        case .failure(let error):
            completion(.failure(error))
        }
    }
    
    public func updateBolusDeliveryDetails(updateHandler: @escaping (BolusDeliveryStatus) -> Void) {
         guard pump.isBolusActive else {
            updateHandler(BolusDeliveryStatus.noActiveBolus)
            return
        }

        pump.updateActiveBolusDeliveryDetails { [weak self] bolusDeliveryStatus in
            guard let self = self,
                  let bolusID = bolusDeliveryStatus.id,
                  let unfinalizedBolus = bolusDeliveryStatus.unfinalizedBolus(at: self.now)
            else { return }

            self.mutateState { state in
                state.unfinalizedBoluses[bolusID] = unfinalizedBolus
            }
            
            updateHandler(bolusDeliveryStatus)
        }
    }

    public func enactTempBasal(decisionId: UUID?, unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (PumpManagerError?) -> Void) {
        // Cancel the current temp basal when duration is 0
        guard duration != 0 else {
            cancelTempBasal(completion: completion)
            return
        }

        // Round to nearest supported volume
        let enactRate = roundToSupportedBasalRate(unitsPerHour: unitsPerHour)
                
        var replaceExisting = false
        if case .tempBasal = status.basalDeliveryState {
            replaceExisting = true
        }
        let preflightResult = setStateWithResult({ state -> PreflightResult in
            if !pump.isConnected {
                logDelegateEvent("preflight failed. pump is not connected")
                return .failure(.connection(InsulinDeliveryPumpManagerError.commError(.disconnected)))
            }
            if !pump.isValidBasalRate(unitsPerHour) {
                logDelegateEvent("preflight failed. invalid basal rate")
                return .failure(.deviceState(InsulinDeliveryPumpManagerError.invalidTempBasalRate))
            }
            if state.suspendState == nil || state.replacementWorkflowState.isWorkflowIncomplete {
                logDelegateEvent("preflight failed. pump is not ready to bolus (suspend state is nil or in replacement workflow is incomplete: \(state.replacementWorkflowState.isWorkflowIncomplete)")
                return .failure(.deviceState(InsulinDeliveryPumpManagerError.commError(.deviceNotReady)))
            }
            if state.isSuspended {
                logDelegateEvent("preflight failed. pump is suspended")
                return .failure(.deviceState(InsulinDeliveryPumpManagerError.insulinDeliverySuspended))
            }

            state.activeTransition = .startingTempBasal
            return .success
        })

        switch preflightResult {
        case .success:
            let startDate = self.now

            pump.setTempBasal(unitsPerHour: enactRate,
                                  durationInMinutes: UInt16(duration.minutes),
                                  replaceExisting: replaceExisting)
            { [weak self] result in
                switch result {
                case .success():
                    self?.mutateState { state in
                        if var canceledTempBasal = state.unfinalizedTempBasal {
                            let now = self?.now ?? Date()
                            canceledTempBasal.cancel(at: now, insulinDelivered: self?.pump.state.activeTempBasalDeliveryStatus.insulinDelivered)
                            state.finalizedDoses.append(canceledTempBasal)
                        }
                        state.unfinalizedTempBasal = UnfinalizedDose(decisionId: decisionId, tempBasalRate: enactRate, startTime: startDate, duration: duration, scheduledCertainty: .certain)
                        state.activeTransition = nil
                    }
                    self?.reportCachedDoses()
                    completion(nil)
                case .failure(let error):
                    self?.mutateState { state in
                        state.activeTransition = nil
                    }
                    self?.reportCachedDoses()
                    
                    guard !error.wasCommandUnacknowledged else {
                        self?.pendingInsulinDeliveryCommand = PendingInsulinDeliveryCommand(type: .tempBasal(enactRate, duration))
                        completion(.uncertainDelivery)
                        return
                    }

                    completion(.communication(InsulinDeliveryPumpManagerError(error)))
                }
            }
        case .failure(let error):
            completion(error)
        }
    }
    
    public func cancelTempBasal(completion: @escaping (PumpManagerError?) -> Void) {
        let preflightResult = setStateWithResult({ state -> PreflightResult in
            if !pump.isConnected {
                logDelegateEvent("preflight failed. pump is not connected")
                return .failure(.connection(InsulinDeliveryPumpManagerError.commError(.disconnected)))
            }
            if state.isSuspended {
                logDelegateEvent("preflight failed. pump is suspended")
                return .failure(.deviceState(InsulinDeliveryPumpManagerError.insulinDeliverySuspended))
            }
            
            state.activeTransition = .cancelingTempBasal
            return .success
        })

        switch preflightResult {
        case .success:
            pump.cancelTempBasal() { [weak self] result in
                switch result {
                case .success():
                    self?.mutateState { state in
                        if var canceledTempBasal = state.unfinalizedTempBasal {
                            let now = self?.now ?? Date()
                            canceledTempBasal.cancel(at: now, insulinDelivered: self?.pump.state.activeTempBasalDeliveryStatus.insulinDelivered)
                            state.unfinalizedTempBasal = nil
                            state.finalizedDoses.append(canceledTempBasal)
                        }
                        state.activeTransition = nil
                    }
                    self?.reportCachedDoses()
                    completion(nil)
                case .failure(let error):
                    self?.mutateState { state in
                        state.activeTransition = nil
                    }

                    guard !error.wasCommandUnacknowledged else {
                        self?.pendingInsulinDeliveryCommand = PendingInsulinDeliveryCommand(type: .cancelTempBasal)
                        completion(.uncertainDelivery)
                        return
                    }

                    completion(.communication(InsulinDeliveryPumpManagerError(error)))
                }
            }
        case .failure(let error):
            completion(error)
        }
    }

    private func finalizeAllCachedDoses() {
        let now = now
        finalizeCachedBoluses(at: now)
        finalizeCachedTempBasal(at: now)
        reportCachedDoses()
    }

    private func finalizeCachedBoluses(at now: Date = Date()) {
        guard !state.unfinalizedBoluses.isEmpty else { return }

        mutateState { state in
            for (_, var unfinalizedBolus) in state.unfinalizedBoluses {
                if !unfinalizedBolus.isFinished(at: now) {
                    unfinalizedBolus.cancel(at: now)
                }
                state.finalizedDoses.append(unfinalizedBolus)
            }
            state.unfinalizedBoluses.removeAll()
        }
    }

    private func finalizeCachedTempBasal(at now: Date = Date()) {
        guard var unfinalizedTempBasal = state.unfinalizedTempBasal else { return }
        if !unfinalizedTempBasal.isFinished(at: now) {
            let endTime = now > unfinalizedTempBasal.startTime ? now : unfinalizedTempBasal.startTime
            unfinalizedTempBasal.cancel(at: endTime)
        } else {
            let duration = max(0, now.timeIntervalSince(unfinalizedTempBasal.startTime))
            unfinalizedTempBasal.duration = duration
        }

        mutateState { state in
            state.finalizedDoses.append(unfinalizedTempBasal)
            state.unfinalizedTempBasal = nil
        }
    }
    
    private func reportCachedDoses(withAdditionalEvents additionalEvents: [NewPumpEvent]? = nil, completion: ((Error?) -> Void)? = nil) {
        var dosesToStore: [UnfinalizedDose: Bool] = [:] // dose mapped to isFinalized flag

        lockedState.mutate { state in
            for finalizeddDose in state.finalizedDoses {
                dosesToStore[finalizeddDose] = true
            }

            for (_, unfinalizedBolus) in state.unfinalizedBoluses {
                dosesToStore[unfinalizedBolus] = false
            }

            if let unfinalizedTempBasal = state.unfinalizedTempBasal {
                dosesToStore[unfinalizedTempBasal] = false
            }
        }
        
        var pumpEventsToStore = dosesToStore.map { NewPumpEvent($0.key, at: self.now, isFinalized: $0.value) }
        if let additionalEvents {
            pumpEventsToStore.append(contentsOf: additionalEvents)
        }
       
        reportPumpEvents(pumpEventsToStore, completion: { [weak self] error in
            if error == nil {
                self?.lockedState.mutate { state in
                    state.finalizedDoses.removeAll { dose in dosesToStore[dose] == true }
                }
            }
            completion?(error)
        })
    }
    
    private func reportPumpEvents(_ pumpEvents: [NewPumpEvent], completion: @escaping (_ error: Error?) -> Void) {
        let lastSync = lastSync
        
        pumpDelegate.notify { [weak self] delegate in
            guard let self else { return }
            delegate?.pumpManager(self, hasNewPumpEvents: pumpEvents, lastReconciliation: lastSync, replacePendingEvents: true, completion: { [weak self] error in
                if let error = error {
                    self?.log.error("Error storing pump events: %{public}@ %{public}@", String(describing: pumpEvents), String(describing: error))
                } else {
                    self?.log.debug("Stored pump events: %{public}@", String(describing: pumpEvents))
                }
                completion(error)
            })
        }
    }

    public func suspendDelivery(reminderDelay: TimeInterval, completion: @escaping (Error?) -> Void) {
        suspendDelivery { [weak self] error in
            if error == nil {
                self?.issueInsulinSuspensionReminderAlert(reminderDelay: reminderDelay)
            }
            completion(error)
        }
    }

    public func suspendDelivery(completion: @escaping (Error?) -> Void) {
        let preflightResult = setStateWithResult({ state -> PreflightResult in
            if !pump.isConnected {
                logDelegateEvent("preflight failed. pump is not connected")
                return .failure(.connection(InsulinDeliveryPumpManagerError.commError(.disconnected)))
            }
            state.activeTransition = .suspendingPump
            return .success
        })

        switch preflightResult {
        case .success:
            pump.suspendInsulinDelivery { [weak self] result in
                switch result {
                case .success(_):
                    guard let self = self else {
                        completion(nil)
                        return
                    }
                    let now = self.now
                    self.cancelActiveDoses(at: now, canFinalizeDoses: true) // doses can be finalized, since suspend is issued from the pump manager
                    self.createInsulinSuspendedDose(at: now)
                    self.reportCachedDoses()
                    self.mutateState { state in
                        state.activeTransition = nil
                    }
                    completion(nil)
                case .failure(let error):
                    self?.mutateState { state in
                        state.activeTransition = nil
                    }

                    guard !error.wasCommandUnacknowledged else {
                        self?.pendingInsulinDeliveryCommand = PendingInsulinDeliveryCommand(type: .suspendInsulinDelivery)
                        completion(PumpManagerError.uncertainDelivery)
                        return
                    }

                    completion(PumpManagerError.communication(InsulinDeliveryPumpManagerError(error)))
                }
            }
        case .failure(let error):
            completion(error)
        }
    }

    private func cancelActiveDoses(at date: Date = Date(), canFinalizeDoses: Bool = false) {
        cancelActiveTempBasal(at: date, canFinalize: canFinalizeDoses)
        cancelActiveBoluses(at: date)
    }

    private func cancelActiveTempBasal(at date: Date = Date(), canFinalize: Bool) {
        guard var unfinalizedTempBasal = state.unfinalizedTempBasal else { return }

        if let finishTime = unfinalizedTempBasal.endTime,
            finishTime > date
        {
            unfinalizedTempBasal.cancel(at: date, insulinDelivered: pump.state.activeTempBasalDeliveryStatus.insulinDelivered)
        }
        
        mutateState { state in
            if canFinalize {
                state.finalizedDoses.append(unfinalizedTempBasal)
                state.unfinalizedTempBasal = nil
            } else {
                state.unfinalizedTempBasal = unfinalizedTempBasal
            }
        }
    }

    private func cancelActiveBoluses(at date: Date = Date()) {
        mutateState { state in
            for (bolusID, var unfinalizedBolus) in state.unfinalizedBoluses {
                if let finishTime = unfinalizedBolus.endTime,
                   finishTime > date
                {
                    log.info("Interrupted bolus: %{public}@", String(describing: unfinalizedBolus))

                    // the pump will send an annunciation providing the insulin delivered for a canceled bolus
                    unfinalizedBolus.cancel(at: date)
                    state.unfinalizedBoluses[bolusID] = unfinalizedBolus
                }
            }
        }
    }

    private func createInsulinSuspendedDose(at date: Date = Date()) {
        mutateState { state in
            state.finalizedDoses.append(UnfinalizedDose(suspendStartTime: date, scheduledCertainty: .certain))
            state.suspendState = .suspended(date)
        }
    }

    private func createInsulinResumedDose(at date: Date = Date()) {
        mutateState { state in
            state.finalizedDoses.append(UnfinalizedDose(resumeStartTime: date, scheduledCertainty: .certain))
            state.suspendState = .resumed(date)
        }
    }
    
    public func resumeDelivery(completion: @escaping (Error?) -> Void) {
        let preflightResult = setStateWithResult({ state -> PreflightResult in
            if !pump.isConnected {
                logDelegateEvent("preflight failed. pump is not connected")
                return .failure(.connection(InsulinDeliveryPumpManagerError.commError(.disconnected)))
            }
            state.activeTransition = .resumingPump
            return .success
        })

        switch preflightResult {
        case .success:
            pump.startInsulinDelivery() { [weak self] result in
                switch result {
                case .success(_):
                    guard let self = self else {
                        completion(nil)
                        return
                    }
                    let now = self.now
                    self.createInsulinResumedDose(at: now)
                    self.mutateState { state in
                        state.activeTransition = nil
                    }
                    self.reportCachedDoses()
                    self.retractInsulinSuspensionReminderAlert()
                    completion(nil)
                case .failure(let error):
                    self?.mutateState { state in
                        state.activeTransition = nil
                    }

                    guard !error.wasCommandUnacknowledged else {
                        self?.pendingInsulinDeliveryCommand = PendingInsulinDeliveryCommand(type: .resumeInsulinDelivery)
                        completion(PumpManagerError.uncertainDelivery)
                        return
                    }

                    completion(PumpManagerError.communication(InsulinDeliveryPumpManagerError(error)))
                }
            }
        case .failure(let error):
            completion(error)
        }
    }
    
    public func getBatteryLevel() {
        pump.getBatteryLevel()
    }
    
    public var deviceInformation: DeviceInformation? {
        state.pumpState.deviceInformation
    }

    public var pumpConfiguration: PumpConfiguration {
        state.pumpConfiguration
    }

    func checkForPumpClockDrift() {
        logDelegateEvent()
        getPumpTime()
    }

    private func getPumpTime() {
        logDelegateEvent()
        pump.getTime(using: pumpTimeZone) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let pumpTime):
                self.logDelegateEvent("Got pump time \(pumpTime) for time zone \(self.pumpTimeZone)")
                self.recordPumpTime(pumpTime, in: self.pumpTimeZone)
                if abs(pumpTime.timeIntervalSince(self.now)) > InsulinDeliveryPumpManager.maxAllowedPumpClockDrift {
                    self.logDelegateEvent("Pump clock drift detected. Should synchronize pump time: \(self.canSynchronizePumpTime)")
                    if self.canSynchronizePumpTime {
                        self.setPumpTime(using: self.pumpTimeZone) { _ in }
                    }
                }
            case .failure(let error):
                self.logDelegateEvent("Error getting pump time: \(error)")
            }
        }
    }

    public func setPumpTime(_ newPumpTime: Date = Date(), using timeZone: TimeZone, completion: @escaping (Error?) -> Void) {
        logDelegateEvent()
        pump.setTime(newPumpTime, using: timeZone) { [weak self] result in
            self?.logDelegateEvent("Result from trying to set the pump time: \(result)")
            switch result {
            case .success():
                guard let self = self else { return }
                self.recordPumpTime(newPumpTime, in: timeZone)
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }

    private func recordPumpTime(_ pumpTime: Date, in timeZone: TimeZone) {
        if timeZone != pumpTimeZone {
            reportPumpTimeZoneSync(fromTimeZone: pumpTimeZone, toTimeZone: timeZone)
        }
        mutateState { state in
            state.timeZone = timeZone
            state.lastPumpTime = pumpTime
        }
    }

    public var detectedSystemTimeOffset: TimeInterval {
        pumpManagerDelegate?.detectedSystemTimeOffset ?? 0
    }

    public var automaticDosingEnabled: Bool {
        pumpManagerDelegate?.automaticDosingEnabled ?? false
    }

    public var canSynchronizePumpTime: Bool {
        detectedSystemTimeOffset == 0
    }

    public var isClockOffset: Bool {
        let now = dateGenerator()
        return TimeZone.current.secondsFromGMT(for: now) != pumpTimeZone.secondsFromGMT(for: now)
    }

    func checkForTimeOffsetChange() {
        logDelegateEvent()
        isAlertActive(timeZoneChangedAlert) { [weak self] isAlertActive in
            guard let self = self else { return }
            if !isAlertActive && self.isClockOffset {
                self.issueTimeZoneChangedAlert()
            } else if isAlertActive && !self.isClockOffset {
                self.retractTimeZoneChangedAlert()
            }
        }
    }

    public func syncBasalRateSchedule(items scheduleItems: [RepeatingScheduleValue<Double>], completion: @escaping (Result<BasalRateSchedule, Error>) -> Void) {
        setBasalSchedule(dailyItems: scheduleItems) { [weak self] error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(BasalRateSchedule(dailyItems: scheduleItems, timeZone: self?.pumpTimeZone)!))
            }
        }
    }
    
    public func reportUpdatedBasalRateSchedule(_ basalRateSchedule: BasalRateSchedule) {
        pumpDelegate.notify { delegate in
            delegate?.pumpManager(self, didRequestBasalRateScheduleChange: basalRateSchedule) { [weak self] error in
                guard let self = self else { return }
                if error == nil {
                    self.mutateState { state in
                        state.basalRateSchedule = basalRateSchedule
                    }
                }
            }
        }
    }

    public func syncDeliveryLimits(limits deliveryLimits: DeliveryLimits, completion: @escaping (Result<DeliveryLimits, Error>) -> Void) {
        guard let maxBolus = deliveryLimits.maximumBolus else {
            completion(.success(deliveryLimits))
            return
        }

        updateMaxBolus(maxBolus) { result in
            switch result {
            case .success():
                completion(.success(deliveryLimits))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func reportPumpAlarm(_ alarmType: PumpAlarmType, at date: Date = Date()) {
        let title = alarmType.title ??  NSLocalizedString("Unknown", comment: "Pump Event title for unknown event")
        let rawData = "Pump \(title) at \(ISO8601DateFormatter().string(from: date))".data(using: .utf8)!
        let alarmEvent = NewPumpEvent(date: date, dose: nil, raw: rawData, title: title, type: .alarm, alarmType: alarmType)
        reportCachedDoses(withAdditionalEvents: [alarmEvent]) { _ in }
    }
    
    private func reportPumpAlarmCleared(at date: Date = Date()) {
        let title =  NSLocalizedString("Alarm Cleared", comment: "Pump Event title for alarm cleared")
        let rawData = "Pump \(title) at \(ISO8601DateFormatter().string(from: date))".data(using: .utf8)!
        let alarmClearedEvent = NewPumpEvent(date: date, dose: nil, raw: rawData, title: title, type: .alarmClear)
        reportCachedDoses(withAdditionalEvents: [alarmClearedEvent]) { _ in }
    }
    
    private func reportPumpTimeZoneSync(fromTimeZone: TimeZone, toTimeZone: TimeZone, at date: Date = Date()) {
        let title =  NSLocalizedString("Time Zone Sync", comment: "Pump Event title for time zone sync")
        let rawData = "Pump \(title) at \(ISO8601DateFormatter().string(from: date))".data(using: .utf8)!
        let timeZoneSyncEvent = NewPumpEvent(date: date, dose: nil, raw: rawData, title: title, type: .timeZoneSync(fromSecondsFromGMT: fromTimeZone.secondsFromGMT(), toSecondsFromGMT: toTimeZone.secondsFromGMT()))
        reportCachedDoses(withAdditionalEvents: [timeZoneSyncEvent]) { _ in }
    }
    
    public let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()

    public var pumpManagerDelegate: PumpManagerDelegate? {
        get {
            return pumpDelegate.delegate
        }
        set {
            pumpDelegate.delegate = newValue
            // when the delegate is set, look-up annunciations and update status highlight as needed
            maybeUpdateStatusHighlight()
        }
    }
    
    public var delegateQueue: DispatchQueue! {
        get {
            return pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
        }
    }
    
    // Primarily used for testing
    private let dateGenerator: () -> Date
    private var now: Date { dateGenerator() }
        
    public convenience required init?(rawState: PumpManager.RawStateValue) {
        guard let state = InsulinDeliveryPumpManagerState(rawValue: rawState) else
        {
            return nil
        }

        self.init(state: state)
    }
    
    public init(state: InsulinDeliveryPumpManagerState,
                pump: InsulinDeliveryPumpComms? = nil,
                dateGenerator: @escaping () -> Date = Date.init)
    {
        self.lockedState = Locked(state)
        self.pump = pump ?? InsulinDeliveryPump(state: state.pumpState)
        self.dateGenerator = dateGenerator
        self.pump.delegate = self
        self.pump.loggingDelegate = self
        self.pump.pumpDelegate = self
        scheduleSignalLossCheckTimer()
        
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            self.maybeUpdateStatusHighlight()
        }
    }

    public convenience required init(state: InsulinDeliveryPumpManagerState, dateGenerator: @escaping () -> Date = Date.init) {
        self.init(state: state, pump: nil, dateGenerator: dateGenerator)
    }
    
    open var rawState: PumpManager.RawStateValue {
        return state.rawValue
    }
    
    private func device(for deviceInformation: DeviceInformation?) -> HKDevice {
        return HKDevice(
            name: pluginIdentifier,
            manufacturer: "Tidepool",
            model: "Insulin Delivery Pump",
            hardwareVersion: deviceInformation?.hardwareRevision,
            firmwareVersion: deviceInformation?.firmwareRevision,
            softwareVersion: String(InsulinDeliveryLoopKitVersionNumber),
            localIdentifier: deviceInformation?.serialNumber,
            udiDeviceIdentifier: nil
        )
    }
    
    public var debugDescription: String {
        var lines = [
            "## InsulinDeliveryPumpManager",
        ]
        lines.append(contentsOf: [
            state.debugDescription,
            "",
        ])
        return lines.joined(separator: "\n")
    }
    
    public func prepareForDeactivation(_ completion: @escaping (Error?) -> Void) {
        logDelegateEvent()
        pump.prepareForDeactivation() { [weak self] result in
            switch result {
            case .success:
                guard let self = self else {
                    completion(nil)
                    return
                }
                self.tidepoolSecurity?.markAsDepedency(false)
                self.resetPendingItems()
                self.retractUnretractedAlerts() {
                    completion(nil)
                }
            case .failure(let error):
                completion(InsulinDeliveryPumpManagerError.commError(error))
            }
        }
    }
    
    func resetPendingItems() {
        self.pendingInsulinDeliveryCommand = nil
        self.annunciationsPendingConfirmation.removeAll()
    }
    
    private func retractUnretractedAlerts(_ completion: @escaping () -> Void) {
        pumpDelegate.notify { delegate in
            delegate?.lookupAllUnretracted(managerIdentifier: self.pluginIdentifier) { [weak self] result in
                switch result {
                case .success(let alerts):
                    self?.log.debug("Retracting alerts: %{public}@", alerts.map { ($0.alert.identifier.alertIdentifier, $0.issuedDate) }.debugDescription)
                    alerts.forEach {
                        // Call delegate directly, because no need to update state
                        delegate?.retractAlert(identifier: $0.alert.identifier)
                    }
                case .failure(let error):
                    self?.log.error("Failed to retract unretracted alerts: %{public}@", error.localizedDescription)
                }
                completion()
            }
        }
    }
}

//MARK: - Pump specific definitions
extension InsulinDeliveryPumpManager {
    // At times, the pump interface requires units to be in U/100 instead of U
    public static let unitAdjustment: Double = 100

    // Reservoir Capacity in IU
    public static let pumpReservoirCapacity: Double = 100

    // Amount below which reservoir value is known with accuracy, in IU.
    public static let reservoirAccuracyLimit: Double = 50

    // Allowed reservoir fill amounts
    public static let supportedReservoirFillVolumes: [Int] = Array(stride(from: 80, through: 100, by: 10))

    // Volume of insulin in one motor pulse
    public static let pulseSize: Double = 0.08

    // Number of pulses required to delivery one unit of insulin
    public static let pulsesPerUnit: Double = 1/pulseSize
    
    // Units per second
    public static let estimatedBolusDeliveryRate: Double = 2.5 / TimeInterval.minutes(1)

    // Supported bolus volumes in IU
    public static var supportedBolusVolumes: [Double] {
        var supportedBolusVolumes: [Double] = Array((20...2045).map { Double($0) / Double(100) })
        supportedBolusVolumes.append(contentsOf: Array((205...350).map { Double($0) / Double(10) }))
        return supportedBolusVolumes
    }
    public static func roundToSupportedBolusVolume(units: Double) -> Double {
        return supportedBolusVolumes.filter({$0 <= units}).max() ?? 0
    }

    // Supported maximum bolus volumes in IU
    public static let supportedMaximumBolusVolumes: [Double] = Array((10...350).map { Double($0) / Double(10) })
    
    // maximum allowed basal rate amount in IU/hr
    public static let maximumBasalRateAmount: Double = 25
    
    // Supported basal rates in IU/hr
    public static var supportedBasalRates: [Double] {
        var supportedBasalRates: [Double] = [0] // a rate of 0 IU/hr is supported
        // 0.01 IU step for rates between 0.1-4.99 IU/hr
        supportedBasalRates.append(contentsOf: Array((10...499).map { Double($0) / Double(100) }))
        // 0.1 IU step for rates between 5.0-25.0 IU/hr
        supportedBasalRates.append(contentsOf: Array((50...250).map { Double($0) / Double(10) }))
        
        return supportedBasalRates
    }

    public static let maximumBasalScheduleEntryCount: Int = 24

    public static let minimumBasalScheduleEntryDuration = TimeInterval.minutes(30)
    
    public static let lifespan = TimeInterval.days(10)

    public static let basalRateProfileTemplateNumber: UInt8 = 1
    
    public static let numberOfProfileTemplates: UInt8 = 1

    public static let primingAmount: Double = 3

    public static let maxAllowedPumpClockDrift: TimeInterval = .seconds(60)
    
    static let maxRequestSize: Int = 19
}

extension InsulinDeliveryPumpManager: IDPumpDelegate {
    public var supportedMaximumBasalRateAmount: Double { InsulinDeliveryPumpManager.maximumBasalRateAmount }
    public var basalRateProfileTemplateNumber: UInt8 { InsulinDeliveryPumpManager.basalRateProfileTemplateNumber }
    public var numberOfProfileTemplates: UInt8 { InsulinDeliveryPumpManager.numberOfProfileTemplates }
    public var estimatedBolusDeliveryRate: Double { InsulinDeliveryPumpManager.estimatedBolusDeliveryRate }
    public var reservoirAccuracyLimit: Double? { InsulinDeliveryPumpManager.reservoirAccuracyLimit }
    public var supportedReservoirFillVolumes: [Int] { InsulinDeliveryPumpManager.supportedReservoirFillVolumes }
    public var pulseSize: Double { InsulinDeliveryPumpManager.pulseSize }
    public var pulsesPerUnit: Double { InsulinDeliveryPumpManager.pulsesPerUnit }
    public var expectedLifespan: TimeInterval { InsulinDeliveryPumpManager.lifespan }
    public var maxAllowedPumpClockDrift: TimeInterval { InsulinDeliveryPumpManager.maxAllowedPumpClockDrift }
    public var isInReplacementWorkflow: Bool { state.replacementWorkflowState.isWorkflowIncomplete || !isOnboarded }
    public var basalProfile: [BasalSegment] { state.basalRateSchedule.basalProfile }
        
    public func pumpDidInitiateBolus(_ pump: IDPumpComms, bolusID: BolusID, insulinProgrammed: Double, startTime: Date) {
        // check if the bolus is already known
        guard state.unfinalizedBoluses[bolusID] == nil else { return }

        // Check if there is a matching pending bolus command first
        if case .bolus(let pendingInsulinProgrammed) = pendingInsulinDeliveryCommand?.type,
           pendingInsulinProgrammed == insulinProgrammed
        {
            logDelegateEvent("Resolved pending enact bolus command. bolus ID: \(bolusID), insulin programmed: \(insulinProgrammed), startTime: \(startTime)")
            mutateState { state in
                state.pendingInsulinDeliveryCommand = nil
                state.unfinalizedBoluses[bolusID] = UnfinalizedDose(decisionId: nil, bolusAmount: insulinProgrammed, startTime: startTime, scheduledCertainty: .certain)
            }
        } else {
            // boluses was initiated on pump and needs to be reported
            logDelegateEvent("Detected historical bolus initiated. bolus ID: \(bolusID), insulin programmed: \(insulinProgrammed), startTime: \(startTime)")
            mutateState { state in
                state.unfinalizedBoluses[bolusID] = UnfinalizedDose(decisionId: nil, bolusAmount: insulinProgrammed, startTime: startTime, scheduledCertainty: .certain)
            }
        }

        reportCachedDoses()
    }

    public func pumpDidDeliverBolus(_ pump: IDPumpComms, bolusID: BolusID, insulinProgrammed: Double, insulinDelivered: Double, startTime: Date, duration: TimeInterval) {
        logDelegateEvent("Bolus has completed delivery. bolus ID: \(bolusID), insulin programmed: \(insulinProgrammed), insulinDelivered: \(insulinDelivered), startTime: \(startTime), duration: \(duration)")

        // clear out any pending cancel bolus command
        if case .cancelBolus = pendingInsulinDeliveryCommand?.type {
            logDelegateEvent("Resolved pending cancel bolus command.")
            pendingInsulinDeliveryCommand = nil
        }

        // only known bolus are reported. if the bolus is unknown, it has already been reported
        guard var bolus = state.unfinalizedBoluses[bolusID] else {
            logDelegateEvent("Bolus not pending finalization.")
            return
        }

        mutateState { state in
            let adjustedDuration = bolus.startTime.addingTimeInterval(duration) <= now ? duration : now.timeIntervalSince(bolus.startTime) // the duration cannot make a bolus end date that is in the future
            if insulinProgrammed != insulinDelivered {
                bolus.cancel(at: bolus.startTime.addingTimeInterval(adjustedDuration), insulinDelivered: insulinDelivered)
            } else {
                bolus.duration = adjustedDuration
            }
            state.finalizedDoses.append(bolus)
            state.unfinalizedBoluses[bolusID] = nil
        }
        reportCachedDoses()
    }

    public func pumpTempBasalStarted(_ pump: IDPumpComms, at startTime: Date, rate: Double, duration: TimeInterval) {
        // check if this temp basal is from a pending command. If so, create that temp basal and clear the pending command
        if case .tempBasal(let programmedRate, let programmedDuration) = pendingInsulinDeliveryCommand?.type,
           programmedRate == rate,
           programmedDuration == duration
        {
            logDelegateEvent("Resolved pending enact temp basal command. rate: \(programmedRate), startTime: \(startTime), duration: \(programmedDuration)")
            mutateState { state in
                state.pendingInsulinDeliveryCommand = nil
                state.unfinalizedTempBasal = UnfinalizedDose(decisionId: nil, tempBasalRate: programmedRate, startTime: startTime, duration: programmedDuration, scheduledCertainty: .certain)
            }
            reportCachedDoses()
        }
    }

    public func pumpTempBasalEnded(_ pump: IDPumpComms, duration: TimeInterval) {
        // clear out any pending cancel temp basal command
        if case .cancelTempBasal = pendingInsulinDeliveryCommand?.type {
            logDelegateEvent("Resolved pending cancel temp basal command.")
            pendingInsulinDeliveryCommand = nil
        }
        
        guard var unfinalizedTempBasal = state.unfinalizedTempBasal else { return }

        logDelegateEvent("Temp basal completed. rate: \(unfinalizedTempBasal.rate), startTime: \(unfinalizedTempBasal.startTime), duration: \(duration), insulin delivered: \(unfinalizedTempBasal.units)")
        mutateState { state in
            let endTime = unfinalizedTempBasal.startTime.addingTimeInterval(duration)
            unfinalizedTempBasal.scheduledCertainty = .certain
            if !unfinalizedTempBasal.isFinished(at: endTime) {
                unfinalizedTempBasal.cancel(at: endTime)
            }
            state.finalizedDoses.append(unfinalizedTempBasal)
            state.unfinalizedTempBasal = nil
        }
        reportCachedDoses()
    }

    public func pumpDidSuspendInsulinDelivery(_ pump: IDPumpComms, suspendedAt: Date) {
        guard state.unfinalizedSuspendDetected == true else { return }
        logDelegateEvent("suspendedAt: \(suspendedAt)")

        // if there is a cached temp basal, this needs to be finalized first
        finalizeCachedTempBasal(at: suspendedAt)

        mutateState { state in
            state.finalizedDoses.append(UnfinalizedDose(suspendStartTime: suspendedAt, scheduledCertainty: .certain, automatic: state.unfinalizedSuspendDetected))
            state.unfinalizedSuspendDetected = nil
        }
        reportCachedDoses()
    }

    public func pumpDidDetectHistoricalAnnunciation(_ pump: IDPumpComms, annunciation: Annunciation, at date: Date?) {
        wasAnnunciationReported(annunciation) { [weak self] wasReported in
            guard let self = self,
                  !wasReported
            else { return }
            self.logDelegateEvent("Detected annunciation that was not reported: \(annunciation), at: \(String(describing: date))")
            
            if pump.isAwaitingConfiguration,
               annunciation.type.isInsulinDeliveryStopped
            {
                // this annunciation may require pump configuration. present to the user
                self.issueAnnunciation(annunciation)
            } else if let date = date {
                self.reportRetractedAnnunciation(annunciation, at: date)
            }
        }
    }

    public func pumpDidSync(_ pump: IDPumpComms, pendingCommandCheckCompleted: Bool = true, at date: Date = Date()) {
        logDelegateEvent("pendingCommandCheckCompleted: \(pendingCommandCheckCompleted)")

        if pendingCommandCheckCompleted {
            pendingInsulinDeliveryCommand = nil
            updateActiveTempBasalCertainty(.certain)
        }
        
        lastSync = date
        scheduleSignalLossCheckTimer()
    }

    public func pumpConnectionStatusChanged(_ pump: IDPumpComms) {
        let isPumpConnected = pump.isConnected
        logDelegateEvent("isPumpConnected: \(isPumpConnected)")
        if !isPumpConnected {
            updateActiveTempBasalCertainty(.uncertain)
        } else {
            confirmPendingAnnunciations()
        }
        mutateState { state in
            // communications will be disrupted
            state.activeTransition = nil
        }
        pumpObservers.forEach { observer in
            observer.pumpConnectionStatusChanged(connected: isPumpConnected)
        }
    }

    private func confirmPendingAnnunciations() {
        for annunciation in state.annunciationsPendingConfirmation {
            self.logSendEvent("Confirming pending annunciation \(annunciation)")
            pump.confirmAnnunciation(annunciation) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success():
                    self.mutateState { state in
                        state.annunciationsPendingConfirmation.remove(annunciation)
                    }
                case .failure(let error):
                    if error == .procedureNotApplicable {
                        self.logReceiveEvent("The pending annunciation \(annunciation) is no longer available to be confirm")
                        self.mutateState { state in
                            state.annunciationsPendingConfirmation.remove(annunciation)
                        }
                    } else {
                        self.logErrorEvent("Could not confirm pending annunciation: \(error)")
                    }
                }
            }
        }
    }

    private func updateActiveTempBasalCertainty(_ scheduledCertainty: UnfinalizedDose.ScheduledCertainty) {
        guard let unfinalizedTempBasal = state.unfinalizedTempBasal,
              unfinalizedTempBasal.scheduledCertainty != scheduledCertainty
        else { return }
        logDelegateEvent("scheduledCertainty: \(scheduledCertainty)")

        mutateState { state in
            state.unfinalizedTempBasal?.scheduledCertainty = scheduledCertainty
        }
        reportCachedDoses()
    }
    
    public func pump(_ pump: IDPumpComms,
                     didDiscoverPumpWithName peripheralName: String?,
                     identifier: UUID,
                     serialNumber: String?)
    {
        logDelegateEvent("name: \(String(describing: peripheralName)), identifier: \(identifier), serialNumber: \(String(describing: serialNumber))")
        pumpObservers.forEach { observer in
            observer.didDiscoverPump(name: peripheralName,
                                     identifier: identifier,
                                     serialNumber: serialNumber,
                                     remainingLifetime: self.state.previousPumpRemainingLifetime[serialNumber ?? ""])
        }
    }
    
    public func pumpDidCompleteAuthentication(_ pump: IDPumpComms, error: DeviceCommError?) {
        logDelegateEvent("error: \(String(describing: error))")
        pumpObservers.forEach { observer in
            observer.pumpDidCompleteAuthentication(error: error)
        }
    }
    
    public func pumpDidCompleteConfiguration(_ pump: IDPumpComms) {
        logDelegateEvent()
        pumpObservers.forEach { observer in
            observer.pumpDidCompleteConfiguration()
        }
    }
    
    public func pumpDidCompleteTherapyUpdate(_ pump: IDPumpComms) {
        logDelegateEvent()
        pumpObservers.forEach { observer in
            observer.pumpDidCompleteTherapyUpdate()
        }
    }
        
    public func pumpDidUpdateState(_ pump: IDPumpComms) {
        // check is the temp basal has completed (triggered by active basal rate changed)
        if var unfinalizedTempBasal = state.unfinalizedTempBasal,
           pump.state.activeTempBasalDeliveryStatus.progressState == .completed
        {
            unfinalizedTempBasal.cancel(at: now, insulinDelivered: pump.state.activeTempBasalDeliveryStatus.insulinDelivered)
            mutateState { state in
                state.finalizedDoses.append(unfinalizedTempBasal)
                state.unfinalizedTempBasal = nil
            }
            reportCachedDoses()
        }
        
        if didInsulinSuspendUnexpectedly(for: pump.state) {
            // check if there is a pending suspend
            if case .suspendInsulinDelivery = pendingInsulinDeliveryCommand?.type,
               let date = pendingInsulinDeliveryCommand?.date
            {
                cancelActiveDoses(at: date, canFinalizeDoses: true)
                createInsulinSuspendedDose(at: date)
                pendingInsulinDeliveryCommand = nil
                reportCachedDoses()
            } else {
                // otherwise it is due to an issue with the pump
                mutateState { state in
                    state.suspendState = nil
                    state.unfinalizedSuspendDetected = true
                }
            }
        } else if didInsulinResumeUnexpectedly(for: pump.state) {
            // this can only happen if a resume was requested from Tidepool Loop and the response was not received
            if case .resumeInsulinDelivery = pendingInsulinDeliveryCommand?.type,
               let date = pendingInsulinDeliveryCommand?.date
            {
                createInsulinResumedDose(at: date)
                pendingInsulinDeliveryCommand = nil
                reportCachedDoses()
            }
        }

        checkForLowReservoirCondition(newValue: pump.state.deviceInformation?.reservoirLevel, oldValue: state.pumpState.deviceInformation?.reservoirLevel)

        mutateState { state in
            state.pumpState = pump.state
        }

        pumpObservers.forEach { observer in
            observer.pumpDidUpdateState()
        }

        storeCurrentPumpRemainingLifetime()
    }

    private func didInsulinSuspendUnexpectedly(for pumpState: IDPumpState) -> Bool {
        // check if the pump was delivering insulin and is no longer delivering insulin
        // if ^ is true, check if the pump is known to be transitioning from a resumed state to a suspended state (i.e., in the act of suspending)
        // if ^ is false, then insulin delivery suspended unexpectedly
        guard state.pumpState.isDeliveringInsulin,
              !pumpState.isDeliveringInsulin,
              case .resumed = state.suspendState,
              state.activeTransition != .suspendingPump
        else { return false }
        return true
    }

    private func didInsulinResumeUnexpectedly(for pumpState: IDPumpState) -> Bool {
        // check if the pump was not delivering insulin and is now delivering insulin
        // if ^ is true, check if the pump is known to be transitioning from a suspended state to a resumed state (i.e., in the act of resuming)
        // if ^ is false, then insulin delivery resumed unexpectedly
        guard !state.pumpState.isDeliveringInsulin,
              pumpState.isDeliveringInsulin,
              case .suspended = state.suspendState,
              state.activeTransition != .resumingPump
        else { return false }
        return true
    }
    
    public func pump(_ pump: IDPumpComms, didReceiveAnnunciation annunciation: Annunciation) {
        logDelegateEvent("annunciation: \(annunciation)")
        
        if annunciation.type == .occlusionDetected {
            reportPumpAlarm(.occlusion)
        } else if annunciation.type == .reservoirLow {
            reportPumpAlarm(.lowInsulin)
        } else if annunciation.type == .reservoirEmpty {
            reportPumpAlarm(.noInsulin)
        } else if annunciation.type.isInsulinDeliveryStopped {
            reportPumpAlarm(.noDelivery)
        }
        
        switch annunciation.type {
        case .bolusCanceled where annunciation is BolusCanceledAnnunciation:
            handleReceivedBolusCanceledAnnunciation(pump, annunciation as! BolusCanceledAnnunciation)
        case .tempBasalCanceled:
            // W-36's are auto-confirmed, in favor of other signalizations (e.g. in the pump pill and status)
            autoConfirmAndReportAnnunciation(annunciation)
        case .primingIssue where state.replacementWorkflowState.isWorkflowIncomplete:
            autoConfirmAndReportAnnunciation(annunciation)
        case .reservoirIssue where state.replacementWorkflowState.isWorkflowIncomplete:
            pumpObservers.forEach { observer in
                observer.pumpEncounteredReservoirIssue()
            }
            autoConfirmAndReportAnnunciation(annunciation)
        case .reservoirLow, .endOfPumpLifetime:
            // These states are tracked and alerted on with configuration outside of the pump for now.
            autoConfirmAnnunciation(annunciation)
        default:
            issueAnnunciation(annunciation)
        }
    }

    private func handleReceivedBolusCanceledAnnunciation(_ pump: IDPumpComms, _ bolusCanceledAnnunciation: BolusCanceledAnnunciation) {
        // a bolus could be canceled for a number of reasons beside cancelBolus (reservoir removed, reservoir empty, insulin suspended, etc.)
        // the BolusCanceledAnnunication reports these canceled boluses
        defer {
            self.reportCachedDoses()
        }
        
        guard let bolusID = bolusCanceledAnnunciation.bolusDeliveryStatus.id else {
            // do not issue an annunciation without a corresponding bolus id
            logDelegateEvent("Bolus canceled annunciation is missing bolus ID.")
            reportRetractedAnnunciation(bolusCanceledAnnunciation)
            return
        }
        
        guard var unfinalizedBolus = state.unfinalizedBoluses[bolusID] else {
            log.debug("Could not identify unfinalized bolus id that was canceled")
            // issue the annunciation since this bolus would not be cancelled by the user (if it was canceled by the user we would be able to identify it)
            issueAnnunciation(bolusCanceledAnnunciation)
            return
        }

        var autoConfirm = false
        self.mutateState { state in
            // WARNING: don't be tempted to unwrap `state.unfinalizedBoluses[bolusID]` and assign it to a local
            // variable (e.g. `if var bolus = state.unfinalizedBoluses[bolusID] ...`) here.
            // It is a struct, which would be copied locally and the `cancel` below would not actually modify
            // the unfinalized bolus in `state`.
            if unfinalizedBolus.wasCanceled {
                // Bolus was canceled by user. If so, auto-confirm the annunciation.
                autoConfirm = true
                unfinalizedBolus.units = bolusCanceledAnnunciation.bolusDeliveryStatus.insulinDelivered
            } else {
                unfinalizedBolus.cancel(at: self.now, insulinDelivered: bolusCanceledAnnunciation.bolusDeliveryStatus.insulinDelivered)
            }

            state.unfinalizedBoluses[bolusID] = unfinalizedBolus
        }
        
        if autoConfirm {
            // Auto-confirm the `bolusCanceled` annunciation (W-38)
            logDelegateEvent("Auto-confirming bolusCanceled, id \(bolusID)")
            autoConfirmAndReportAnnunciation(bolusCanceledAnnunciation)
        } else {
            issueAnnunciation(bolusCanceledAnnunciation)
        }
    }

    private func issueAnnunciation(_ annunciation: Annunciation) {
        wasAnnunciationIssued(annunciation) { [weak self] wasIssued in
            guard let self = self,
                  !wasIssued
            else { return }

            self.issueAlert(Alert(with: annunciation, managerIdentifier: self.pluginIdentifier))
            self.replacementWorkflowState.doesPumpNeedsReplacement = annunciation.type.doesPumpNeedsReplacement
        }
    }

    private func wasAnnunciationIssued(_ annunciation: Annunciation, completion: @escaping (Bool) -> Void) {
        pumpDelegate.notify { [weak self] delegate in
            guard let self = self else { return }
            delegate?.lookupAllUnacknowledgedUnretracted(managerIdentifier: self.pluginIdentifier) { [weak self] result in
                switch result {
                case .failure(let error):
                    self?.log.error("Failed to determine if annunciation was already issued: %{public}@", error.localizedDescription)
                    completion(false)
                case .success(let alerts):
                    completion(alerts.contains(where: { $0.alert.identifier.alertIdentifier == annunciation.alertIdentifier }))
                }
            }
        }
    }

    private func wasAnnunciationReported(_ annunciation: Annunciation, completion: @escaping (Bool) -> Void) {
        pumpDelegate.notify() { [weak self] delegate in
            guard let self = self else { return }
            let identifier = Alert.Identifier(managerIdentifier: self.pluginIdentifier, alertIdentifier: annunciation.alertIdentifier)
            delegate?.doesIssuedAlertExist(identifier: identifier) { [weak self] result in
                switch result {
                case .success(let wasAnnunciationReported):
                    completion(wasAnnunciationReported)
                case .failure(let error):
                    self?.logDelegateEvent("Cannot determine if annunciation \(annunciation) already exists. Error: \(error)")
                    completion(false)
                }
            }
        }
    }

    private func getLatestActiveAlertForAnnunciationType(_ annunciationType: AnnunciationType, completion: @escaping (PersistedAlert?) -> Void) {
        pumpDelegate.notify() { delegate in
            delegate?.lookupAllUnretracted(managerIdentifier: self.pluginIdentifier) { [weak self] result in
                switch result {
                case .success(let alerts):
                    completion(alerts
                        .sorted(by: { $0.issuedDate > $1.issuedDate } )
                        .filter {
                            guard let activeAnnunciationType = try? $0.alert.annunciationType() else { return false }
                            return activeAnnunciationType == annunciationType
                        }
                        .first)
                case .failure(let error):
                    self?.log.error("Failed to determine if an alert with matching annunciation type is still active: %{public}@", error.localizedDescription)
                    completion(nil)
                }
            }
        }
    }

    private func isAlertActive(_ alert: Alert, completion: @escaping (Bool) -> Void) {
        pumpDelegate.notify() { delegate in
            delegate?.lookupAllUnretracted(managerIdentifier: alert.identifier.managerIdentifier) { [weak self] result in
                switch result {
                case .success(let alerts):
                    completion(alerts.contains(where: { $0.alert.identifier == alert.identifier }))
                case .failure(let error):
                    self?.log.error("Failed to determine if the alert is still active: %{public}@", error.localizedDescription)
                    completion(false)
                }
            }
        }
    }

    private func reportRetractedAnnunciation(_ annunciation: Annunciation, at date: Date = Date()) {
        logDelegateEvent("Reporting retracted annunciation \(annunciation)")
        pumpDelegate.notify() { [weak self] delegate in
            guard let self = self else { return }
            let alert = Alert(with: annunciation, managerIdentifier: self.pluginIdentifier)
            delegate?.recordRetractedAlert(alert, at: date)
        }
    }

    private func autoConfirmAndReportAnnunciation(_ annunciation: Annunciation, at date: Date = Date()) {
        autoConfirmAnnunciation(annunciation)
        reportRetractedAnnunciation(annunciation, at: date)
    }

    private func autoConfirmAnnunciation(_ annunciation: Annunciation) {
        logDelegateEvent("Auto-confirming \(annunciation)")
        pump.confirmAnnunciation(annunciation) { [weak self] result in
            switch result {
            case .success:
                self?.logDelegateEvent("\(annunciation) was auto-confirmed")
            case .failure(let error):
                self?.logDelegateEvent("Error auto-confirming \(annunciation). \(error)")
            }
        }
    }
}

// MARK: - Alert Presenter

extension InsulinDeliveryPumpManager: AlertIssuer {
    public func issueAlert(_ alert: Alert) {
        logDelegateEvent("issuing \(alert.identifier) \(alert.backgroundContent.title) with trigger \(alert.trigger)")
        pumpDelegate.notify { [weak self] delegate in
            delegate?.issueAlert(alert)
            self?.maybeUpdateStatusHighlight()
        }
    }
    
    public func retractAlert(identifier: Alert.Identifier) {
        logDelegateEvent("retracting \(identifier)")
        pumpDelegate.notify { [weak self] delegate in
            delegate?.retractAlert(identifier: identifier)
            self?.maybeUpdateStatusHighlight()
        }
    }

    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        logDelegateResponseEvent("acknowledging \(alertIdentifier)")

        if alertIdentifier == insulinSuspensionReminderAlertIdentifier.alertIdentifier {
            if isSuspended {
                // subsequent reminder are delayed 15 mins
                issueInsulinSuspensionReminderAlert(reminderDelay: .minutes(15))
            }
            completion(nil)
            return
        }

        if PumpExpiresSoonAnnunciation.alertIdentifierComponents(alertIdentifier)?.type == PumpExpiresSoonAnnunciation.type {
            // Schedule any repeating expiration reminder alerts
            scheduleRepeatedPumpExpirationReminderAlert()
            completion(nil)
            return
        }

        guard let annunciation = GeneralAnnunciation(alertIdentifier) else {
            logDelegateResponseEvent("Failed to acknowledge \(alertIdentifier)")
            completion(InsulinDeliveryPumpManagerError.invalidAlert)
            return
        }

        pump.confirmAnnunciation(annunciation) { [weak self] result in
            switch result {
            case .success:
                self?.logDelegateResponseEvent("Annunciation \(annunciation) was acknowledge")
                completion(nil)
            case .failure(let error):
                self?.logDelegateResponseEvent("Acknowledging \(annunciation) failed: \(error)")
                self?.mutateState { state in
                    state.annunciationsPendingConfirmation.insert(annunciation)
                }
                completion(InsulinDeliveryPumpCommError.acknowledgingAnnunciationFailed)
            }
        }
    }

    func issueInsulinSuspensionReminderAlert(reminderDelay: TimeInterval?) {
        guard let reminderDelay = reminderDelay else { return }
        issueAlert(insulinSuspensionReminderAlert(reminderDelay: reminderDelay))
    }

    private func retractInsulinSuspensionReminderAlert() {
        retractAlert(identifier: insulinSuspensionReminderAlertIdentifier)
    }

    var insulinSuspensionReminderAlertIdentifier: Alert.Identifier {
        Alert.Identifier(managerIdentifier: pluginIdentifier, alertIdentifier: "insulinSuspensionReminder")
    }

    private func insulinSuspensionReminderAlert(reminderDelay: TimeInterval) -> Alert {
        let identifier = insulinSuspensionReminderAlertIdentifier
        let alertContentForeground = Alert.Content(title: LocalizedString("Delivery Suspension Reminder", comment: "Title of insulin suspension reminder alert"),
                                                   body: LocalizedString("The insulin suspension period has ended. You can resume delivery from the banner on the home screen or from your pump settings screen.", comment: "The body of the insulin suspension reminder alert (in app)"),
                                                   acknowledgeActionButtonLabel: LocalizedString("OK", comment: "Acknowledgement button title for insulin suspension reminder  alert"))
        let alertContentBackground = Alert.Content(title: LocalizedString("Delivery Suspension Reminder", comment: "Title of insulin suspension reminder alert"),
                                                   body: LocalizedString("The insulin suspension period has ended. Return to App and resume.", comment: "The body of the insulin suspension reminder alert (notification)"),
                                                   acknowledgeActionButtonLabel: LocalizedString("OK", comment: "Acknowledgement button title for insulin suspension reminder  alert"))
        return Alert(identifier: identifier,
                     foregroundContent: alertContentForeground,
                     backgroundContent: alertContentBackground,
                     trigger: .delayed(interval: reminderDelay),
                     interruptionLevel: .timeSensitive)
    }
    
    private func scheduleRepeatedPumpExpirationReminderAlert() {
        let trigger: Alert.Trigger
        switch expiryReminderRepeat {
        case .dayBefore:
            guard let expirationDate = self.pump.deviceInformation?.estimatedExpirationDate else {
                log.error("Could not issue pump expiration reminder")
                return
            }
            let dayBeforeExpiration = Calendar.current.date(byAdding: .day, value: -1, to: expirationDate) ?? expirationDate.addingTimeInterval(.days(-1))
            // Odd corner case: if the user happens to acknowledge the PumpExpiresSoonAnnunciation alert
            // after the day before expiration time, set the alert reminder to be as soon as possible (adding a minute
            // instead of "immediate" to make it a little more user-friendly, instead of just getting another alert
            // right away before displaying reminder.)
            let interval = max(.minutes(1), dayBeforeExpiration.timeIntervalSince(now))
            trigger = .delayed(interval: interval)
        case .daily:
            trigger = .repeating(repeatInterval: .days(1))
        case .never:
            return
        }
        issueAlert(pumpExpirationReminderAlert(trigger: trigger))
    }

    private func retractPumpExpirationReminderAlert() {
        retractAlert(identifier: pumpExpirationReminderAlertIdentifier)
    }

    var pumpExpirationReminderAlertIdentifier: Alert.Identifier {
        Alert.Identifier(managerIdentifier: pluginIdentifier, alertIdentifier: "pumpExpirationReminder")
    }

    private func pumpExpirationReminderAlert(trigger: Alert.Trigger) -> Alert {
        let identifier = pumpExpirationReminderAlertIdentifier
        let alertContent = Alert.Content(title: LocalizedString("Pump Expiration Reminder", comment: "Title of pump expiration reminder alert"),
                                         body: LocalizedString("Be prepared to replace the pump soon.", comment: "The body of the pump expiration reminder alert"),
                                         acknowledgeActionButtonLabel: LocalizedString("OK", comment: "Acknowledgement button title for pump expiration reminder  alert"))
        return Alert(identifier: identifier,
                     foregroundContent: alertContent,
                     backgroundContent: alertContent,
                     trigger: trigger,
                     interruptionLevel: .active)
    }

    func issueTimeZoneChangedAlert() {
        issueAlert(timeZoneChangedAlert)
    }

    private func retractTimeZoneChangedAlert() {
        retractAlert(identifier: timeZoneChangedAlertIdentifier)
    }

    var timeZoneChangedAlertIdentifier: Alert.Identifier {
        Alert.Identifier(managerIdentifier: pluginIdentifier, alertIdentifier: "timeZoneChanged")
    }

    private var timeZoneChangedAlert: Alert {
        let identifier = timeZoneChangedAlertIdentifier
        let alertContent = Alert.Content(title: LocalizedString("Time Change Detected", comment: "Alert content title for an alert when the time zone of the pump does not match the time zone of the app"),
                                         body: LocalizedString("The time on your pump is different from the current time. You can review the pump time and sync to current time in the pump settings.", comment: "Alert content body for an alert when the time zone of the pump does not match the time zone of the app"),
                                         acknowledgeActionButtonLabel: LocalizedString("OK", comment: "Acknowledgement button title for time zone changed alert"))
        return Alert(identifier: identifier,
                     foregroundContent: alertContent,
                     backgroundContent: alertContent,
                     trigger: .immediate,
                     interruptionLevel: .timeSensitive)
    }
}

// MARK: - Alert Sounds

extension InsulinDeliveryPumpManager: AlertSoundVendor {
    public func getSoundBaseURL() -> URL? {
        return Bundle(for: type(of: self)).bundleURL
    }
    
    public func getSounds() -> [Alert.Sound] {
        // Remove duplicates
        let sounds = AlertSound.allCases.map { $0.filename }.compactMap { $0 }
        let set = Set(sounds)
        return Array(set).map { .sound(name: $0) }
    }
}

// MARK: - Settings Convenience

extension InsulinDeliveryPumpManager {

    public var isSuspended: Bool {
        state.isSuspended
    }

    public var suspendedAt: Date? {
        state.suspendedAt
    }

    public var expirationReminderTimeBeforeExpiration: TimeInterval {
        state.expirationReminderTimeBeforeExpiration
    }

    public var allowedExpiryWarningDurations: [TimeInterval] {
        pumpConfiguration.allowedExpiryWarningDurations
    }

    public func updateExpiryWarningDuration(_ expiryWarningDuration: TimeInterval) {
        guard self.expirationReminderTimeBeforeExpiration != expiryWarningDuration else {
            return
        }

        mutateState { state in
            state.expirationReminderTimeBeforeExpiration = expiryWarningDuration
        }
    }

    public var expiryReminderRepeat: InsulinDeliveryPumpManagerState.NotificationSettingsState.ExpiryReminderRepeat {
        get {
            return state.notificationSettingsState.expiryReminderRepeat
        }
        set {
            mutateState { state in
                state.notificationSettingsState.expiryReminderRepeat = newValue
            }
        }
    }
    
    public var lowReservoirWarningThresholdInUnits: Int {
        state.lowReservoirWarningThresholdInUnits
    }

    public var allowedLowReservoirWarningThresholdsInUnits: [Int] {
        pumpConfiguration.allowedLowReservoirWarningThresholdsInUnits
    }

    public func updateLowReservoirWarningThreshold(_ lowReservoirWarningThresholdInUnits: Int) {
        guard self.lowReservoirWarningThresholdInUnits != lowReservoirWarningThresholdInUnits else {
            return
        }
        
        self.mutateState { state in
            state.lowReservoirWarningThresholdInUnits = lowReservoirWarningThresholdInUnits
        }
    }

    private func updateMaxBolus(_ maxBolus: LoopQuantity, completion: @escaping ProcedureResultCompletion) {
        let maxBolusInUnits = maxBolus.doubleValue(for: .internationalUnit)
        guard pumpConfiguration.bolusMaximum != maxBolusInUnits
        else {
            completion(.success)
            return
        }

        var updatedPumpConfiguration = pumpConfiguration
        updatedPumpConfiguration.bolusMaximum = maxBolusInUnits
        updatePumpConfiguration(updatedPumpConfiguration, completion: completion)
    }

    private func updatePumpConfiguration(_ pumpConfiguration: PumpConfiguration, completion: @escaping ProcedureResultCompletion) {
        logDelegateEvent("Pump configuration is managed by the pump manager.")
        mutateState { state in
            state.pumpConfiguration = pumpConfiguration
        }
        pumpDidCompleteConfiguration(pump)
    }
}

extension InsulinDeliveryPumpManager: DeviceCommLoggingDelegate {
    public func logConnectionEvent(function: StaticString = #function, _ message: String = "") {
        logEvent(function: function, type: .connection, message: message)
    }

    public func logSendEvent(function: StaticString = #function, _ message: String = "") {
        logEvent(function: function, type: .send, message: message)
    }

    public func logReceiveEvent(function: StaticString = #function, _ message: String = "") {
        logEvent(function: function, type: .receive, message: message)
    }

    public func logErrorEvent(function: StaticString = #function, _ message: String = "") {
        logEvent(function: function, type: .error, message: message)
    }

    public func logDelegateEvent(function: StaticString = #function, _ message: String = "") {
        logEvent(function: function, type: .delegate, message: message)
    }

    public func logDelegateResponseEvent(function: StaticString = #function, _ message: String = "") {
        logEvent(function: function, type: .delegateResponse, message: message)
    }

    private func logEvent(function: StaticString,
                          type: DeviceLogEntryType,
                          message: String) {
        switch type {
        case .error:
            log.error("%{public}@: %{public}@", function.description, message)
        default:
            log.info("%{public}@: %{public}@", function.description, message)
        }
        pumpDelegate.notify { delegate in
            delegate?.deviceManager(self,
                                    logEventForDeviceIdentifier: (self.deviceInformation?.serialNumber ?? "NoSerialNumber"),
                                    type: type, message: "\(function): \(message)", completion: nil)
        }
    }
}

extension AnnunciationType {
    var statusBadge: InsulinDeliveryPumpStatusBadge? {
        switch self {
        case .batteryLow:
            return .lowBattery
        default:
            return nil
        }
    }
}

extension BolusActivationType {
    var idsBolusActivationType: IDBolusActivationType {
        switch self {
        case .manualNoRecommendation: return .manualBolus
        case .manualRecommendationAccepted: return .recommendedBolus
        case .manualRecommendationChanged: return .manuallyChangedRecommendedBolus
        case .automatic: return .aidController
        case .none: return .undetermined
        }
    }
}

// Mark: - Security

extension InsulinDeliveryPumpManager {
    public func initializationComplete(for pluggables: [Pluggable]) {
        tidepoolSecurity = pluggables.first(where: { $0 as? TidepoolSecurity != nil }) as? TidepoolSecurity
        tidepoolSecurity?.markAsDepedency(true)
    }
}

fileprivate extension PumpAlarmType {
    var title: String? {
        switch self {
        case .lowInsulin:
            return NSLocalizedString("Low Insulin", comment: "Pump Event title for low insulin event")
        case .noDelivery:
            return NSLocalizedString("No Delivery", comment: "Pump Event title for no delivery event")
        case .noInsulin:
            return NSLocalizedString("No Insulin", comment: "Pump Event title for no insulin event")
        case .occlusion:
            return NSLocalizedString("Occlusion", comment: "Pump Event title for occlusion event")
        default:
            return nil
        }
    }
}
