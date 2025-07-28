//
//  PumpExpiresSoonAnnunciation.swift
//  InsulinDeliveryLoopKit
//
//  Created by Rick Pasetto on 2/10/22.
//  Copyright © 2022 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit
import InsulinDeliveryServiceKit

public struct PumpExpiresSoonAnnunciation: Annunciation {
    public static let type: AnnunciationType = .endOfPumpLifetime
    public let type: AnnunciationType = type

    public let identifier: UInt16
    
    public let status: AnnunciationStatus = .pending
    
    public let auxiliaryData: Data? = nil

    public let timeRemaining: TimeInterval?
    
    public var annunciationMessageCauseArgs: [CVarArg] {
        let defaultString = NSLocalizedString("soon", comment: "Fallback string for Pump Expiration date annunciation")
        // NOTE: This used to use RelativeDateTimeFormatter but it would give different calculated results than
        // DateComponentsFormatter, which is used here and in other places for consistency.
        let defaultFormat = NSLocalizedString("in %@", comment: "Default format for relative time when we have a time.")
        
        if let timeRemaining = timeRemaining,
           let expirationTimeString = DateComponentsFormatter.expirationTimeFormatter.string(from: timeRemaining) {
            return [String(format: defaultFormat, expirationTimeString)]
        } else {
            return [defaultString]
        }
    }
}
