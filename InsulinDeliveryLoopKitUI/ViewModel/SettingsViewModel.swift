//
//  SettingsViewModel.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2025-04-29.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopAlgorithm
import LoopKit
import InsulinDeliveryLoopKit
import InsulinDeliveryServiceKit

typealias SaveNotificationSettingCompletion = (_ selectedSettings: NotificationSetting, _ completion: @escaping (_ error: Error?) -> Void) -> Void

class SettingsViewModel: ObservableObject {
    let pumpManager: InsulinDeliveryPumpManager

    var pumpManagerState: InsulinDeliveryPumpManagerState {
        pumpManager.state
    }
    
    weak var navigator: IDSViewNavigator?
    
    @Published var deviceInformation: DeviceInformation?

    var pumpManagerTitle: String {
        pumpManager.localizedTitle
    }

    lazy var insulinQuantityFormatter: QuantityFormatter = {
        return QuantityFormatter(for: .internationalUnit)
    }()
    
    let completionHandler: () -> Void
    
    var deletePumpManagerHandler: ((_ completion: @escaping (Error?) -> Void) -> Void)? = nil

    @Published var expiryWarningDuration: TimeInterval

    typealias ExpiryReminderRepeat = InsulinDeliveryPumpManagerState.NotificationSettingsState.ExpiryReminderRepeat
    typealias ExpirySaveCompletion = (_ duration: TimeInterval, _ expiryReminderRepeat: ExpiryReminderRepeat) -> Void

    var expiryReminderRepeat: ExpiryReminderRepeat {
        didSet {
            pumpManager.expiryReminderRepeat = expiryReminderRepeat
        }
    }
    
    var allowedExpiryWarningDurations: [TimeInterval] {
        pumpManager.allowedExpiryWarningDurations
    }

    func saveExpiryWarningDuration(duration: TimeInterval, expiryReminderRepeat: ExpiryReminderRepeat) {
        pumpManager.updateExpiryWarningDuration(duration)
        self.expiryWarningDuration = duration
        self.expiryReminderRepeat = expiryReminderRepeat
    }

    @Published var lowReservoirWarningThresholdInUnits: Int

    var allowedLowReservoirWarningThresholdsInUnits: [Int] {
        pumpManager.allowedLowReservoirWarningThresholdsInUnits
    }

    func saveLowReservoirWarningThreshold(threshold: Int) {
        pumpManager.updateLowReservoirWarningThreshold(threshold)
        self.lowReservoirWarningThresholdInUnits = threshold
    }
    
    @Published var descriptiveTextTitle: String?
    @Published var descriptiveText: String?
    
    var suspendReminderDelayOptions: [TimeInterval] {
        [.minutes(30), .hours(1), .hours(1.5), .hours(2)]
    }

    lazy var suspendReminderTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    var isInsulinDeliverySuspended: Bool {
        suspendedAt != nil
    }

    var isInsulinDeliverySuspendedByUser: Bool {
        isInsulinDeliverySuspended && !wasInsulinDeliverySuspensionCausedByEMWR
    }
    
    var wasInsulinDeliverySuspensionCausedByEMWR: Bool {
        isInsulinDeliverySuspended && pumpManager.state.replacementWorkflowState.doesPumpNeedsReplacement
    }
    
    var insulinDeliveryDisabled: Bool {
        transitioningSuspendResumeInsulinDelivery || transitioningSuspendInsulinDelivery || !canSuspendResumeInsulinDelivery || pumpManager.status.deliveryIsUncertain == true
    }

    @Published var transitioningSuspendResumeInsulinDelivery: Bool

    @Published var suspendedAt: Date?

