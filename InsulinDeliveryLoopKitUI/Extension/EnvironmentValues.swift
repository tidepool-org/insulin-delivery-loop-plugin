//
//  EnvironmentValues.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

private struct AllowDebugFeaturesKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    var allowDebugFeatures: Bool {
        get { self[AllowDebugFeaturesKey.self] }
        set { self[AllowDebugFeaturesKey.self] = newValue }
    }
}
