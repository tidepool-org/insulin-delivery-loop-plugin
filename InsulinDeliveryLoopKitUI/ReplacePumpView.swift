//
//  ReplacePumpView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-08-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import InsulinDeliveryLoopKit

struct ReplaceComponentsView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.guidanceColors) var guidanceColors
    @Environment(\.insulinTintColor) var insulinTintColor

    @ObservedObject var viewModel: WorkflowViewModel

    @State private var stoppingInsulinDelivery = false
    @State private var unpairingPumpBase = false
    
    private var communicationInProgress: Bool {
        stoppingInsulinDelivery || unpairingPumpBase
    }

    var body: some View {
        VStack {
            replacePump
            Spacer()
            actionContent
        }
        .navigationBarBackButtonHidden(communicationInProgress)
        .navigationBarTitleDisplayMode(.inline)
        .edgesIgnoringSafeArea(.bottom)
    }
    
    private var replacePump: some View {
        RoundedCardScrollView(title: LocalizedString("Replace Pump", comment: "Title for replace pump page"))
        {
            instructions
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 7) {
            FixedHeightText(LocalizedString("Are you sure you want to replace your pump? This action cannot be taken back.", comment: "Description for replacing pump"))
        }
    }
    
    private var actionContent: some View {
        VStack {
            replaceButton
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground).shadow(radius: 5))
    }

    private var replaceButton: some View {
        Button(action: replaceTapped) {
            Text(replaceButtonText)
                .actionButtonStyle()
        }
        .disabled(disableReplaceButton)
    }

    private var disableReplaceButton: Bool {
        communicationInProgress
    }

    private func replaceTapped() {
        viewModel.replacePumpSelected()
    }

    private var replaceButtonText: String {
        return LocalizedString("Start Pump Replacement", comment: "Button label for replacing the selected system component")
    }
}

struct ReplaceComponentsView_Previews: PreviewProvider {
    static var previews: some View {
        let pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        let pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState)
        let viewModel = WorkflowViewModel(pumpWorkflowHelper: pumpManager,
                                          navigator: MockNavigator())
        return ReplaceComponentsView(viewModel: viewModel)
    }
}
