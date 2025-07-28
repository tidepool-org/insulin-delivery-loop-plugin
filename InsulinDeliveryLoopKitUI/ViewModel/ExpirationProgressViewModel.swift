//
//  ExpirationProgressViewModel.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2025-05-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit
import InsulinDeliveryLoopKit

class ExpirationProgressViewModel: ObservableObject {
    private let pumpExpirationProgressViewModel: PumpExpirationProgressViewModel
    
    init(statePublisher: InsulinDeliveryPumpManagerStatePublisher, now: @escaping () -> Date = Date.init ) {
        pumpExpirationProgressViewModel = PumpExpirationProgressViewModel(statePublisher: statePublisher, now: now)
    }
    func viewModel() -> PumpExpirationProgressViewModel {
        pumpExpirationProgressViewModel
    }
    
    var expirationProgress: DeviceLifecycleProgress? {
        let expiration = pumpExpirationProgressViewModel.timeUntilExpiration
        
        guard let expiration,
              expiration < .hours(8)
        else {
            return nil
        }
        assert(pumpExpirationProgressViewModel.expirationProgress != nil)
        return pumpExpirationProgressViewModel.expirationProgress
    }
    
    var pumpExpired: Bool {
        pumpExpirationProgressViewModel.isExpired
    }

    func detach() {
        pumpExpirationProgressViewModel.detach()
    }
}

struct ComponentLifecycleProgress: DeviceLifecycleProgress, Equatable {
    var percentComplete: Double
    var progressState: DeviceLifecycleProgressState
}

class PumpExpirationProgressViewModel: ObservableObject {
    private weak var statePublisher: InsulinDeliveryPumpManagerStatePublisher?
    private let now: () -> Date
    
    @Published var lifespan: TimeInterval = 0
    @Published var lastReplacementDate: Date?
    @Published var expirationDate: Date?
    @Published var isInsulinSuspended: Bool = false
    var pumpExpirationWarningPreference: TimeInterval = 0
    
    var lastState: InsulinDeliveryPumpManagerState?
    
    required init(statePublisher: InsulinDeliveryPumpManagerStatePublisher, now: @escaping () -> Date = { Date() }) {
        self.statePublisher = statePublisher
        self.now = now

        self.update(from: statePublisher.state)
        statePublisher.addPumpManagerStateObserver(self, queue: .main)
    }
    
    func detach() {
        statePublisher?.removePumpManagerStateObserver(self)
        statePublisher = nil
    }
    
    deinit {
        detach()
    }
}

extension PumpExpirationProgressViewModel: InsulinDeliveryPumpManagerStateObserver {

    func pumpManagerDidUpdateState(_ pumpManager: InsulinDeliveryPumpManager, _ state: InsulinDeliveryPumpManagerState) {
        update(from: state)
    }

    private func update(from state: InsulinDeliveryPumpManagerState) {
        if lastState != state {
            lifespan = state.getLifespan()
            lastReplacementDate = state.replacementWorkflowState.lastPumpReplacementDate
            expirationDate = state.getExpirationDate()
            isInsulinSuspended = state.isSuspended || state.replacementWorkflowState.doesPumpNeedsReplacement
            pumpExpirationWarningPreference = state.expirationReminderTimeBeforeExpiration
            lastState = state
        }
    }
}

extension PumpExpirationProgressViewModel {
    var isExpired: Bool {
        guard let timeUntilExpiration = timeUntilExpiration else { return false }
        return timeUntilExpiration <= 0
    }
    var timeUntilExpiration: TimeInterval? {
        expirationDate?.timeIntervalSince(now())
    }
    var expirationProgress: DeviceLifecycleProgress? {
        timeUntilExpiration.map { ComponentLifecycleProgress(percentComplete: (1 - $0 / lifespan).clamped(to: 0...1), progressState: progressState) }
    }
    var progressState: DeviceLifecycleProgressState {
        guard !isInsulinSuspended else { return .dimmed }
        switch timeUntilExpiration {
        case let x? where x <= 0:
            return .critical
        case let x? where x <= .hours(24):
            return .warning
        default:
            return .normalPump
        }
    }
    var isHiddenFromPumpManager: Bool { false }
    
    static let timeFormatter: DateFormatter = {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        return timeFormatter
    }()
    
    static let dateTimeFormatter: DateFormatter = {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .short
        timeFormatter.timeStyle = .short
        return timeFormatter
    }()

    static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let timeFormatter = RelativeDateTimeFormatter()
        timeFormatter.dateTimeStyle = .numeric
        return timeFormatter
    }()
    
    var lastReplacementDateTimeString: String {
        return lastReplacementDate.map { Self.dateTimeFormatter.string(from: $0) } ?? ""
    }
    
    var expirationDateTimeString: String {
        return expirationDate.map { Self.dateTimeFormatter.string(from: $0) } ?? ""
    }
        
    var expirationDateString: String {
        guard let expirationDate = expirationDate else { return "" }
        if Calendar.current.isDateInToday(expirationDate) {
            return String(format: LocalizedString("at %@", comment: "Expiration at time (1: time)"), Self.timeFormatter.string(from: expirationDate))
        } else {
            return Self.relativeTimeFormatter.localizedString(for: expirationDate, relativeTo: now())
        }
    }
    
    var expirationString: String {
        if isExpired {
            return String(format: LocalizedString("%1$@ expired %2$@", comment: "Format for component expiration in the future (1: component title, 2: expiration time)"), LocalizedString("Pump", comment: "Title for Pump"), expirationDateString)
        } else {
            return String(format: LocalizedString("%1$@ expires in", comment: "Format for component expiration in the future (1: component title)"), LocalizedString("Pump", comment: "Title for Pump"))
        }
    }

    var expirationTimeTuple: (interval: String, units: String) {
        switch timeUntilExpiration {
        case let x? where x >= .minutes(1):
            guard let timeUntilExpirationStringParts = DateComponentsFormatter.expirationTimeFormatter.string(from: x)?.components(separatedBy: CharacterSet.whitespaces),
                  timeUntilExpirationStringParts.count >= 2 else {
                      fatalError("Something went wrong with the formatting of the time")
                  }
            return (timeUntilExpirationStringParts[0], timeUntilExpirationStringParts[1])
        case let x? where x > 0:
            return (LocalizedString("< 1", comment: "String meaning \"less than one minute left\""), LocalizedString("minute", comment: "relative time label for minutes"))
        default:
            return (LocalizedString("0", comment: "String meaning \"zero days left\""), LocalizedString("days", comment: "relative time label for days"))
        }
    }
    
    func componentCardExpirationString(replace: Bool) -> String {
        if replace {
            if isExpired {
                return String(format: LocalizedString("Expired %1$@", comment: "Format for component expiration in the future (1: expiration time)"), expirationDateString)
            } else {
                return LocalizedString("Replace", comment: "Replace string for non-expired replacements.")
            }
        } else {
            return String(format: LocalizedString("%1$@ %2$@ left", comment: "Format for component expiration in the future (1: component title)"), expirationTimeTuple.interval, expirationTimeTuple.units)
        }
    }
    
    enum ExpirationTimeColor {
        case critical, warning, normal, dimmed
    }
    var expirationTimeColor: ExpirationTimeColor {
        guard !isInsulinSuspended else { return .dimmed }
        switch expirationProgress?.progressState {
        case .critical:
            return .critical
        case .warning:
            return .warning
        default:
            return .normal
        }
    }
}
