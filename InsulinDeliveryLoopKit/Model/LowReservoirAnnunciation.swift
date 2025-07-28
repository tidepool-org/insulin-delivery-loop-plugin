//
//  LowReservoirAnnunciation.swift
//  InsulinDeliveryLoopKit
//
//  Created by Rick Pasetto on 2/10/22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopAlgorithm
import LoopKit
import InsulinDeliveryServiceKit

public struct LowReservoirAnnunciation: Annunciation {
    public let type: AnnunciationType = .reservoirLow
    
    public let identifier: UInt16
    
    public let status: AnnunciationStatus = .pending
    
    public let auxiliaryData: Data? = nil

    public let currentReservoirWarningLevel: Int

    public var annunciationMessageCauseArgs: [CVarArg] {
        let quantityFormatter = QuantityFormatter(for: .internationalUnit)
        let currentReservoirWarningLevel = Double(currentReservoirWarningLevel)
        let level = LoopUnit.internationalUnit.roundForPreferredDigits(value: currentReservoirWarningLevel)
        let valueString = quantityFormatter.string(from: LoopQuantity(unit: .internationalUnit, doubleValue: level)) ?? String(describing: currentReservoirWarningLevel)
        return [valueString]
    }
}
