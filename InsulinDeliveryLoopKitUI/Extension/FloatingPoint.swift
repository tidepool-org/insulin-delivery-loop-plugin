//
//  FloatingPoint.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation

extension FloatingPoint {
    func rounded(to nearest: Self, roundingRule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Self {
       (self / nearest).rounded(roundingRule) * nearest
    }
}
