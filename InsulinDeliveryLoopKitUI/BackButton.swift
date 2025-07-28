//
//  BackButton.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

struct BackButton: View {
    var action: () -> Void
    var label: String?

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "chevron.left")
                    .resizable()
                    .font(.title.weight(.semibold))
                    .frame(width: 12, height: 20)
                Text(label ?? backTitle)
                    .fontWeight(.regular)
            }
            .offset(x: -6, y: 0)
        }
    }

    private var backTitle: String { LocalizedString("Back", comment: "Back navigation for dexcom plugin") }
}

struct BackButton_Previews: PreviewProvider {
    static var previews: some View {
        BackButton(action: {})
    }
}

