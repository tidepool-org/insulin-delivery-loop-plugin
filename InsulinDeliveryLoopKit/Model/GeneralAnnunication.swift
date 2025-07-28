//
//  GeneralAnnunication.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2020-08-18.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import LoopKit
import InsulinDeliveryServiceKit

extension GeneralAnnunciation {
    init?(_ alertIdentifier: Alert.AlertIdentifier) {
        guard let (type, identifier) = GeneralAnnunciation.alertIdentifierComponents(alertIdentifier) else {
            return nil
        }
        self.init(type: type, identifier: identifier, status: .pending, auxiliaryData: nil)
    }
}
