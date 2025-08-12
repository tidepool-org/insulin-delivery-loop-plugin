//
//  InsulinStatusView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import LoopAlgorithm
import SwiftUI
import LoopKit

struct InsulinStatusView: View {
    @Environment(\.guidanceColors) var guidanceColors
    @Environment(\.insulinTintColor) var insulinTintColor

    @ObservedObject var viewModel: InsulinStatusViewModel

    private let subViewSpacing: CGFloat = 21

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            deliveryStatus
                .fixedSize(horizontal: true, vertical: true)
            Spacer()
            Divider()
                .frame(height: dividerHeight)
                .offset(y:3)
            Spacer()
            reservoirStatus
                .fixedSize(horizontal: true, vertical: true)
        }
    }

    private var dividerHeight: CGFloat {
        guard inNoDelivery == false else {
            return 65 + subViewSpacing-10
        }

        return 65 + subViewSpacing
    }

    let basalRateFormatter = QuantityFormatter(for: .internationalUnitsPerHour)
    let reservoirVolumeFormatter = QuantityFormatter(for: .internationalUnit)

    private var inNoDelivery: Bool {
        !viewModel.isInsulinSuspended && viewModel.basalDeliveryRate == nil
    }

    private var deliveryStatusSpacing: CGFloat {
        return subViewSpacing
    }

    var deliveryStatus: some View {
        VStack(alignment: .leading, spacing: deliveryStatusSpacing) {
            FixedHeightText(deliverySectionTitle)
                .foregroundColor(.secondary)
            if viewModel.isInsulinSuspended {
                insulinSuspended
            } else if let basalRate = viewModel.basalDeliveryRate {
                basalRateView(basalRate)
            } else {
                noDelivery
            }
        }
    }
    
    var insulinSuspended: some View {
        HStack(alignment: .center, spacing: 2) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 34))
                .fixedSize()
                .foregroundColor(guidanceColors.warning)
            FrameworkLocalizedText("Insulin\nSuspended", comment: "Text shown in insulin remaining space when no pump is paired")
                .font(.subheadline.weight(.heavy))
                .lineSpacing(0.01)
                .fixedSize()
        }
    }

    private func basalRateView(_ basalRate: Double) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    let unit = LoopUnit.internationalUnitsPerHour
                    let quantity = LoopQuantity(unit: unit, doubleValue: basalRate)
                    Text(basalRateFormatter.string(from: quantity, includeUnit: false) ?? "")
                        .font(.system(size: 28))
                        .fontWeight(.heavy)
                        .fixedSize()
                    Text(basalRateFormatter.localizedUnitStringWithPlurality(forQuantity: quantity))
                        .foregroundColor(.secondary)
                }
                Group {
                    if viewModel.isScheduledBasal {
                        FrameworkLocalizedText("Scheduled\(String.nonBreakingSpace)Basal", comment: "Subtitle of insulin delivery section during scheduled basal")
                    } else if viewModel.isTempBasal {
                        FrameworkLocalizedText("Temporary\(String.nonBreakingSpace)Basal", comment: "Subtitle of insulin delivery section during temporary basal")
                    }
                }
                .font(.footnote)
                .foregroundColor(.accentColor)
            }
        }
    }
    
    var noDelivery: some View {
        HStack(alignment: .center, spacing: 2) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 34))
                .fixedSize()
                .foregroundColor(guidanceColors.critical)
            FrameworkLocalizedText("No\nDelivery", comment: "Text shown in insulin remaining space when no pump is paired")
                .font(.subheadline.weight(.heavy))
                .lineSpacing(0.01)
                .fixedSize()
        }
    }

    var deliverySectionTitle: String {
        LocalizedString("Insulin\(String.nonBreakingSpace)Delivery", comment: "Title of insulin delivery section")
    }

    private var reservoirStatusSpacing: CGFloat {
        subViewSpacing
    }

    var reservoirStatus: some View {
        VStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: reservoirStatusSpacing) {
                FrameworkLocalizedText("Insulin\(String.nonBreakingSpace)Remaining", comment: "Header for insulin remaining on pump settings screen")
                    .foregroundColor(Color(UIColor.secondaryLabel))
                HStack {
                    if let pumpStatusHighlight = viewModel.pumpStatusHighlight {
                        pumpStatusWarningText(pumpStatusHighlight: pumpStatusHighlight)
                    } else {
                        reservoirLevelStatus
                    }
                }
            }
        }
    }

    @ViewBuilder
    func pumpStatusWarningText(pumpStatusHighlight: DeviceStatusHighlight) -> some View {
        HStack(alignment: .center, spacing: 2) {
            Image(systemName: pumpStatusHighlight.imageName)
                .font(.system(size: 34))
                .fixedSize()
                .foregroundColor(guidanceColors.critical)
            
            Text(pumpStatusHighlight.localizedMessage)
                .font(.subheadline.weight(.heavy))
                .lineSpacing(0.01)
                .fixedSize()
        }
    }
    
    @ViewBuilder
    var reservoirLevelStatus: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Image(frameworkImage: viewModel.reservoirViewModel.imageName)
                    .resizable()
                    .foregroundColor(reservoirColor)
                    .frame(width: 25, height: 38, alignment: .bottom)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(viewModel.reservoirLevelString)
                        .font(.system(size: 28))
                        .fontWeight(.heavy)
                        .fixedSize()
                    Text(reservoirVolumeFormatter.localizedUnitStringWithPlurality())
                        .foregroundColor(.secondary)
                }
            }
            if viewModel.isEstimatedReservoirLevel {
                FrameworkLocalizedText("Estimated Reading", comment: "label when reservoire level is estimated")
                    .font(.footnote)
                    .foregroundColor(.accentColor)
            } else {
                FrameworkLocalizedText("Accurate Reading", comment: "label when reservoire level is estimated")
                    .font(.footnote)
                    .foregroundColor(.accentColor)
            }
        }
        .offset(y: -11) // the reservoir image should have tight spacing so move the view up
        .padding(.bottom, -11)
    }
    
    var reservoirColor: Color {
        switch viewModel.reservoirViewModel.warningColor {
        case .normal:
            return insulinTintColor
        case .warning:
            return guidanceColors.warning
        case .error:
            return guidanceColors.critical
        case .none:
            return guidanceColors.acceptable
        }
    }
}
