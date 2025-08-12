//
//  DeviceDetailsView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopAlgorithm
import LoopKit
import LoopKitUI
import InsulinDeliveryLoopKit
import InsulinDeliveryServiceKit

struct DeviceDetailsView: View {
    @Environment(\.allowDebugFeatures) var allowDebugFeatures
    @Environment(\.insulinTintColor) var insulinTintColor
    @Environment(\.guidanceColors) var guidanceColors

    @ObservedObject var viewModel: SettingsViewModel

    var deviceInformation: DeviceInformation? {
        viewModel.deviceInformation
    }

    let pumpManagerState: InsulinDeliveryPumpManagerState
    let insulinQuantityFormatter: QuantityFormatter
    let getBatteryLevel: () -> Void

    @State private var showDebug: Bool = false
    
    var body: some View {
        RoundedCardScrollView(title: LocalizedString("Pump Details", comment: "Device details screen title")) {
            RoundedCard(title: LocalizedString("Component Information", comment: "Component Information section title"), footer: expirationFooter) {
                pumpExpiration
            }
            
            RoundedCard {
                batteryDetail
                    .openVirtualPumpSettingsOnLongPress(enabled: allowDebugFeatures, pumpManager: viewModel.pumpManager)
            }
            
            RoundedCard(title: LocalizedString("System Information", comment: "System Information section title")) {
                systemInformationDetail
                if allowDebugFeatures && showDebug {
                    FixedHeightText(pumpManagerState.debugDescription)
                        .font(.system(.body, design: .monospaced))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showDebug = false
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showDebug = false
            }
            .onLongPressGesture {
                if allowDebugFeatures {
                    showDebug = true
                }
            }
        }
        .onAppear {
            getBatteryLevel()
        }
    }
    
    @ViewBuilder
    private var pumpExpiration: some View {
        let pumpViewModel = viewModel.expirationProgressViewModel.viewModel()
        PumpExpirationProgressView(viewModel: pumpViewModel)
            .openVirtualPumpSettingsOnLongPress(enabled: allowDebugFeatures, pumpManager: viewModel.pumpManager)
        Divider()
        DateRangeView(
            title: "Pump",
            startDate: pumpViewModel.lastReplacementDate,
            endDate: pumpViewModel.expirationDate
        )
    }

    private var expirationFooter: String {
        NSLocalizedString("The lifespan of the pump is 10 days.", comment: "Foot note describing the expected lifespan of the pump")
    }

    private var batteryDetail: some View {
        HStack {
            Image(frameworkImage: "battery.circle.fill")
                .foregroundColor(batteryLevelInfo.color)
            LabeledValueView(label: LocalizedString("Battery", comment: "Battery Field label"), value: batteryLevelInfo.string)
        }
    }
    
    private var batteryLevelInfo: (color: Color, string: String) {
        switch deviceInformation?.batteryLevelIndicator {
        case .full:
            return (insulinTintColor, LocalizedString("Full", comment: "Battery string for full (=100%) battery"))
        case .medium:
            return (insulinTintColor, LocalizedString("Medium", comment: "Battery string for medium (>=50%) battery"))
        case .low:
            return (guidanceColors.warning, LocalizedString("Low", comment: "Battery string for low (>=25%) battery"))
        case .empty:
            return (guidanceColors.critical, LocalizedString("Empty", comment: "Battery string for empty (=0%) battery"))
        default:
            return (.gray, "")
        }
    }

    private var reservoirInformationDetailSectionFooter: String? {
        guard isReservoirLevelEstimated else { return nil }

        return LocalizedString("The reservoir fill amount is reported as an estimate until it reaches 48 U. Any reported value over 48 U may be a few units different than the true value.", comment: "Reservoir information detail footer")
    }
    
    private var systemInformationDetail: some View {
        Group {
            LabeledValueView(label: LocalizedString("Serial Number", comment: "Serial Number Field label"), value: serialNumber)
            Divider()
            LabeledValueView(label: LocalizedString("Firmware Number", comment: "Firmware Number Field label"), value: firmwareRevision)
            if showDebug {
                Divider()
                LabeledValueView(label: LocalizedString("Therapy State", comment: "Therapy State Field label"), value: therapyControlState)
                Divider()
                LabeledValueView(label: LocalizedString("Operational State", comment: "Operational State Field label"), value: pumpOperationalState)
                Divider()
                LabeledValueView(label: LocalizedString("Last Status", comment: "Last Status Field label"), value: viewModel.lastStatusDateString)
                Divider()
                LabeledValueView(label: LocalizedString("Last Comms", comment: "Last Comms Field label"), value: viewModel.lastCommsDateString)
            }
        }
    }
    
    private var serialNumber: String? {
        deviceInformation?.serialNumber
    }

    private var firmwareRevision: String? {
        deviceInformation?.firmwareRevision
    }

    private var hardwareRevision: String? {
        deviceInformation?.hardwareRevision
    }
    
    private var reservoirLevel: String? {
        guard let reservoirLevel = deviceInformation?.reservoirLevel else {
            return nil
        }
        return insulinQuantityFormatter.string(from: LoopQuantity(unit: .internationalUnit, doubleValue: reservoirLevel))
    }

    private var isReservoirLevelEstimated: Bool {
        return deviceInformation?.isReservoirLevelEstimated(InsulinDeliveryPumpManager.reservoirAccuracyLimit) ?? true
    }
    
    private var therapyControlState: String? {
        deviceInformation?.therapyControlState.localizedDescription
    }

    private var pumpOperationalState: String? {
        deviceInformation?.pumpOperationalState.localizedDescription
    }
}

struct IDSDeviceDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = SettingsViewModel(pumpManager: InsulinDeliveryPumpManager(state: InsulinDeliveryPumpManagerState.forPreviewsAndTests), navigator: MockNavigator(), completionHandler: { })
        return ContentPreview {
            DeviceDetailsView(viewModel: viewModel,
                                 pumpManagerState: InsulinDeliveryPumpManagerState(basalRateSchedule: BasalRateSchedule(dailyItems: [], timeZone: nil)!, maxBolusUnits: 0),
                                 insulinQuantityFormatter: QuantityFormatter(for: .internationalUnit),
                                 getBatteryLevel: { })
        }
    }
}
