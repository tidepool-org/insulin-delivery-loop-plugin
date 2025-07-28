//
//  InsulinStatusViewModel.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Rick Pasetto on 4/18/22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import LoopAlgorithm
import SwiftUI
import LoopKit
import LoopKitUI
import InsulinDeliveryLoopKit

class InsulinStatusViewModel: ObservableObject {
    private weak var statePublisher: InsulinDeliveryPumpManagerStatePublisher?

    @Published var basalDeliveryState: PumpManagerStatus.BasalDeliveryState?

    @Published var basalDeliveryRate: Double?

    var isScheduledBasal: Bool {
        switch basalDeliveryState {
        case .active:
            return true
        default:
            return false
        }
    }

    var isTempBasal: Bool {
        switch basalDeliveryState {
        case .tempBasal, .initiatingTempBasal, .cancelingTempBasal:
            return true
        default:
            return false
        }
    }
    
    var isInsulinSuspended: Bool {
        switch basalDeliveryState {
        case .suspended:
            return true
        default:
            return false
        }
    }
        
    @Published var reservoirViewModel: ReservoirHUDViewModel

    @Published private var statusHighlight: DeviceStatusHighlight?
    @Published private var lastCommsDate: Date?
    var isSignalLost: Bool {
        InsulinDeliveryPumpManager.isSignalLost(lastCommsDate: lastCommsDate, isPumpConnected: statePublisher?.isPumpConnected ?? false, asOf: now)
    }
    var pumpStatusHighlight: DeviceStatusHighlight? {
        let shouldShowStatusHighlight = !isInsulinSuspended ||
            (isSignalLost && statusHighlight is SignalLossPumpStatusHighlight) // This avoids a race condition where we detect signal loss timeout but pumpStatusHighlight has not yet updated.

        return shouldShowStatusHighlight ? statusHighlight : nil
    }
    
    private let now: () -> Date
    private var internalBasalDeliveryState: PumpManagerStatus.BasalDeliveryState?
    
    init(statePublisher: InsulinDeliveryPumpManagerStatePublisher, now: @autoclosure @escaping () -> Date = Date()) {
        self.statePublisher = statePublisher
        self.reservoirViewModel = ReservoirHUDViewModel(userThreshold: Double(statePublisher.state.lowReservoirWarningThresholdInUnits))
        self.now = now
        if let statusPublisher = statePublisher as? PumpManagerStatusPublisher {
            self.basalDeliveryState = statusPublisher.status.basalDeliveryState
            update(with: statusPublisher.status, pumpStatusHighlight: statusPublisher.pumpStatusHighlight)
            statusPublisher.addStatusObserver(self, queue: .main)
        }
        statePublisher.addPumpManagerStateObserver(self, queue: .main)
        update(with: statePublisher.state)
    }

    func detach() {
        statePublisher?.removePumpManagerStateObserver(self)
        if let statusPublisher = statePublisher as? PumpManagerStatusPublisher {
            statusPublisher.removeStatusObserver(self)
        }
        statePublisher = nil
    }

    deinit {
        detach()
    }
    
    static let reservoirVolumeFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter(for: .internationalUnit)
        formatter.numberFormatter.maximumFractionDigits = 2
        formatter.avoidLineBreaking = true
        return formatter
    }()

    var reservoirLevelString: String {
        let accuracyLimit = InsulinDeliveryPumpManager.reservoirAccuracyLimit
        let formatter = Self.reservoirVolumeFormatter
        let fallbackString = ""
        switch reservoirViewModel.reservoirLevel {
        case let x? where x >= accuracyLimit:
            // display reservoir level to the nearest 10U when above the accuracy level
            let roundedReservoirLevel = x.rounded(to: 10)
            let quantity = LoopQuantity(unit: .internationalUnit, doubleValue: roundedReservoirLevel)
            return formatter.string(from: quantity, includeUnit: false) ?? fallbackString
        case .some(let value):
            let quantity = LoopQuantity(unit: .internationalUnit, doubleValue: value)
            return formatter.string(from: quantity, includeUnit: false) ?? fallbackString
        default:
            return fallbackString
        }
    }

    var isEstimatedReservoirLevel: Bool {
        guard let reservoirLevel = reservoirViewModel.reservoirLevel else { return false }
        return reservoirLevel >= InsulinDeliveryPumpManager.reservoirAccuracyLimit
    }
    
    private func update(with state: InsulinDeliveryPumpManagerState) {
        // ignore updates while suspending
        guard internalBasalDeliveryState != .suspending else {
            return
        }
        // ... but still update `basalDeliveryRate` while resuming otherwise the UI flashes "No Insulin" briefly
        basalDeliveryRate = state.basalDeliveryRate(at: now())
        // ignore updates while resuming
        guard internalBasalDeliveryState != .resuming else {
            return
        }
        reservoirViewModel = ReservoirHUDViewModel(userThreshold: Double(state.lowReservoirWarningThresholdInUnits), reservoirLevel: state.pumpState.deviceInformation?.reservoirLevel)
        lastCommsDate = state.pumpState.lastCommsDate
    }
    
    private func update(with status: PumpManagerStatus, pumpStatusHighlight: DeviceStatusHighlight?) {
        internalBasalDeliveryState = status.basalDeliveryState
        guard status.basalDeliveryState != .suspending,
              status.basalDeliveryState != .resuming else {
                  return
              }
        if status.basalDeliveryState != basalDeliveryState {
            basalDeliveryState = status.basalDeliveryState
        }
        self.statusHighlight = pumpStatusHighlight
    }
}

extension InsulinStatusViewModel: InsulinDeliveryPumpManagerStateObserver {
    func pumpManagerDidUpdateState(_ pumpManager: InsulinDeliveryPumpManager, _ state: InsulinDeliveryPumpManagerState) {
        update(with: state)
    }
}

extension InsulinStatusViewModel: PumpManagerStatusObserver {
    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        update(with: status, pumpStatusHighlight: (pumpManager as? PumpStatusIndicator)?.pumpStatusHighlight)
    }
}

extension ReservoirHUDViewModel {
    var imageName: String {
        switch imageType {
        case .full:
            return "generic-reservoir-mask"
        case .open:
            return "generic-reservoir"
        }
    }
}

public protocol PumpManagerStatusPublisher: AnyObject, PumpStatusIndicator {
    var status: PumpManagerStatus { get }
    var pumpStatusHighlight: DeviceStatusHighlight? { get }
    func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue)
    func removeStatusObserver(_ observer: PumpManagerStatusObserver)
}

extension InsulinDeliveryPumpManager: PumpManagerStatusPublisher { }

extension InsulinDeliveryPumpManagerState {
        
    func basalDeliveryRate(at now: Date) -> Double? {
        switch suspendState {
        case .resumed:
            if let tempBasal = unfinalizedTempBasal, !tempBasal.isFinished(at: now) {
                return tempBasal.rate
            } else {
                return basalRateSchedule.value(at: now)
            }
        case .suspended, .none:
            return nil
        }
    }
}

extension String {
    static let nonBreakingSpace = "\u{00a0}"
}