    var suspendedAtString: String? {
        guard let suspendedAt = suspendedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: suspendedAt)
    }
    
    enum SuspendResumeInsulinDeliveryStatus {
        case suspended
        case suspending
        case resumed
        case resuming
        
        var localizedLabel: String {
            switch self {
            case .suspended:
                return LocalizedString("Tap to Resume Insulin Delivery", comment: "Label when the user can resume insulin delivery")
            case .suspending:
                return LocalizedString("Suspending Insulin Delivery", comment: "Label when suspending insulin delivery")
            case .resumed:
                return LocalizedString("Suspend Insulin Delivery", comment: "Label when the user can suspend insulin delivery")
            case .resuming:
                return LocalizedString("Resuming Insulin Delivery", comment: "Label when resuming insulin delivery")
            }
        }
        
        var showPauseIcon: Bool {
            self == .suspended || self == .resuming
        }
    }

    var suspendResumeInsulinDeliveryStatus: SuspendResumeInsulinDeliveryStatus {
        if isInsulinDeliverySuspendedByUser {
            if transitioningSuspendResumeInsulinDelivery {
                return .resuming
            } else {
                return .suspended
            }
        } else {
            if transitioningSuspendResumeInsulinDelivery {
                return .suspending
            } else {
                return .resumed
            }
        }
    }

    func suspendInsulinDelivery(reminderDelay: TimeInterval, completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.transitioningSuspendResumeInsulinDelivery = true
            self?.pumpManager.suspendDelivery(reminderDelay: reminderDelay) { error in
                DispatchQueue.main.async {
                    if error == nil {
                        self?.suspendedAt = Date()
                    }
                    self?.transitioningSuspendResumeInsulinDelivery = false
                    completion(error)
                }
            }
        }
    }

    func resumeInsulinDelivery(completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.transitioningSuspendResumeInsulinDelivery = true
            self?.pumpManager.resumeDelivery() { error in
                DispatchQueue.main.async {
                    if error == nil {
                        self?.suspendedAt = nil
                    }
                    self?.transitioningSuspendResumeInsulinDelivery = false
                    completion(error)
                }
            }
        }
    }

    var isClockOffset: Bool {
        return pumpManager.isClockOffset
    }

    var timeZone: TimeZone {
        return pumpManager.status.timeZone
    }

    // "Sub"-viewModels
    let expirationProgressViewModel: ExpirationProgressViewModel
    let insulinStatusViewModel: InsulinStatusViewModel

    @Published var detectedSystemTimeOffset: TimeInterval

    @Published var canSynchronizePumpTime: Bool

    @Published var automaticDosingEnabled: Bool
    
    @Published var doesPumpNeedsReplacement: Bool

    init(pumpManager: InsulinDeliveryPumpManager,
         navigator: IDSViewNavigator,
         completionHandler: @escaping () -> Void)
    {
        self.pumpManager = pumpManager
        self.expirationProgressViewModel = pumpManager.expirationProgressViewModel
        self.insulinStatusViewModel = InsulinStatusViewModel(statePublisher: pumpManager)
        self.navigator = navigator
        self.deviceInformation = pumpManager.deviceInformation
        self.completionHandler = completionHandler
        self.expiryWarningDuration = pumpManager.expirationReminderTimeBeforeExpiration
        self.expiryReminderRepeat = pumpManager.expiryReminderRepeat
        self.lowReservoirWarningThresholdInUnits = pumpManager.lowReservoirWarningThresholdInUnits
        self.suspendedAt = pumpManager.suspendedAt
        self.transitioningSuspendResumeInsulinDelivery = false
        self.transitioningSuspendInsulinDelivery = false
        self.detectedSystemTimeOffset = pumpManager.detectedSystemTimeOffset
        self.canSynchronizePumpTime = pumpManager.canSynchronizePumpTime
        self.automaticDosingEnabled = pumpManager.automaticDosingEnabled
        self.doesPumpNeedsReplacement = pumpManager.state.replacementWorkflowState.doesPumpNeedsReplacement

        deletePumpManagerHandler = { [weak self] completion in
            self?.pumpManager.prepareForDeactivation { error in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(error)
                    }
                } else {
                    self?.pumpManager.notifyDelegateOfDeactivation {
                        DispatchQueue.main.async {
                            completion(nil)
                            self?.dismissSettings()
                        }
                    }
                }
            }
        }
        pumpManager.addPumpObserver(self, queue: .main)
        pumpManager.addPumpManagerStateObserver(self, queue: .main)
        pumpManager.addStatusObserver(self, queue: .main)

        updateDescriptiveText()

        NotificationCenter.default.addObserver(forName: UIApplication.significantTimeChangeNotification,
                                               object: nil, queue: nil) { [weak self] _ in self?.updateDisplayOfPumpTime() }
    }
    
    func dismissSettings() {
        pumpManager.removePumpObserver(self)
        pumpManager.removePumpManagerStateObserver(self)
        pumpManager.removeStatusObserver(self)
        expirationProgressViewModel.detach()
        insulinStatusViewModel.detach()
        completionHandler()
    }

    func getBatteryLevel() {
        pumpManager.getBatteryLevel()
    }
    
    func replacePartsSelected() {
        navigator?.navigateTo(.replaceParts)
    }

    @Published var transitioningSuspendInsulinDelivery: Bool
    
    private var wasReplacementWorkflowCanceled: Bool {
        pumpManager.replacementWorkflowState.wasWorkflowCanceled
    }
    
    private var canSuspendResumeInsulinDelivery: Bool {
        pumpManager.operationalState == .ready && !wasInsulinDeliverySuspensionCausedByEMWR
    }
    
    private func updateDescriptiveText() {
        self.descriptiveTextTitle = nil
        
        if pumpManager.status.deliveryIsUncertain == true {
            descriptiveText = uncertainDeliveryDescriptiveText
        } else if pumpManager.pumpStatusHighlight is SignalLossPumpStatusHighlight {
            descriptiveText = signalLossDescriptiveText
        } else if isClockOffset {
            descriptiveTextTitle = clockOffsetTitle
            descriptiveText = clockOffsetDescriptiveText
        } else {
            pumpManager.lookupLatestAnnunciation { [weak self] annunciationType in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let annunciationType {
                        self.descriptiveText = annunciationType.insulinDeliveryStatusLocalizedString(automaticDosingEnabled: self.automaticDosingEnabled)
                    } else if self.isInsulinDeliverySuspendedByUser == true {
                        self.descriptiveText = self.attachPumpDescriptiveText
                    } else {
                        self.descriptiveText = nil
                    }
                }
            }
        }
    }
    
    @Published var lastStatusDate: Date?
    
    @Published var lastCommsDate: Date?
    
    private static let dateTimeFormatter: DateFormatter = {
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateStyle = .short
        dateTimeFormatter.timeStyle = .short
        return dateTimeFormatter
    }()

    var lastStatusDateString: String? {
        return lastStatusDate.map { Self.dateTimeFormatter.string(from: $0) }
    }

    var lastCommsDateString: String? {
        return lastCommsDate.map { Self.dateTimeFormatter.string(from: $0) }
    }

    @Published var synchronizingTime: Bool = false

    func changeTimeZoneTapped(completion: @escaping (Error?) -> Void) {
        synchronizingTime = true
        pumpManager.setPumpTime(using: TimeZone.currentFixed) { [weak self] error in
            self?.synchronizingTime = false
            completion(error)
        }
    }
}

