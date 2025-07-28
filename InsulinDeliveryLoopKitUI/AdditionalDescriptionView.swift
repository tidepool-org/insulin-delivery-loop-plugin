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
        let title = "Delete/Swap/Replace CGM"
        let boldedMessage = "This will disconnect from your existing CGM and delete all the CGM settings (for example, the alert configurations). In order to use a CGM, you will need to complete the setup process again."
        let additionalDescription = "Only use this to switching between CGMs from different manufacturers. Do not use this to replace a CGM of the same manufacturer/model (replace a Dexcom G6 with another Dexcom G6). If you are looking to replace a CGM of the same manufacturer/model, go back to settings and tap on the Transmitter ID"
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
