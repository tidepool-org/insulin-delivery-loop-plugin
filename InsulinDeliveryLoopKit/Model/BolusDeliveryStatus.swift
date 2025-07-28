//
//  BolusDeliveryStatus.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2021-11-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//
//

import InsulinDeliveryServiceKit

extension BolusDeliveryStatus {
    func unfinalizedBolus(at now: Date = Date()) -> UnfinalizedDose? {
        guard self.progressState != .noActiveBolus else { return nil }
        
        let startTime = self.startTime ?? now.addingTimeInterval(-self.insulinDelivered / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate)
        var unfinalizedBolus = UnfinalizedDose(bolusAmount: self.insulinProgrammed,
                                               startTime: startTime,
                                               scheduledCertainty: progressState == .estimatingProgress ? .uncertain : .certain)
        // calculate the end time
        switch progressState {
        case .noActiveBolus: return nil
        case .canceled:
            unfinalizedBolus.cancel(at: endTime ?? now, insulinDelivered: insulinDelivered)
        case .completed:
            unfinalizedBolus.endTime = startTime.addingTimeInterval(insulinProgrammed / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate)
            unfinalizedBolus.programmedUnits = insulinProgrammed
            unfinalizedBolus.units = insulinProgrammed
        case .estimatingProgress:
            // use the expected delivery rate to calculate the endTime
            unfinalizedBolus.endTime = startTime.addingTimeInterval(insulinProgrammed / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate)
        case .inProgress:
            // the bolus may be delivered slowly. As such recalculate the endTime
            unfinalizedBolus.endTime = endTime ?? now.addingTimeInterval((insulinProgrammed - insulinDelivered) / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate)
        }
        
        return unfinalizedBolus
    }
}
