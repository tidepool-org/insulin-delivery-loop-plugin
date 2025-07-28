//
//  InsulinDeliveryDoseProgressTimerEstimator.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2020-05-28.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit
import InsulinDeliveryServiceKit

class InsulinDeliveryDoseProgressTimerEstimator: DoseProgressReporter {
    let dose: DoseEntry
    
    weak var pumpManager: InsulinDeliveryPumpManager?
    
    private var insulinDelivered: Double = 0
    
    private let pollingDelay: TimeInterval = .seconds(2)
    
    private var bolusProgressState: BolusProgressState = .inProgress

    private let lock = UnfairLock()

    private var observers = WeakSet<DoseProgressObserver>()

    private let reportingQueue: DispatchQueue

    init(dose: DoseEntry, pumpManager: InsulinDeliveryPumpManager, reportingQueue: DispatchQueue) {
        self.dose = dose
        self.pumpManager = pumpManager
        self.reportingQueue = reportingQueue
    }
    
    func addObserver(_ observer: DoseProgressObserver) {
        var firstObserver: Bool = false
        lock.withLock {
            firstObserver = observers.isEmpty
            observers.insert(observer)
        }
        if firstObserver {
            updateBolusDeliveryDetails()
        }
    }

    func removeObserver(_ observer: DoseProgressObserver) {
        lock.withLock {
            observers.remove(observer)
        }
    }
    
    func notify() {
        let observersCopy = lock.withLock { observers }
        var shouldUpdate = bolusProgressState.isOngoing
        for observer in observersCopy {
            reportingQueue.async {
                observer.doseProgressReporterDidUpdate(self)
            }
            if shouldUpdate {
                shouldUpdate = false
                reportingQueue.asyncAfter(deadline: .now() + pollingDelay) {  [weak self] in
                    self?.updateBolusDeliveryDetails()
                }
            }
        }
    }

    private func updateBolusDeliveryDetails() {
        pumpManager?.updateBolusDeliveryDetails() { [weak self] (bolusDeliveryStatus: BolusDeliveryStatus) in
            guard let self = self else { return }
            self.bolusProgressState = bolusDeliveryStatus.progressState
            switch self.bolusProgressState {
            case .inProgress, .canceled, .estimatingProgress:
                self.insulinDelivered = bolusDeliveryStatus.insulinDelivered
                self.notify()
            case .completed:
                self.insulinDelivered = self.dose.programmedUnits
                self.notify()
            case .noActiveBolus:
                break
            }
        }
    }

    var progress: DoseProgress {
        guard bolusProgressState.isOngoing else {
            return DoseProgress(deliveredUnits: insulinDelivered, percentComplete: 1)
        }

        let percentComplete = min(insulinDelivered / dose.programmedUnits, 0.99) // do not report completed until bolusProgressState is completed
        return DoseProgress(deliveredUnits: insulinDelivered, percentComplete: percentComplete)
    }
}
