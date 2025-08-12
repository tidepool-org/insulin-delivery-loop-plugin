//
//  PumpKeyEntryManualView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-08-06.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKitUI
import InsulinDeliveryLoopKit

struct PumpKeyEntryManualView: View, HorizontalSizeClassOverride {
    @ObservedObject var viewModel: WorkflowViewModel

    @State private var typedPumpKey = ""
    @State private var displayConfirmation = false
    @State private var showPumpKeyLocation = false

    private let pumpKeyLengthMin: Int = InsulinDeliveryPumpManager.pumpKeyLengthRange.lowerBound
    private let pumpKeyLengthMax: Int = InsulinDeliveryPumpManager.pumpKeyLengthRange.upperBound

    var body: some View {
        VStack {
            RoundedCardScrollView(title: LocalizedString("Enter Pump Key", comment: "Navigation view title for enter pump key view")) {
                RoundedCard {
                    pumpKeyInput
                        .padding(.vertical)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: saveButton)
        .edgesIgnoringSafeArea(.bottom)
    }

    private var pumpKeyInput: some View {
        DismissibleKeyboardTextField(text: $typedPumpKey,
                                     placeholder: LocalizedString("Enter Pump Key", comment: "Placeholder text until the pump key is entered"),
                                     font: .preferredFont(forTextStyle: .largeTitle),
                                     textAlignment: .center,
                                     keyboardType: .asciiCapable,
                                     autocapitalizationType: .allCharacters,
                                     autocorrectionType: .no,
                                     shouldBecomeFirstResponder: true,
                                     maxLength: pumpKeyLengthMax,
                                     isDismissible: false)
            .padding()
    }

    private var saveButton: some View {
        Button(LocalizedString("Save", comment: "Save button title"), action: {
            typedPumpKey = typedPumpKey.trimmingCharacters(in: .whitespacesAndNewlines)
            displayConfirmation = true
        })
        .disabled(typedPumpKey.count < pumpKeyLengthMin)
        .alert(isPresented: $displayConfirmation) {
            confirmEntryAlert
        }
    }

    private var confirmEntryAlert: SwiftUI.Alert {
        Alert(title: FrameworkLocalizedText("Confirm Entry", comment: "Confirm entered pump key title"),
              message: Text(typedPumpKey),
              primaryButton: confirmAlertButton,
              secondaryButton: .cancel()
        )
    }

    private var confirmAlertButton: SwiftUI.Alert.Button {
        .default(FrameworkLocalizedText("Confirm", comment: "Confirm button title"),
                action: { viewModel.pumpKeyEntry(typedPumpKey) })
    }
}

struct PumpKeyEntryManualView_Previews: PreviewProvider {
    static var previews: some View {
        let pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        let pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState)
        let viewModel = WorkflowViewModel(pumpWorkflowHelper: pumpManager,
                                          navigator: MockNavigator())
        PumpKeyEntryManualView(viewModel: viewModel)
    }
}
