//
//  InsulinDeliveryLoopKitPlugin.swift
//  InsulinDeliveryLoopPlugin
//
//  Created by Nathaniel Hamming on 2025-03-13.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKitUI
import InsulinDeliveryLoopKit
import InsulinDeliveryLoopKitUI
import os.log

class InsulinDeliveryLoopKitPlugin: NSObject, PumpManagerUIPlugin {
    
    private let log = OSLog(category: "InsulinDeliveryLoopKitPlugin")

    public var pumpManagerType: PumpManagerUI.Type? {
        return InsulinDeliveryPumpManager.self
    }

    override init() {
        super.init()
        log.default("InsulinDeliveryLoopKitPlugin Instantiated")
    }
}
