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
    private let originalInsulinType: InsulinType?
    private var supportedInsulinTypes: [InsulinType]
    private var didConfirm: (InsulinType) -> Void
    private var didCancel: (() -> Void)?

    init(initialValue: InsulinType?, supportedInsulinTypes: [InsulinType], didConfirm: @escaping (InsulinType) -> Void, didCancel: (() -> Void)? = nil) {
        self._insulinType = State(initialValue: initialValue)
        self.originalInsulinType = initialValue
        self.supportedInsulinTypes = supportedInsulinTypes
        self.didConfirm = didConfirm
        self.didCancel = didCancel
    }

    var hasSelectionChanged: Bool {
        originalInsulinType != insulinType
    }

    func saveTapped(_ insulinType: InsulinType?) {
        if let insulinType = insulinType {
            didConfirm(insulinType)
            dismiss()
        } else {
            assertionFailure()
        }
    }

    var body: some View {
        VStack {
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

            Button(action: { self.saveTapped(insulinType) }) {
                Text(LocalizedString("Save", comment: "Text for save button"))
                    .actionButtonStyle(hasSelectionChanged ? .primary : .deactivated)
                    .padding()
            }
            .disabled(!hasSelectionChanged)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
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
        .toolbarTitleDisplayMode(.inline)
    }
}

struct InsulinTypeSelection_Previews: PreviewProvider {
    static var previews: some View {
        InsulinTypeSelection(initialValue: .humalog, supportedInsulinTypes: InsulinType.allCases, didConfirm: { (newType) in }, didCancel: { })
    }
}
