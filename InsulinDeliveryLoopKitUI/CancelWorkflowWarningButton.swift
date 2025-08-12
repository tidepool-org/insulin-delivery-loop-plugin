//
//  CancelWorkflowWarningButton.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2025-04-30.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKitUI
import InsulinDeliveryLoopKit

typealias AlertTitle = String
typealias AlertMessage = String
typealias AlertAction = () -> Void
typealias AlertModalSecondaryButton = SwiftUI.Alert.Button
typealias AlertModalDetails = (AlertTitle, AlertMessage, AlertModalSecondaryButton)

protocol CancelWorkflowViewModel {
    var cancelWorkflowWarningTitle: AlertTitle { get }
    var cancelWorkflowWarningMessage: AlertMessage { get }

    func warningButtonPrimary(completion: @escaping (AlertModalDetails?) -> Void) -> SwiftUI.Alert.Button
    func warningButtonAction(completion: @escaping (AlertModalDetails?) -> Void) -> AlertAction
}

struct CancelWorkflowWarningButton: View {
    fileprivate enum PresentedAlert {
        case cancelWorkflowWarningAlert
        case couldNotCancelWorkflow(AlertModalDetails)
    }

    var viewModel: CancelWorkflowViewModel

    @State private var presentedAlert: PresentedAlert?

    var body: some View {
        cancelButton
            .alert(item: $presentedAlert, content: alert(for:))
    }

    private var cancelButton: some View {
        Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
            presentedAlert = .cancelWorkflowWarningAlert
        })
    }

    private func alert(for presentedAlert: PresentedAlert) -> Alert {
        switch presentedAlert {
        case .cancelWorkflowWarningAlert:
            return Alert(title: Text(viewModel.cancelWorkflowWarningTitle),
                         message: Text(viewModel.cancelWorkflowWarningMessage),
                         primaryButton: viewModel.warningButtonPrimary() { alertModalDetails in
                guard let alertModalDetails = alertModalDetails else { return }
                self.presentedAlert = .couldNotCancelWorkflow(alertModalDetails) },
                         secondaryButton: .default(FrameworkLocalizedText("No, continue", comment: "Button label to not cancel the workflow")))
        case .couldNotCancelWorkflow(let alertModalDetails):
            return Alert(title: Text(alertModalDetails.0),
                         message: Text(alertModalDetails.1),
                         primaryButton: .cancel(FrameworkLocalizedText("Try Again", comment: "Button label to try cancelling the workflow again")) {
                self.presentedAlert = nil
                self.viewModel.warningButtonAction(completion: { alertModalDetails in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        guard let alertModalDetails = alertModalDetails else { return }
                        self.presentedAlert = .couldNotCancelWorkflow(alertModalDetails) }
                })() },
                         secondaryButton: alertModalDetails.2)
        }
    }
}

extension CancelWorkflowWarningButton.PresentedAlert: Identifiable {
    var id: Int {
        switch self {
        case .cancelWorkflowWarningAlert:
            return 0
        case .couldNotCancelWorkflow:
            return 1
        }
    }
}

struct CancelWorkflowWarningButton_Previews: PreviewProvider {
    static var previews: some View {
        let insulinDeliveryPumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        let pumpManager = InsulinDeliveryPumpManager(state: insulinDeliveryPumpManagerState)
        let viewModel = WorkflowViewModel(pumpWorkflowHelper: pumpManager,
                                             navigator: MockNavigator())
        return CancelWorkflowWarningButton(viewModel: viewModel)
    }
}
