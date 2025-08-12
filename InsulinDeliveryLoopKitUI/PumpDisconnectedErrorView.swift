//
//  PumpDisconnectedErrorView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

struct PumpDisconnectedErrorView: View {
    var body: some View {
        ErrorView(title: LocalizedString("Cannot connect to the pump", comment: "Title for pump disconnected warning"),
                  caption: LocalizedString("A connection to the pump could not be established. Check whether the pump is too far away and try again.", comment: "Description for pump disconnected warning"),
                  displayIcon: true)
    }
}

struct PumpDisconnectedErrorView_Previews: PreviewProvider {
    static var previews: some View {
        PumpDisconnectedErrorView()
    }
}
