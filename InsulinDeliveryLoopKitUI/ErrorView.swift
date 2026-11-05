//
//  ErrorView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct ErrorView: View {
    @Environment(\.guidanceColors) var guidanceColors

    var title: String
    var captions: [String]
    var criticality: ErrorCriticality
    var displayIcon: Bool

    public enum ErrorCriticality {
        case critical
        case normal

        func symbolColor(using guidanceColors: GuidanceColors) -> Color {
            switch self {
            case .critical:
                return guidanceColors.critical
            case .normal:
                return guidanceColors.warning
            }
        }
    }

    init(title: String, caption: String, errorClass: ErrorCriticality = .normal, displayIcon: Bool = false) {
        self.title = title
        self.captions = [caption]
        self.criticality = errorClass
        self.displayIcon = displayIcon
    }
    
    init(title: String, captions: [String], errorClass: ErrorCriticality = .normal, displayIcon: Bool = false) {
        self.title = title
        self.captions = captions
        self.criticality = errorClass
        self.displayIcon = displayIcon
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            ActionAreaHeader(
                Text(title),
                messages: captions.map({ Text($0) }),
                showsIcon: displayIcon
            ) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(criticality.symbolColor(using: guidanceColors))
            }
        } else {
            legacyContent
        }
    }

    private var legacyContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                if displayIcon {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(self.criticality.symbolColor(using: guidanceColors))
                }

                FixedHeightText(Text(title).bold())
                    .accessibility(identifier: "label_error_description")
            }
            .accessibilityElement(children: .ignore)
            .accessibility(label: FrameworkLocalizedText("Error", comment: "Accessibility label indicating an error occurred"))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(captions.enumerated()), id: \.offset) { index, caption in
                    FixedHeightText(caption)
                        .foregroundColor(.secondary)
                        .font(.footnote)
                        .accessibilityIdentifier(Self.recoverySuggestionIdentifier(at: index))
                }
            }
        }
        .padding(.bottom)
        .accessibilityElement(children: .combine)
    }

    private static func recoverySuggestionIdentifier(at index: Int) -> String {
        index == 0 ? "label_recovery_suggestion" : "label_recovery_suggestion_\(index + 1)"
    }
}

struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        ContentPreview {
            ErrorView(title: "It didn't work", caption: "Maybe try turning it on and off.")
        }
    }
}
