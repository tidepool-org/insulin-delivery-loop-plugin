//
//  LowReservoirWarningEditView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopAlgorithm
import LoopKit
import LoopKitUI

struct LowReservoirWarningEditView: View {
    @Environment(\.dismissAction) private var dismiss

    enum PresentationMode {
        case onboarding
        case settings
    }

    @State private var selectedValue: Int

    private let initialValue: Int

    let allowedThresholdsSorted: [Int]
    let insulinQuantityFormatter: QuantityFormatter
    let presentationMode: PresentationMode
    let showInstructionalContent: Bool
    let onSave: ((_ selectedValue: Int) -> Void)?
    let onPause: (() -> Void)?
    let onFinish: (() -> Void)?

    init(threshold: Int,
         allowedThresholds: [Int],
         insulinQuantityFormatter: QuantityFormatter,
         presentationMode: PresentationMode = .settings,
         showInstructionalContent: Bool,
         onSave: ((_ selectedValue: Int) -> Void)? = nil,
         onPause: (() -> Void)? = nil,
         onFinish: (() -> Void)? = nil)
    {
        precondition(!allowedThresholds.isEmpty)
        let allowedThresholdsSorted = allowedThresholds.sorted()
        
        self.allowedThresholdsSorted = allowedThresholdsSorted
        self.insulinQuantityFormatter = insulinQuantityFormatter
        self.presentationMode = presentationMode
        self.showInstructionalContent = showInstructionalContent
        self.onSave = onSave
        self.onPause = onPause
        self.onFinish = onFinish
        
        self.initialValue = threshold
        self._selectedValue = State(initialValue: threshold)
    }

    var body: some View {
        if presentationMode == .onboarding {
            onboardingContent
        } else {
            settingsContent
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        if valueChanged {
            content
                .navigationBarBackButtonHidden(true)
                .navigationBarItems(leading: cancelButton)
        } else {
            content
        }
    }

    private var onboardingContent: some View {
        content
            .navigationBarItems(trailing: pauseButton)
    }

    private var pauseButton: some View {
        Button(action: {
            onSave?(selectedValue)
            onPause?()
        }) {
            FrameworkLocalizedText("Close", comment: "Button title for suspending onboarding on LowReservoirWarningEditView")
        }
    }


    private var cancelButton: some View {
        Button(action: {
            onFinish?()
        }) {
            FrameworkLocalizedText("Cancel", comment: "Button title for cancelling pump expiry warning edit on LowReservoirWarningEditView")
        }
    }

    private var content: some View {
        VStack {
            RoundedCardScrollView(title: LocalizedString("Low Reservoir", comment: "Title for low reservoir warning edit page")) {
                if showInstructionalContent {
                    instructionalContent
                }
                RoundedCard(footer: footerText) {
                    ExpandableSetting(
                        isEditing: .constant(true),
                        leadingValueContent: {
                            FrameworkLocalizedText("Low Reservoir Warning", comment: "Label for low reservoir warning row")
                        },
                        trailingValueContent: {
                            Text(formatValue(selectedValue))
                                .foregroundColor(.accentColor)
                        },
                        expandedContent: { picker }
                    )
                }
            }
            Spacer()
            Button(action: saveTapped) {
                Text(saveButtonText)
                    .actionButtonStyle()
                    .padding()
            }
            .disabled(!valueChanged && presentationMode == .settings)
        }
    }

    private var instructionalContent: some View {
        RoundedCard {
            FixedHeightText(LocalizedString("Set your low reservoir warning", comment: "LowReservoirWarningEditView instructional content header"))
                .font(.headline)
                .padding(.bottom, 1)
            FixedHeightText(LocalizedString("Set to receive an alert when the amount of insulin in the reservoir reaches this level (5-40 U). Scroll to set the number of units at which you would like to be warned.", comment: "LowReservoirWarningEditView instructional content body"))
                .font(.subheadline)
        }
    }

    private var footerText: String {
        LocalizedString("The app and pump notify you when the amount of insulin in the reservoir reaches this level.", comment: "Description for low reservoir warning editor")
    }

    private func formatValue(_ value: LoopQuantity) -> String {
        return insulinQuantityFormatter.string(from: value) ?? ""
    }

    private var picker: some View {
        Picker(selection: $selectedValue) {
            ForEach(allowedThresholdsSorted, id: \.self) { value in
                Text(self.formatValue(value))
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.wheel)
    }

    private func formatValue(_ value: Int) -> String {
        return insulinQuantityFormatter.string(from: LoopQuantity(unit: .internationalUnit, doubleValue: Double(value))) ?? ""
    }

    private var saveButtonText: String {
        if presentationMode == .onboarding {
            return LocalizedString("Continue", comment: "Button title for continuing when LowReservoirWarningEditView presented in onboarding mode")
        } else {
            return LocalizedString("Save", comment: "Button title for saving warning threshold on LowReservoirWarningEditView")
        }
    }

    private func saveTapped() {
        if valueChanged {
            onSave?(selectedValue)
        }
        self.onFinish?()
    }

    private var valueChanged: Bool {
        return selectedValue != initialValue
    }

}

struct LowReservoirWarningEditView_Previews: PreviewProvider {
    static var previews: some View {
        let insulinQuantityFormatter = QuantityFormatter(for: .internationalUnit)
        return ContentPreview {
            LowReservoirWarningEditView(
                threshold: 20,
                allowedThresholds: Array(stride(from: 5, to: 40, by: 5)),
                insulinQuantityFormatter: insulinQuantityFormatter,
                showInstructionalContent: true)
        }
    }
}
