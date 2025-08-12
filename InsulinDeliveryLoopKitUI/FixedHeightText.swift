//
//  FixedHeightText.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

struct FixedHeightText: View {
    private let text: Text

    init(_ string: String) { self.text = Text(string) }
    init(_ string: AttributedString) { self.text = Text(string) }
    init(_ text: Text) { self.text = text }

    var body: some View {
        text
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FixedHeightText_Previews: PreviewProvider {
    static var previews: some View {
        FixedHeightText("Some longer text that needs to be wrapped instead of truncated.")
    }
}
