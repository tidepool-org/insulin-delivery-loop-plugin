//
//  ReservoirIssueWarningView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

struct ReservoirIssueWarningView: View {
    var action: () -> Void

    var body: some View {
        reservoirIssueWarning
    }

    @ViewBuilder
    private var reservoirIssueWarning: some View {
        ErrorView(title: LocalizedString("Deviation in Reservoir Amount", comment: "Title for pump reservoir issue warning"),
                  caption: LocalizedString("""
                    The amount of insulin detected in the reservoir is too low and does not match the fill amount of insulin entered into Tidepool Loop.

                    To resolve this issue, add more insulin to reach a minimum of 80 U in your reservoir and re-enter your reservoir fill amount.
                    """, comment: "Description for pump disconnected warning"),
                  displayIcon: true)
        restartReservoirFillButton
    }

    private var restartReservoirFillButton: some View {
        Button(action: action) {
            FrameworkLocalizedText("Re-Enter Reservoir Fill", comment: "Title of restart reservoir fill button")
                .actionButtonStyle(.destructive)
        }
    }
}

struct ReservoirIssueWarningView_Previews: PreviewProvider {
    static var previews: some View {
        ReservoirIssueWarningView(action: { })
    }
}
