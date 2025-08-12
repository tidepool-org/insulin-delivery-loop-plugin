//
//  MockInsulinDeliveryPumpPlugin.swift
//  MockInsulinDeliveryPumpPlugin
//
//  Created by Nathaniel Hamming on 2021-09-01.
//  Copyright © 2021 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKitUI
import InsulinDeliveryLoopKit
import InsulinDeliveryLoopKitUI
import os.log

class MockInsulinDeliveryPumpPlugin: NSObject, PumpManagerUIPlugin {
    private let log = OSLog(category: "MockInsulinDeliveryPumpPlugin")

    public var pumpManagerType: PumpManagerUI.Type? {
        return MockInsulinDeliveryPumpManager.self
    }

    override init() {
        super.init()
        log.default("MockInsulinDeliveryPumpPlugin Instantiated")
    }
}
