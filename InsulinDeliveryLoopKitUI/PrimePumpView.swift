//
//  PrimePumpView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKitUI
import InsulinDeliveryLoopKit

struct PrimePumpView: View {
    @Environment(\.guidanceColors) private var guidanceColors
    
    fileprivate enum PresentedAlert {
        case startPriming(Error)
        case stopPriming(Error)
        case displayPrimingIssueWarning
    }

    @ObservedObject var viewModel: WorkflowViewModel

    @State private var startPriming = false
    @State private var stopPriming = false
    @State private var displayPrimingIssueWarning = false
    @State private var primingCompleted = false
    @State private var presentedAlert: PresentedAlert?
    @State private var presentedImageAlert: ImageAlert?

    var body: some View {
        VStack {
            content
            actionContent
        }
        .alert(item: $presentedAlert, content: alert(for:))
        .imageAlert(item: $presentedImageAlert)
        .navigationBarBackButtonHidden(true)
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: CancelWorkflowWarningButton(viewModel: viewModel))
        .edgesIgnoringSafeArea(.bottom)
    }
    
    @ViewBuilder
    private var content: some View {
        RoundedCardScrollView(title: title) {
            RoundedCard(heroView: {
                Image(frameworkImage: "pump-simulator")
                    .resizable()
                    .scaledToFit()
            }) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {         FixedHeightText(Text(subtitle).bold())
                            .font(.title3)
                    }
                    
                    instructions.openVirtualPumpSettingsOnLongPress(viewModel.virtualPump)
                }
            }
        }
    }

    private var title: String? {
        if viewModel.workflowType == .onboarding {
            return nil
        } else {
            return LocalizedString("Prime Pump", comment: "Title of screen for priming the pump")
        }
    }
    
    private var navTitle: String {
        if viewModel.workflowType == .onboarding {
            return LocalizedString("Prime Pump", comment: "Title of screen for priming the pump")
        } else {
            return ""
        }
    }
    
    private var startPrimingInstructions: some View {
        RoundedCard {
            FixedHeightText(
                LocalizedString(
                    """
                    "Now you will prepare to prime the pump.
                    
                    The pump must not be on the body.
                    """,
                    comment: "Start priming instruction that the pump is ready for priming"
                )
            )
            .openVirtualPumpSettingsOnLongPress(viewModel.virtualPump)
            
            Callout(
                .warning,
                title: Text(
                    "Risk of hypoglycemia (low blood glucose level)",
                    comment: "Warning message that the pump must not be on the pump"
                ),
                message: Text(
                    "Make sure that the pump is not attached to your body. There is a risk of uncontrolled insulin delivery. Never prime the pump while attached to your body.",
                    comment: "Warning description that the pump must not be attached to your body"
                )
            )
            .padding(.horizontal, -16)
        
            instructions
        }
    }
    
    private var stopPrimingInstructions: some View {
        RoundedCard(heroView: { primingImage }) {
            Text(subtitle)
                .fontWeight(.semibold)
                
            instructions
                .openVirtualPumpSettingsOnLongPress(viewModel.virtualPump)
        }
    }

    private var subtitle: String {
        if viewModel.pumpSetupState == .configured {
            return LocalizedString("The pump is now ready to prime.", comment: "Instruction to start priming of the pump")
        } else {
            return LocalizedString("When you see a drop of insulin, the pump is primed", comment: "Instruction to stop the priming of the pump")
        }
    }

    @ViewBuilder
    private var instructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.pumpSetupState == .configured {
                FrameworkLocalizedText("Hold the pump in an upright tilted position.", comment: "Message when priming the pump is completed")
                FrameworkLocalizedText("To begin priming the pump, tap Start Priming. Priming may take up to two minutes.", comment: "Message for how long priming may take")
                    .bold()
            } else {
                FrameworkLocalizedText("Pay attention to the opening of the pump and tap stop priming when you see a drop.", comment: "Message for how to detect when priming has completed")
            }
        }
    }
    
    @ViewBuilder
    private var primingImage: some View {
        Image(frameworkImage: "pump-simulator")
            .resizable()
            .aspectRatio(contentMode: ContentMode.fit)
    }

    private var actionContent: some View {
        VStack(spacing: 15) {
            pumpDisconnectedWarningIfNecessary
            if primingCompleted || viewModel.pumpSetupState == .pumpPrimed {
                primingPumpCompleted
            } else if viewModel.receivedReservoirIssue {
                ReservoirIssueWarningView(action: { })
            } else if viewModel.pumpSetupState == .primingPump ||
                        viewModel.pumpSetupState == .primingPumpIssue ||
                        displayPrimingIssueWarning ||
                        stopPriming
            {
                stopPrimingPump
            } else if !stopPriming,
                      viewModel.pumpSetupState == .primingPumpStopped
            {
                continuePrimingPump
            } else {
                startPrimingPump
            }
        }
        .padding(15)
        .background(Color(.secondarySystemGroupedBackground).shadow(radius: 5))
    }

    @ViewBuilder
    private var pumpDisconnectedWarningIfNecessary: some View {
        if !viewModel.isPumpConnected && !startPriming && !stopPriming {
            PumpDisconnectedErrorView()
        }
    }

    @ViewBuilder
    private var stopPrimingPump: some View {
        if !stopPriming && viewModel.isPumpConnected {
            primingMessage
        }
        
        stopPrimingButton
        primingIssueButton
    }

    private var primingMessage: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.trailing, 5)
            Text(viewModel.pumpSetupState.statusMessage)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.bottom)
    }

    private var stopPrimingButton: some View {
        Button(action: stopPrimingSelected) {
            FrameworkLocalizedText("Stop Priming", comment: "Action button description to stop priming and continue to the next step")
                .actionButtonStyle()
        }
        .disabled(stopPrimingButtonDisabled)
    }

    private var primingIssueButton: some View {
        Button(action: {
            presentedAlert = .displayPrimingIssueWarning
            displayPrimingIssueWarning = true
        }) {
            FrameworkLocalizedText("Unable to Prime Pump", comment: "Button label to stop priming the pump when there is an issue")
                .actionButtonStyle(stopPrimingButtonDisabled ? .deactivated : .destructive)
        }
        .disabled(stopPrimingButtonDisabled)
    }

    private func stopPrimingSelected() {
        stopPriming = true
        viewModel.stopPriming() { (error) in
            stopPriming = false
            if let error = error {
                presentedAlert = .stopPriming(error)
            } else {
                primingCompleted = true
            }
        }
    }

    private func issuePrimingSelected() {
        stopPriming = true
        viewModel.issuePriming() { (error) in
            stopPriming = false
            if let error = error {
                presentedAlert = .stopPriming(error)
            }
        }
    }

    private var stopPrimingButtonDisabled: Bool {
        stopPriming || !viewModel.isPumpConnected
    }
    
    @ViewBuilder
    private var primingPumpCompleted: some View {
        VStack(spacing: 12) {
            ProgressIndicatorView(state: .completed)
            successMessage
            primingCompletedButton
        }
    }

    private var successMessage: some View {
        FrameworkLocalizedText("Pump Primed", comment: "Message for when the pump was primed successfully")
            .font(.headline)
    }
    
    private var primingCompletedButton: some View {
        Button(action: viewModel.primingHasCompleted) {
                FrameworkLocalizedText("Continue", comment: "Action button description to continue the workflow after priming pump has completed")
                .actionButtonStyle()
        }
        .disabled(!viewModel.isPumpConnected)
    }

    @ViewBuilder
    private var continuePrimingPump: some View {
        if viewModel.isPumpConnected {
            ErrorView(title: LocalizedString("Did you see a drop of insulin?", comment: "Title of warning when the priming command has completed"),
                      caption: LocalizedString("This means you’re done!\n\nIf you do not see a drop of insulin tap \"continue priming\".", comment: "Message of warning when the priming command has completed"),
                      displayIcon: true)
        }
        
        Button(action: { withAnimation() { primingCompleted = true } }) {
            FrameworkLocalizedText("Yes, I saw a drop", comment: "Button label for when the user has seen a drop of insulin")
                .actionButtonStyle()
        }
        
        Button(action: startPrimingPumpSelected) {
            FrameworkLocalizedText("No, continue priming", comment: "Action button description when priming the pump stopped but can continue")
                .actionButtonStyle(.secondary)
        }
    }

    private var startPrimingButtonDisabled: Bool {
        startPriming || !viewModel.isPumpConnected
    }

    private var startPrimingPump: some View {
        Button(action: startPrimingPumpSelected) {
            FrameworkLocalizedText("Start Priming", comment: "Action button description to start priming")
                .actionButtonStyle()
        }
        .disabled(startPrimingButtonDisabled)
    }

    private func startPrimingPumpSelected() {
        presentedImageAlert = ImageAlert(
            image: .warning,
            title: NSLocalizedString("Pump Must NOT be Attached to your Body", comment: "Title of alert when this is the first run warning"),
            message: NSLocalizedString("Please confirm your pump is not attached to your body.\n\nTap ‘Confirm’ to continue priming the pump.", comment: "Message of alert for pump unattached warning before priming pump"),
            primaryAction: UIAlertAction(title: NSLocalizedString("Confirm", comment: "Alert button label to answer with confirm"), style: .default, handler: { _ in startPrimingConfirmed() }),
            secondaryAction: UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert button label to cancel"), style: .cancel, handler: { _ in })
        )
    }

    private func startPrimingConfirmed() {
        startPriming = true
        viewModel.startPriming() { (error) in
            startPriming = false
            if let error = error {
                presentedAlert = .startPriming(error)
            }
        }
    }

    private func alert(for presentedAlert: PresentedAlert) -> SwiftUI.Alert {
        switch presentedAlert {
        case .startPriming(let error):
            return Alert(
                title: FrameworkLocalizedText("Failed to Start Priming Pump", comment: "Alert title for error when starting to prime pump"),
                message: Text(error.localizedDescription)
            )
        case .stopPriming(let error):
            return Alert(
                title: FrameworkLocalizedText("Failed to Stop Priming Pump", comment: "Alert title for error when stopping the priming of the pump"),
                message: Text(error.localizedDescription)
            )
        case .displayPrimingIssueWarning:
            return Alert(
                title: FrameworkLocalizedText("Unable to Prime Pump", comment: "Title of alert when there is an issue priming the pump"),
                message: FrameworkLocalizedText("The pump could not be primed and may be defective.", comment: "Message of alert when there is an issue priming the pump"),
                primaryButton: .default(FrameworkLocalizedText("Replace", comment: "Alert button label to answer with yes"), action: issuePrimingSelected),
                secondaryButton: .cancel() { displayPrimingIssueWarning = false }
            )
        }
    }
}

struct PrimePumpView_Previews: PreviewProvider {
    static var previews: some View {
        let pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        let pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState)
        let viewModel = WorkflowViewModel(pumpWorkflowHelper: pumpManager,
                                          navigator: MockNavigator())
        return Group {
            PrimePumpView(viewModel: viewModel)
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE"))
                .previewDisplayName("SE light")
            
            PrimePumpView(viewModel: viewModel)
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS Max"))
                .previewDisplayName("XS Max dark")
        }
    }
}

extension PrimePumpView.PresentedAlert: Identifiable {
    var id: Int {
        switch self {
        case .startPriming:
            return 0
        case .stopPriming:
            return 1
        case .displayPrimingIssueWarning:
            return 2
        }
    }
}
