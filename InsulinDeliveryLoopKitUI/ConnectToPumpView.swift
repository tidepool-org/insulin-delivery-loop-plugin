//
//  ConnectToPumpView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKitUI
import InsulinDeliveryLoopKit

struct ConnectToPumpView: View {
    fileprivate enum PresentedAlert {
        case updatePumpFailed(Error)
    }

    @ObservedObject var viewModel: WorkflowViewModel

    @State private var configuring = false
    @State private var presentedAlert: PresentedAlert?

    var body: some View {
        VStack {
            connectingToPumpCard
            Spacer()
            actionContent
        }
        .alert(item: $presentedAlert, content: alert(for:))
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(trailing: CancelWorkflowWarningButton(viewModel: viewModel))
        .navigationBarTitleDisplayMode(.inline)
        .edgesIgnoringSafeArea(.bottom)
    }

    @ViewBuilder
    private var connectingToPumpCard: some View {
        VStack {
            pumpImage
                .padding(.top, 30)
            instructions
            communicationStatus
            Spacer()
        }
    }

    private var instructions: some View {
        guard viewModel.pumpSetupState != .configured else {
            return FrameworkLocalizedText("You're all set!", comment: "Connecting to pump completed")
                .bold()
                .multilineTextAlignment(.center)
                .font(.title3)
        }
        return FrameworkLocalizedText("Hold your smart device close to the pump", comment: "Instructions for connecting to pump")
            .bold()
            .multilineTextAlignment(.center)
            .font(.title3)
    }

