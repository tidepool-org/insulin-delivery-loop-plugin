//
//  AttachPumpView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKitUI
import InsulinDeliveryLoopKit

struct AttachPumpView: View {
    @ObservedObject var viewModel: WorkflowViewModel

    @State private var displayInsulinDeliveryStarted: Bool
    @State private var startingInsulinDelivery = false
    @State private var alertIsPresented = false
    @State private var error: Error?

    init(viewModel: WorkflowViewModel) {
        self.viewModel = viewModel
        displayInsulinDeliveryStarted = viewModel.therapyState == .run
    }

    var body: some View {
        VStack {
            content
            actionContent
        }
        .alert(isPresented: $alertIsPresented, content: { alert(error: error) })
        .navigationBarBackButtonHidden(viewModel.workflowType == .replacement)
        .navigationBarItems(trailing: CancelWorkflowWarningButton(viewModel: viewModel))
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .edgesIgnoringSafeArea(.bottom)
    }
    
    @ViewBuilder
    private var content: some View {
        RoundedCardScrollView(
            title: LocalizedString(
                "Attach Pump",
                comment: "Title of screen to guide the user on attaching the pump"
            )
        ) {
            RoundedCard(heroView: { attachPumpImage }) {
                attachPumpInstructions
            }
        }
    }
    
    private var attachPumpInstructions: some View {
        InstructionList(instructions: [
            LocalizedString("Attach the pump to your body.", comment: "Attach pump step 1"),
            LocalizedString("Tap to start insulin delivery.", comment: "Attach pump step 2"),
        ])
    }

    private var navTitle: String {
        viewModel.workflowType == .onboarding ? LocalizedString("Attach the pump", comment: "Title of attach pump") : ""
    }
    
    private var attachPumpImage: some View {
        Image(frameworkImage: "pump-simulator")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .openVirtualPumpSettingsOnLongPress(viewModel.virtualPump)
    }

    private var actionContent: some View {
        VStack {
            if viewModel.receivedReservoirIssue {
                ReservoirIssueWarningView(action: { })
            } else if !viewModel.isPumpConnected && !alertIsPresented {
                pumpDisconnectedWarning
            } else {
                if startingInsulinDelivery {
                    progressView(.indeterminantProgress)
                } else if displayInsulinDeliveryStarted {
                    progressView(.completed)
                    insulinDeliveryStartedMessage
                }
                startInsulinDeliveryButton
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground).shadow(radius: 5))
    }

    @ViewBuilder
    private var pumpDisconnectedWarning: some View {
        PumpDisconnectedErrorView()
    }
    
    private func progressView(_ state: ProgressIndicatorState) -> some View {
        VStack {
            ProgressIndicatorView(state: state)
                .padding(.horizontal)
        }
        .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
    }

    private var startInsulinDeliveryButton: some View {
        Button(action: startInsulinDeliveryTapped) {
            startInsulinDeliveryButtonTitle
                .actionButtonStyle()
        }
        .disabled(!viewModel.isPumpConnected || startingInsulinDelivery)
    }

    private var startInsulinDeliveryButtonTitle: Text {
        if displayInsulinDeliveryStarted {
            return FrameworkLocalizedText("Finish", comment: "Title of button when insulin delivery has started")
        } else if startingInsulinDelivery && viewModel.isPumpConnected {
            return FrameworkLocalizedText("Starting Insulin Delivery...", comment: "Title of button while starting insulin delivery")
        } else {
            return FrameworkLocalizedText("Start Insulin Delivery", comment: "Title of start insulin delivery button")
        }
    }

    private func startInsulinDeliveryTapped() {
        guard !displayInsulinDeliveryStarted else {
            viewModel.confirmInsulinDeliveryStarted()
            return
        }

        startingInsulinDelivery = true
        viewModel.startInsulinDeliverySelected() { error in
            startingInsulinDelivery = false
            if let error = error {
                self.error = error
                self.alertIsPresented = true
            } else {
                self.displayInsulinDeliveryStarted = true
            }
        }
    }

    private var insulinDeliveryStartedMessage: some View {
        FrameworkLocalizedText("Insulin Delivery Started", comment: "Message when insulin delivery has started")
            .bold()
            .padding(.top)
    }

    private func alert(error: Error?) -> SwiftUI.Alert {
        SwiftUI.Alert(
            title: FrameworkLocalizedText("Failed to Start Insulin Delivery", comment: "Alert title for error when starting insulin delivery"),
            message: Text(error?.localizedDescription ?? LocalizedString("Unknown Error", comment: "Description when error does not have a description"))
        )
    }
}

struct AttachPumpView_Previews: PreviewProvider {
    static var previews: some View {
        let pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        let pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState)
        let viewModel = WorkflowViewModel(pumpWorkflowHelper: pumpManager,
                                             navigator: MockNavigator())
        return Group {
            AttachPumpView(viewModel: viewModel)
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE"))
                .previewDisplayName("SE light")
            
            AttachPumpView(viewModel: viewModel)
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS Max"))
                .previewDisplayName("XS Max dark")
        }
    }
}
