//
//  InsulinDeliveryPumpCommError.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2021-09-13.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation

public enum InsulinDeliveryPumpCommError: Equatable {
    case acknowledgingAnnunciationFailed
}

extension InsulinDeliveryPumpCommError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .acknowledgingAnnunciationFailed:
            return LocalizedString("Tidepool Loop was unable to clear the alert on your pump, therefore you may continue to hear an audible beep.", comment: "Description of error when acknowledging annunciation failed.")
        }
    }
}
