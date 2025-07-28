//
//  Color.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

private class FrameworkBundle {
    static let main = Bundle(for: FrameworkBundle.self)
}

extension Color {
    init?(frameworkColor name: String) {
        self.init(name, bundle: FrameworkBundle.main)
    }
}

