//
//  InsulinTypeSelection.swift
//  InsulinDeliveryLoopKit
//
//  Created by Pete Schwamb on 1/13/26.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

struct InsulinTypeSelection: View {
    @Environment(\.dismiss) private var dismiss

    @State private var insulinType: InsulinType?
    @State private var showingConfirmation = false
    private let originalInsulinType: InsulinType?
    private var supportedInsulinTypes: [InsulinType]
    private var didConfirm: (InsulinType) -> Void
    private var didCancel: (() -> Void)?
    private var enableConfirmationDialog: Bool
    private var enableCancelButton: Bool

    init(initialValue: InsulinType?, supportedInsulinTypes: [InsulinType], isInitialSetup: Bool = false, didConfirm: @escaping (InsulinType) -> Void, didCancel: (() -> Void)? = nil) {
        self._insulinType = State(initialValue: initialValue)
        self.originalInsulinType = initialValue
        self.supportedInsulinTypes = supportedInsulinTypes
        self.didConfirm = didConfirm
        self.didCancel = didCancel
        self.enableConfirmationDialog = !isInitialSetup
        self.enableCancelButton = !isInitialSetup
    }

    var hasSelectionChanged: Bool {
        originalInsulinType != insulinType
    }

    func saveTapped(_ insulinType: InsulinType?) {
        if enableConfirmationDialog {
            showingConfirmation = true
        } else {
            if let insulinType = insulinType {
                didConfirm(insulinType)
                dismiss()
            } else {
                assertionFailure()
            }
        }
    }

    var body: some View {
        List {
            Section(content: {
                Text(LocalizedString("Select the type of insulin that you are using in this pump.", comment: "Title text for insulin type confirmation page"))
                    .font(.subheadline)
            }, header: {
                Text("Insulin Type", comment: "Title of insulin selection screen")
                    .font(.largeTitle)
                    .bold()
                    .padding(.vertical)
                    .foregroundStyle(.foreground)
            })
            Section {
                InsulinTypeChooser(insulinType: $insulinType, supportedInsulinTypes: supportedInsulinTypes)
                    .listRowSeparator(.hidden)
            }
            .buttonStyle(PlainButtonStyle()) // Disable row highlighting on selection
        }
        .insetGroupedListStyle()
        .actionAreaInset {
            Button(action: { self.saveTapped(insulinType) }) {
                Text(LocalizedString("Save", comment: "Text for save button"))
                    .actionButtonStyle(hasSelectionChanged ? .primary : .deactivated)
            }
            .disabled(!hasSelectionChanged)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if (enableCancelButton) {
                    if hasSelectionChanged {
                        Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
                            didCancel?()
                            dismiss()
                        })
                    } else {
                        Button(LocalizedString("Done", comment: "Done button title"), action: {
                            dismiss()
                        })
                    }
                }
            }
        }
        .toolbarTitleDisplayMode(.inline)
        .alert(isPresented: $showingConfirmation) {
            Alert(
                title: Text("Change Insulin Type?"),
                message: Text("Are you sure you want to change your insulin type?\n\nChanging your insulin type during an active pump session only affects insulin delivered after the change. It does not apply to any insulin already delivered."),
                primaryButton: .default(Text("Yes, Change Insulin")) {
                    if let insulinType = self.insulinType {
                        self.didConfirm(insulinType)
                        self.dismiss()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
}

struct InsulinTypeSelection_Previews: PreviewProvider {
    static var previews: some View {
        InsulinTypeSelection(initialValue: .humalog, supportedInsulinTypes: InsulinType.allCases, didConfirm: { (newType) in }, didCancel: { })
    }
}
