//
//  MockInsulinDeliveryPumpManagerStatePublisher.swift
//  InsulinDeliveryLoopKitUITests
//
//  Created by Rick Pasetto on 4/19/22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import XCTest
import LoopKit
import LoopKitUI
import InsulinDeliveryServiceKit
import InsulinDeliveryLoopKit
@testable import InsulinDeliveryLoopKitUI

class MockInsulinDeliveryPumpManagerStatePublisher: InsulinDeliveryPumpManagerStatePublisher, PumpManagerStatusPublisher {
    
    var pumpManager: InsulinDeliveryPumpManager
    let now: () -> Date
    init(state: InsulinDeliveryPumpManagerState, status: PumpManagerStatus? = nil, pumpManager: InsulinDeliveryPumpManager? = nil, now: @escaping () -> Date) {
        self.state = state
        self.now = now
        self.pumpManager = pumpManager ?? InsulinDeliveryPumpManager(state: state, pump: MockInsulinDeliveryPump(), dateGenerator: now)
        self.status = status ?? self.pumpManager.status
    }
    var state: InsulinDeliveryPumpManagerState {
        didSet {
            stateObservers.forEach { $0.pumpManagerDidUpdateState(pumpManager, state) }
        }
    }
    var stateObservers = [InsulinDeliveryPumpManagerStateObserver]()
    func addPumpManagerStateObserver(_ observer: InsulinDeliveryPumpManagerStateObserver, queue: DispatchQueue) {
        stateObservers.append(observer)
    }
    func removePumpManagerStateObserver(_ observer: InsulinDeliveryPumpManagerStateObserver) {
        stateObservers.removeAll { $0 === observer }
    }
    
    func setPumpReplacementDate(date: Date) {
        state.replacementWorkflowState.lastPumpReplacementDate = date
        let expiration = date + InsulinDeliveryPumpManager.lifespan
        state.pumpState.deviceInformation?.updateExpirationDate(remainingLifetime: min(max(0, expiration.timeIntervalSinceNow), InsulinDeliveryPumpManager.lifespan))
    }

    var status: PumpManagerStatus {
        didSet {
            statusObservers.forEach { $0.pumpManager(pumpManager, didUpdate: status, oldStatus: oldValue) }
        }
    }
    
    var pumpStatusHighlight: DeviceStatusHighlight? {
        get {
            pumpManager.pumpStatusHighlight
        }
        set {
            pumpManager.pumpStatusHighlight = newValue
            statusObservers.forEach { $0.pumpManager(pumpManager, didUpdate: status, oldStatus: status) }
        }
    }
    var pumpLifecycleProgress: DeviceLifecycleProgress?
    
    var pumpStatusBadge: DeviceStatusBadge?

    var statusObservers = [PumpManagerStatusObserver]()

    func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        statusObservers.append(observer)
    }
    
    func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        statusObservers.removeAll { $0 === observer }
    }
    
    var isPumpConnected: Bool {
        pumpManager.pump.isConnected
    }
}
