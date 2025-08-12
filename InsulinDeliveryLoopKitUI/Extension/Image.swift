//
//  Image.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

private class FrameworkBundle {
    static let main = Bundle(for: FrameworkBundle.self)
}

extension Image {
    init(frameworkImage name: String) {
        self.init(name, bundle: FrameworkBundle.main)
    }

    static var disclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .imageScale(.small)
            .font(.headline)
            .foregroundColor(.secondary)
            .opacity(0.5)
    }
}

