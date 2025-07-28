//
//  InsulinDeliveryPumpManager+WorkflowHelper.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2020-08-18.
//  Copyright © 2020 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

extension InsulinDeliveryPumpManager: InsulinDeliveryPumpWorkflowHelper {    
    public var isPumpConnected: Bool {
        pump.isConnected
    }

    public var isPumpAuthenticated: Bool {
        pump.isAuthenticated
    }

    public var therapyState: InsulinTherapyControlState {
        return pump.deviceInformation?.therapyControlState ?? .undetermined
    }
    
    public var operationalState: PumpOperationalState {
        return pump.deviceInformation?.pumpOperationalState ?? .undetermined
    }
    
    public var initialReservoirLevel: Int {
        get {
            return pump.state.initialReservoirLevel
        }
        set {
            if pump.state.initialReservoirLevel != newValue {
                pump.state.initialReservoirLevel = newValue
            }
        }
    }

    public var remainingPumpLifetime: TimeInterval? {
        get {
            pump.state.deviceInformation?.estimatedRemainingLifeTime
        }
    }
 
    public func prepareForNewPump() {
        logDelegateEvent()
        resetPendingItems()
        pump.prepareForNewPump()
    }
        
    public func connectToPump(withIdentifier identifier: UUID,
                              andSerialNumber serialNumber: String) {
        pump.connectToPump(withIdentifier: identifier,
                               andSerialNumber: serialNumber)
    }
    
    public func configurePump(completion: @escaping (Error?) -> Void) {
        setPumpTime(using: pumpTimeZone) { [weak self] error in
            guard error == nil else {
                completion(error)
                return
            }

            guard let self = self else {
                completion(nil)
                return
            }

            self.pump.configurePump(pumpConfiguration: self.pumpConfiguration,
                                    initialConfiguration: true) { result in
                switch result {
                case .success():
                    completion(nil)
                case .failure(let error):
                    completion(error)
                }
            }
        }
    }
    
    public func setReservoirLevel(reservoirLevel: Int, completion: @escaping (Error?) -> Void) {
        pump.prepareForInsulinDelivery(reservoirLevel: reservoirLevel,
                                       basalProfile: state.basalRateSchedule.basalProfile) { result in
            switch result {
            case .success():
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }

    public func startPriming(completion: @escaping (Error?) -> Void) {
        pump.startPrimingReservoir(InsulinDeliveryPumpManager.primingAmount) { result in
            switch result {
            case .success():
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }
    
    public func stopPriming(completion: @escaping (Error?) -> Void) {
        pump.stopPriming() { result in
            switch result {
            case .success():
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }
    
    public func startInsulinDelivery(completion: @escaping (Error?) -> Void) {
        resumeDelivery(completion: completion)
    }
    
    public func stopInsulinDelivery(completion: @escaping (Error?) -> Void) {
        suspendDelivery(completion: completion)
    }
    
    public func getVirtualPump() -> VirtualInsulinDeliveryPump? {
        return pump as? VirtualInsulinDeliveryPump
    }
}
