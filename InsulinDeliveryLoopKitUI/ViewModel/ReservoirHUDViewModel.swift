//
//  ReservoirHUDViewModel.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Rick Pasetto on 3/25/22.
//  Copyright © 2022 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryLoopKit

struct ReservoirHUDViewModel {

    var userThreshold: Double
    var reservoirLevel: Double?

    init(userThreshold: Double, reservoirLevel: Double? = nil) {
        self.userThreshold = userThreshold
        self.reservoirLevel = reservoirLevel
    }

    enum ImageType {
        case full, open
    }
    
    var imageType: ImageType {
        switch reservoirLevel {
        case let x? where x >= InsulinDeliveryPumpManager.reservoirAccuracyLimit:
            return .full
        case let x? where x > 0:
            return .open
        case let x? where x == 0:
            return .open
        default:
            return .full
        }
    }
    
    enum WarningColor {
        case normal, warning, error
    }

    var warningColor: WarningColor? {
        switch reservoirLevel {
        case let x? where x > threshold:
            return .normal
        case let x? where x > 0:
            return .warning
        case let x? where x == 0:
            return .error
        default:
            return nil
        }
    }
    
    private var threshold: Double {
        // Actual threshold has a floor of 10U
        max(10.0, Double(userThreshold))
    }
}

