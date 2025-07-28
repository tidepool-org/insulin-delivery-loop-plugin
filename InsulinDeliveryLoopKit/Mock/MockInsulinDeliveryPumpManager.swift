//
//  MockInsulinDeliveryPumpManager.swift
//  MockInsulinDeliveryPumpPlugin
//
//  Created by Nathaniel Hamming on 2021-09-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit
import os.log

public class MockInsulinDeliveryPumpManager: InsulinDeliveryPumpManager {

    let virtualPump: VirtualInsulinDeliveryPump
    
    public override var log: OSLog {
        OSLog(category: "MockInsulinDeliveryPumpManager")
    }

    public override var localizedTitle: String {
        NSLocalizedString("Insulin Delivery Pump", comment: "Generic title of the insulin delivery pump manager")
    }
    
    public override var pluginIdentifier: String { "InsulinDeliveryDemo" }
    
    public required init(pumpStatus: MockInsulinDeliveryPumpStatus? = nil,
                         state: InsulinDeliveryPumpManagerState,
                         dateGenerator: @escaping () -> Date = Date.init)
    {
        virtualPump = VirtualInsulinDeliveryPump(status: pumpStatus)

        super.init(state: state, pump: virtualPump, dateGenerator: dateGenerator)

        virtualPump.delegate = self
    }

    public convenience required init?(rawState: PumpManager.RawStateValue) {
        guard let rawPumpManagerState = rawState["pumpManagerState"] as? PumpManager.RawStateValue,
              let pumpManagerState = InsulinDeliveryPumpManagerState(rawValue: rawPumpManagerState),
              let rawMockPumpStatus = rawState["mockPumpStatus"] as? MockInsulinDeliveryPumpStatus.RawValue,
              let mockPumpStatus = MockInsulinDeliveryPumpStatus(rawValue: rawMockPumpStatus)
        else {
            return nil
        }

        self.init(pumpStatus: mockPumpStatus, state: pumpManagerState)
    }

    required convenience init(state: InsulinDeliveryPumpManagerState, dateGenerator: @escaping () -> Date = Date.init) {
        var status = MockInsulinDeliveryPumpStatus()
        status.pumpConfiguration = state.pumpConfiguration
        self.init(pumpStatus: status, state: state, dateGenerator: dateGenerator)
    }

    public override var rawState: PumpManager.RawStateValue {
        return [
            "pumpManagerState": super.rawState,
            "mockPumpStatus": virtualPump.status.rawValue
        ]
    }
    
    public override var debugDescription: String {
        var lines = [
            "## MockInsulinDeliveryPumpManager",
        ]
        lines.append(contentsOf: [
            state.debugDescription,
            "",
        ])
        return lines.joined(separator: "\n")
    }

}
