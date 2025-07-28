//
//  InsulinDeliveryPumpManagerError.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2020-03-13.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import BluetoothCommonKit

public enum InsulinDeliveryPumpManagerError: Error, LocalizedError {
    case commError(DeviceCommError)
    case genericError(description: String)
    case hasActiveCommand
    case insulinDeliverySuspended
    case invalidAlert
    case invalidBasalSchedule
    case invalidBolusVolume
    case invalidTempBasalRate
    case missingSettings

    public var errorDescription: String? {
        switch self {
        case .commError(let error):
            return error.errorDescription
        case .genericError(let description):
            return description
        default:
            return nil
        }
    }

    public var failureReason: String? {
        switch self {
        case .commError(_):
            return nil
        case .genericError(_):
            return nil
        case .hasActiveCommand:
            return LocalizedString("Pump is currently busy with another command", comment: "Description that the pump has an active command.")
        case .insulinDeliverySuspended:
            return LocalizedString("Insulin delivery is suspended", comment: "Description that insulin delivery is suspended on the pump.")
        case .invalidAlert:
            return LocalizedString("Invalid alert", comment: "Description that the alert is invalid.")
        case .invalidBasalSchedule:
            return LocalizedString("Invalid basal schedule", comment: "Description that the basal schedule is invalid.")
        case .invalidBolusVolume:
            return LocalizedString("Invalid bolus volume.", comment: "Description that the bolus volume is invalid")
        case .invalidTempBasalRate:
            return LocalizedString("Invalid temp basal rate.", comment: "Description that the temp basal rate is invalid")
        case .missingSettings:
            return LocalizedString("Missing settings", comment: "Description that pump settings are missing.")
        }
    }
}

extension InsulinDeliveryPumpManagerError {
    init(_ deviceCommError: DeviceCommError) {
        self = .commError(deviceCommError)
    }
}
