//
//  SetReservoirFillValueView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopAlgorithm
import LoopKit
import LoopKitUI
import InsulinDeliveryLoopKit

struct SetReservoirFillValueView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var viewModel: WorkflowViewModel
    
    @State private var pickerSelection: Int

    private let insulinQuantityFormatter = QuantityFormatter(for: .internationalUnit)

    private func formatValue(_ value: Int) -> String {
        return insulinQuantityFormatter.string(from: LoopQuantity(unit: .internationalUnit, doubleValue: Double(value))) ?? ""
    }

    init(viewModel: WorkflowViewModel) {
        self.viewModel = viewModel
        self._pickerSelection = State(initialValue: viewModel.initialReservoirLevel)
    }

    var body: some View {
        content
            .navigationBarItems(trailing: CancelWorkflowWarningButton(viewModel: viewModel))
            .navigationBarTitleDisplayMode(.inline)
            .edgesIgnoringSafeArea(.bottom)
    }
    
    private var content: some View {
        VStack {
            RoundedCardScrollView(title: LocalizedString("Reservoir Fill Amount", comment: "Title for reservoir fill amount page")) {
                if viewModel.workflowType == .onboarding {
                    RoundedCard {
                        FrameworkLocalizedText("Set your reservoir fill amount", comment: "Subtitle for reservoir fill amount page")
                            .font(.headline)
                            .padding(.bottom, 1)
                        FrameworkLocalizedText("Scroll to set the reservoir fill amount. In Tidepool Loop, the fill amount is reported as an estimate until the reservoir is below 48 U.", comment: "Description for reservoir fill amount page")
                            .font(.subheadline)
                    }
                }
                RoundedCard(footer: footerText) {
                    ExpandableSetting(
                        isEditing: .constant(true),
                        leadingValueContent: {
                            FrameworkLocalizedText("Fill Amount", comment: "Label of reservoir fill amount picker")
                        },
                        trailingValueContent: {
                            Text(formatValue(pickerSelection))
                                .foregroundColor(.accentColor)
                        },
                        expandedContent: { picker }
                    )
                }
            }
            Spacer()
            saveButton
        }
    }

    private var picker: some View {
        Picker("", selection: $pickerSelection) {
            ForEach(InsulinDeliveryPumpManager.supportedReservoirFillVolumes, id: \.self) { value in
                Text("\(value) \(LoopUnit.internationalUnit.localizedUnitString(in: .medium) ?? "U")")
            }
        }
        .pickerStyle(.wheel)
    }

    private var footerText: String {
        LocalizedString("The reservoir must always be filled with at least 20 U (0.2 ml). The reservoir has a maximum holding capacity of 100 U (1.0 ml). The set fill amount will be saved as the default setting for when the reservoir is filled the next time.", comment: "Description of the set reservoir fill amount values")
    }

    private var saveButton: some View {
        Button(action: saveTapped) {
            saveButtonText
                .actionButtonStyle()
                .padding()
        }
        .background(Color(.secondarySystemGroupedBackground).shadow(radius: 5))
    }
    
    @ViewBuilder
    private var saveButtonText: some View {
        if viewModel.workflowType == .onboarding {
            FrameworkLocalizedText("Save and Continue", comment: "Label for save button during onboarding")
        } else {
            FrameworkLocalizedText("Save", comment: "Label for save button")
        }
    }

    private func saveTapped() {
        viewModel.storeInitialReservoirLevel(initialReservoirLevel: pickerSelection)
    }
}

struct SetReservoirFillValueView_Previews: PreviewProvider {
    static var previews: some View {
        let pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        let pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState)
        let viewModel = WorkflowViewModel(pumpWorkflowHelper: pumpManager,
                                          navigator: MockNavigator())
        return Group {
            SetReservoirFillValueView(viewModel: viewModel)
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE"))
                .previewDisplayName("SE light")
            
            SetReservoirFillValueView(viewModel: viewModel)
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS Max"))
                .previewDisplayName("XS Max dark")
        }
    }
}
