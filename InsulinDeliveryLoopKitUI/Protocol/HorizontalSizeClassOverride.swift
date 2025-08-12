//
//  HorizontalSizeClassOverride.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2020-04-09.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

protocol HorizontalSizeClassOverride {
    var horizontalOverride: UserInterfaceSizeClass { get }
}

extension HorizontalSizeClassOverride {
    var horizontalOverride: UserInterfaceSizeClass {
        if UIScreen.main.bounds.height <= 640 {
            return .compact
        } else {
            return .regular
        }
    }
}