extension SettingsViewModel: InsulinDeliveryPumpObserver {
    
    func pumpDidUpdateState() {
        // only publish when values actually change
        if pumpManager.expirationReminderTimeBeforeExpiration != expiryWarningDuration {
            expiryWarningDuration = pumpManager.expirationReminderTimeBeforeExpiration
        }

        if pumpManager.lowReservoirWarningThresholdInUnits != lowReservoirWarningThresholdInUnits {
            lowReservoirWarningThresholdInUnits = pumpManager.lowReservoirWarningThresholdInUnits
        }

        if !transitioningSuspendResumeInsulinDelivery && pumpManager.suspendedAt != suspendedAt {
            suspendedAt = pumpManager.suspendedAt
        }

        if let deviceInformation = pumpManager.deviceInformation, deviceInformation != self.deviceInformation {
            self.deviceInformation = deviceInformation
        }

        lastCommsDate = pumpManager.state.pumpState.lastCommsDate
        lastStatusDate = pumpManager.state.lastStatusDate

        updateDescriptiveText()
    }

    private func updateDisplayOfPumpTime() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.detectedSystemTimeOffset = self.pumpManager.detectedSystemTimeOffset
            self.canSynchronizePumpTime = self.pumpManager.canSynchronizePumpTime
        }
    }
}

extension SettingsViewModel: InsulinDeliveryPumpManagerStateObserver {
    func pumpManagerDidUpdateState(_ pumpManager: InsulinDeliveryPumpManager, _ state: InsulinDeliveryPumpManagerState) {
        doesPumpNeedsReplacement = state.replacementWorkflowState.doesPumpNeedsReplacement
        automaticDosingEnabled = pumpManager.automaticDosingEnabled

        updateDescriptiveText()
    }
}

extension SettingsViewModel: PumpManagerStatusObserver {
    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        updateDescriptiveText()
    }
}

extension SettingsViewModel.ExpiryReminderRepeat: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .daily: return LocalizedString("Daily", comment: "Expiration repeat reminder daily")
        case .dayBefore: return LocalizedString("Day Before", comment: "Expiration repeat reminder day before")
        case .never: return LocalizedString("Never", comment: "Expiration repeat reminder never")
        }
    }
}

extension SettingsViewModel {
    var signalLossDescriptiveText: String {
        LocalizedString("The pump is out of communication with your device and automation is temporarily off. For more information, consult the general troubleshooting section of your user manual.", comment: "descriptive text when pump signal is lost")
    }
    
    var clockOffsetTitle: String {
        LocalizedString("Time Change Detected", comment:"title of descriptive text when there is a clock offset with the pump")
    }
    
    var clockOffsetDescriptiveText: String {
        LocalizedString("The time on your pump is different from the current time. Your pump’s time controls your scheduled basal rates. You can review the time difference and sync your pump.", comment: "descriptive text when there is a clock offset with the pump")
    }

    var uncertainDeliveryDescriptiveText: String {
        LocalizedString("Problem communicating with pump. Make sure your pump is within 5 feet (1.5 meters) of your phone.", comment: "Insuln suspended time limit reached descriptive text")
    }
    
    var attachPumpDescriptiveText: String {
        LocalizedString("Make sure your pump is attached to your body before resuming insulin delivery.", comment: "Insulin suspended hint text")
    }
}
