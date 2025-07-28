//
//  InsulindDeliveryPumpWorkflowHelper.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2020-08-17.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit
import InsulinDeliveryServiceKit

public protocol InsulinDeliveryPumpWorkflowHelper: AnyObject {
    var isPumpConnected: Bool { get }

    var isPumpAuthenticated: Bool { get }

    var therapyState: InsulinTherapyControlState { get }
    
    var operationalState: PumpOperationalState { get }

    var initialReservoirLevel: Int { get set }
    
    var remainingPumpLifetime: TimeInterval? { get }
    
    func addPumpObserver(_ observer: InsulinDeliveryPumpObserver, queue: DispatchQueue)

    func addPumpManagerStateObserver(_ observer: InsulinDeliveryPumpManagerStateObserver, queue: DispatchQueue)
    
    func prepareForNewPump()

    func connectToPump(withIdentifier identifier: UUID, andSerialNumber serialNumber: String)
    
    func configurePump(completion: @escaping (Error?) -> Void)
    
    func setReservoirLevel(reservoirLevel: Int, completion: @escaping (Error?) -> Void)

    func startPriming(completion: @escaping (Error?) -> Void)
    
    func stopPriming(completion: @escaping (Error?) -> Void)
        
    func startInsulinDelivery(completion: @escaping (Error?) -> Void)
    
    func stopInsulinDelivery(completion: @escaping (Error?) -> Void)
    
    func getVirtualPump() -> VirtualInsulinDeliveryPump?
}