    private var pumpImage: some View {
        Image(frameworkImage: "pump-simulator")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 250)
    }

    @ViewBuilder
    private var communicationStatus: some View {
        VStack(alignment: .center) {
            if viewModel.pumpSetupState.showProgressDetail {
                HStack {
                    ProgressView()
                        .padding(.trailing)
                    Text(viewModel.pumpSetupState.statusMessage)
                }
            } else if viewModel.pumpSetupState == .authenticated {
                FrameworkLocalizedText("Tap Continue to finish configuring the pump", comment: "instructions to continue configuring the pump")
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 5)
            }
        }
        .padding(.horizontal)
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var actionContent: some View {
        Group {
            if viewModel.pumpSetupState == .authenticationFailed {
                VStack {
                    pumpAuthenticationFailedWarning
                    enterPumpInformationButton
                }
            } else if viewModel.pumpSetupState == .authenticationCancelled {
                VStack {
                    pumpAuthenticationCancelledWarning
                    tryAgainButton
                }
            } else if viewModel.pumpSetupState == .pumpAlreadyPaired {
                VStack {
                    pumpAlreadyPairedWarning
                    repeatSetupButton
                }
            } else if viewModel.isPumpConnected && viewModel.pumpSetupState.isFinished {
                VStack(spacing: 15) {
                    ProgressIndicatorView(state: .completed)
                    successMessage
                    continueButton
                }
            } else if viewModel.pumpSetupState != .connecting, !viewModel.isPumpConnected {
                VStack {
                    PumpDisconnectedErrorView()
                    if viewModel.pumpSetupState.isFinished {
                        continueButton
                    }
                }
            } else if viewModel.connectToPumpTimedOut {
                VStack {
                    connectToPumpTimeoutWarning
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground).shadow(radius: 5))
    }

    private var pumpAuthenticationFailedWarning: some View {
        ErrorView(title: LocalizedString("Connection to the pump failed", comment: "Title for pump authentication failed warning"),
                  caption: LocalizedString("A connection to the pump could not be established. Try re-entering your pump information.", comment: "Description for pump authentication failed warning"),
                  displayIcon: true)
    }

    private var pumpAuthenticationCancelledWarning: some View {
        ErrorView(title: LocalizedString("Connection to the pump failed", comment: "Title for pump authentication failed warning"),
                  caption: LocalizedString("A connection to the pump could not be established. Try again and accept the pairing request.", comment: "Description for pump authentication cancelled warning"),
                  displayIcon: true)
    }

    @ViewBuilder
    private var pumpAlreadyPairedWarning: some View {
        if viewModel.workflowType == .replacement {
            pumpAlreadyPairedReplacementWarning
        } else {
            pumpAlreadyPairedSetupWarning
        }
    }
    
    private var pumpAlreadyPairedReplacementWarning: some View {
        ErrorView(title: LocalizedString("Pump already in-use", comment: "Title for pump already paired warning"),
                  caption: LocalizedString("This pump appears to already have been used and a connection to the pump cannot be established.\n\nPlease repeat the replacement process using the new pump and a new reservoir.", comment: "Description for pump already paired warning during replacement"),
                  displayIcon: true)
    }

    private var pumpAlreadyPairedSetupWarning: some View {
        ErrorView(title: LocalizedString("Pump already in-use", comment: "Title for pump already paired warning"),
                  caption: LocalizedString("This pump appears to already have been used and a connection to the pump cannot be established.\n\nPlease repeat the setup process using the new pump and a new reservoir.\n\nDispose of the used reservoir and pump according to local regulations.", comment: "Description for pump already paired warning during setup"),
                  displayIcon: true)
    }

    private var connectToPumpTimeoutWarning: some View {
        ErrorView(title: LocalizedString("Cannot connect to the pump", comment: "Title for connect to pump timeout warning"),
                  caption: LocalizedString("A connection to the pump could not be established. Check whether the pump is too far away. If the issue continues, contact support.", comment: "Description for connect to pump timeout warning"),
                  displayIcon: true)
    }
    
    private var successMessage: some View {
        Text(viewModel.pumpSetupState.statusMessage)
            .font(.headline)
    }

    private var enterPumpInformationButton: some View {
        Button(action: viewModel.selectPumpAgain) {
            FrameworkLocalizedText("Enter Pump Information", comment: "Button label to enter the pump information again")
                .actionButtonStyle(.destructive)
        }
    }

    private var tryAgainButton: some View {
        Button(action: viewModel.connectToPumpAgain) {
            FrameworkLocalizedText("Try Again", comment: "Button label to try connecting to the same pump again")
                .actionButtonStyle(.primary)
        }
    }

    private var repeatSetupButton: some View {
        Button(action: viewModel.repeatPumpSetup) {
            FrameworkLocalizedText("Repeat Setup", comment: "Button label to repeat pump setup again")
                .actionButtonStyle(.destructive)
        }
    }

    private var continueButton: some View {
        Button(action: continueButtonTapped) {
            if viewModel.pumpSetupState == .configured && viewModel.workflowType != .replacement {
                continueSetupText
            } else {
                continueText
            }
        }
        .disabled(viewModel.pumpSetupState.isProcessing || !viewModel.isPumpConnected)
    }
    
    private var continueText: some View {
        FrameworkLocalizedText("Continue", comment: "Button label to continue pump connection and configuration")
            .actionButtonStyle()
    }

    private var continueSetupText: some View {
        FrameworkLocalizedText("Continue Setup", comment: "Button label to continue pump connection and configuration in setup")
            .actionButtonStyle()
    }

    private func continueButtonTapped() {
        if viewModel.pumpSetupState == .authenticated {
            configuring = true
            viewModel.setReservoirLevel() { error in
                configuring = false
                if let error = error {
                    presentedAlert = .updatePumpFailed(error)
                }
            }
        } else {
            viewModel.pumpConfigurationCompleted()
        }
    }

    private func alert(for presentedAlert: PresentedAlert) -> SwiftUI.Alert {
        switch presentedAlert {
        case .updatePumpFailed(let error):
            return Alert(
                title: FrameworkLocalizedText("Failed to Update Pump", comment: "Alert title for error when updating the pump"),
                message: Text(error.localizedDescription)
            )
        }
    }
}

struct ConnectToPumpView_Previews: PreviewProvider {
    static var previews: some View {
        let pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        let pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState)
        let viewModel = WorkflowViewModel(pumpWorkflowHelper: pumpManager,
                                             navigator: MockNavigator())
        return ConnectToPumpView(viewModel: viewModel)
    }
}

extension ConnectToPumpView.PresentedAlert: Identifiable {
    var id: Int {
        switch self {
        case .updatePumpFailed:
            return 0
        }
    }
}
