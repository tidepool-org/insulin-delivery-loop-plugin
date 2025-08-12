//
//  AdditionalDescriptionView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct AdditionalDescriptionView: View, HorizontalSizeClassOverride {
    @Environment(\.presentationMode) private var presentationMode
    var title: String
    var boldedMessage: String
    var additionalDescription: String
    var confirmButtonTitle: String = LocalizedString("OK", comment: "OK button title")
    var confirmButtonType: ActionButton.ButtonType = .primary
    var confirmAction: (() -> Void)? = nil
    var displayCancelButton: Bool = false
    
    var body: some View {
        NavigationView {
            GuidePage(content: {
                VStack(alignment: .leading, spacing: 10) {
                    FixedHeightText(Text(boldedMessage).bold())
                    FixedHeightText(additionalDescription)
                }
            }) {
                VStack(alignment: .leading, spacing: 15) {
                    Button(action: {
                        confirmAction?()
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        FixedHeightText(confirmButtonTitle)
                            .actionButtonStyle(confirmButtonType)
                    }
                    
                    if displayCancelButton {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            FrameworkLocalizedText("Cancel", comment: "Cancel button title")
                                .actionButtonStyle(confirmButtonType == .destructive ? .primary : .secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitle(title)
            .environment(\.horizontalSizeClass, horizontalOverride)
        }
    }
}

struct AdditionalDescriptionView_Previews: PreviewProvider {
    static var previews: some View {
        let title = "Delete/Swap/Replace Device"
        let boldedMessage = "This will disconnect from your existing device and delete all the device settings (for example, the alert configurations). In order to use a device, you will need to complete the setup process again."
        let additionalDescription = "Only use this to switching between devices from different manufacturers. Do not use this to replace a device of the same manufacturer/model. If you are looking to replace a device of the same manufacturer/model, go back to settings and tap on replace device"
        return NavigationView {
                AdditionalDescriptionView(title: title,
                                          boldedMessage: boldedMessage,
                                          additionalDescription: additionalDescription,
                                          confirmButtonTitle: title,
                                          confirmButtonType: .destructive,
                                          displayCancelButton: true)
        }
    }
}
