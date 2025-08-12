//
//  NotificationSettingsView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopAlgorithm
import LoopKit
import LoopKitUI

struct NotificationSettingsView: View {
    @Environment(\.allowDebugFeatures) var allowDebugFeatures

    let expiryWarningDuration: TimeInterval

    let allowedExpiryWarningDurations: [TimeInterval]

    let expiryReminderRepeat: SettingsViewModel.ExpiryReminderRepeat
    
    let lowReservoirWarningThresholdInUnits: Int

    let allowedLowReservoirWarningThresholdsInUnits: [Int]

    let timeFormatterDaysOnly: DateComponentsFormatter

    let insulinQuantityFormatter: QuantityFormatter

    let dateFormatterTimeOnly: DateFormatter

    let dateFormatterDateOnly: DateFormatter

    var onSaveExpiryWarningDuration: SettingsViewModel.ExpirySaveCompletion?

    var onSaveLowReservoirWarning: ((_ selectedValue: Int) -> Void)?

    init(expiryWarningDuration: TimeInterval,
         allowedExpiryWarningDurations: [TimeInterval],
         expiryReminderRepeat: SettingsViewModel.ExpiryReminderRepeat,
         lowReservoirWarningThresholdInUnits: Int,
         allowedLowReservoirWarningThresholdsInUnits: [Int],
         insulinQuantityFormatter: QuantityFormatter,
         onSaveExpiryWarningDuration: SettingsViewModel.ExpirySaveCompletion? = nil,
         onSaveLowReservoirWarning: ((_ selectedValue: Int) -> Void)? = nil)
    {
        self.expiryWarningDuration = expiryWarningDuration
        self.allowedExpiryWarningDurations = allowedExpiryWarningDurations
        self.expiryReminderRepeat = expiryReminderRepeat
        self.lowReservoirWarningThresholdInUnits = lowReservoirWarningThresholdInUnits
        self.allowedLowReservoirWarningThresholdsInUnits = allowedLowReservoirWarningThresholdsInUnits
        self.insulinQuantityFormatter = insulinQuantityFormatter

        timeFormatterDaysOnly = DateComponentsFormatter()
        timeFormatterDaysOnly.unitsStyle = .full
        timeFormatterDaysOnly.allowedUnits = [.day]

        dateFormatterTimeOnly = DateFormatter()
        dateFormatterTimeOnly.dateStyle = .none
        dateFormatterTimeOnly.timeStyle = .short

        dateFormatterDateOnly = DateFormatter()
        dateFormatterDateOnly.dateStyle = .medium
        dateFormatterDateOnly.timeStyle = .none
        dateFormatterDateOnly.doesRelativeDateFormatting = true
    }

    var body: some View {
        RoundedCardScrollView(title: LocalizedString("Notification Settings", comment: "Title for notification settings view")) {
            expiryWarningSection(title: LocalizedString("Insulin Delivery Notifications", comment: "Insulin Delivery notifications section title"))
            lowReservoirWarningSection
            criticalAlertsSection
        }
    }
    
    // MARK: MP Expiry
    @State private var expiryWarningEditViewIsShown = false

    @ViewBuilder
    private func expiryWarningSection(title: String) -> some View {
        RoundedCard(title: title) {
            expiryWarningRow
            if expiryReminderRepeat != .never {
                repeatReminderRow
            }
        }
    }

    private var expiryWarningRow: some View {
        NavigationLink(destination:
                        PumpExpiryWarningEditView(
                            expiryWarningDuration: expiryWarningDuration,
                            allowedDurations: allowedExpiryWarningDurations,
                            showInstructionalContent: false,
                            expiryReminderRepeat: expiryReminderRepeat,
                            timeFormatter: timeFormatterDaysOnly,
                            onSave: onSaveExpiryWarningDuration,
                            onFinish: {
                                expiryWarningEditViewIsShown = false
                            }),
                       isActive: $expiryWarningEditViewIsShown) {
            RoundedCardValueRow(
                label: LocalizedString("Pump Expiration Warning", comment: "Description label for pump expiry warning in pump notification settings"),
                value: timeFormatterDaysOnly.string(from: expiryWarningDuration) ?? "",
                highlightValue: false,
                disclosure: true
            )
        }
    }
    
    @ViewBuilder
    private var repeatReminderRow: some View {
        LabeledValueView(
            label: LocalizedString("Repeat Reminder", comment: "Description label for pump expiry repeat reminder in pump notification settings"),
            value: expiryReminderRepeat.description
        )
    }

    // MARK: Low Reservoir Warning

    private var lowReservoirWarningSection: some View {
        RoundedCard {
            lowReservoirWarningRow
        }
    }

    @State private var lowReservoirWarningEditViewIsShown: Bool = false

    private var lowReservoirWarningRow: some View {
        NavigationLink(destination:
                        LowReservoirWarningEditView(
                            threshold: lowReservoirWarningThresholdInUnits,
                            allowedThresholds: allowedLowReservoirWarningThresholdsInUnits,
                            insulinQuantityFormatter: insulinQuantityFormatter,
                            showInstructionalContent: false,
                            onSave: onSaveLowReservoirWarning,
                            onFinish: {
                                lowReservoirWarningEditViewIsShown = false
                            }),
                       isActive: $lowReservoirWarningEditViewIsShown)
        {
            RoundedCardValueRow(
                label: LocalizedString("Low Reservoir Warning", comment: "Description label for low reservoir warning in pump notification settings"),
                value: insulinQuantityFormatter.string(from: LoopQuantity(unit: .internationalUnit, doubleValue: Double(lowReservoirWarningThresholdInUnits))) ?? "",
                highlightValue: false,
                disclosure: true
            )
        }
    }
    
    // MARK: Critical Alerts

    private var criticalAlertsSection: some View {
        VStack(spacing: 5) {
            RoundedCardTitle(LocalizedString("Critical Alerts", comment: "Critical alerts section title"))
            RoundedCardFooter(LocalizedString("""
                The reminders above will not sound if your device is in Silent or Do Not Disturb mode.

                There are other critical pump alerts and alarms that will sound even if you device is set to Silent or Do Not Disturb mode.
                """, comment: "Description of critical alerts in critical alerts section footer"))
            .padding(.bottom)
        }
    }
}

struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        var allowedExpiryWarningDurations: [TimeInterval] = []
        for days in 4...30 {
            allowedExpiryWarningDurations.append(.days(days))
        }
        let timeFormatter = DateComponentsFormatter()
        timeFormatter.unitsStyle = .full
        timeFormatter.allowedUnits = [.day]

        let now = Date()
        let twoHoursFromNow = now.addingTimeInterval(.hours(2))

        return ContentPreview {
            NotificationSettingsView(
                expiryWarningDuration: .days(10),
                allowedExpiryWarningDurations: allowedExpiryWarningDurations,
                expiryReminderRepeat: .daily,
                lowReservoirWarningThresholdInUnits: 20,
                allowedLowReservoirWarningThresholdsInUnits: Array(stride(from:5, to: 40, by: 5)),
                insulinQuantityFormatter: QuantityFormatter(for: .internationalUnit))
        }
    }
}

fileprivate extension Edge.Set {
    static var none: Edge.Set { Edge.Set(rawValue: 0) }
}
