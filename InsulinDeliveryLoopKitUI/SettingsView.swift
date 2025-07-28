//
//  SettingsView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import InsulinDeliveryLoopKit
import InsulinDeliveryServiceKit

struct SettingsView: View {
    fileprivate enum PresentedAlert {
        case resumeInsulinDeliveryError(Error)
        case suspendInsulinDeliveryError(Error)
        case syncTimeError(Error)
        case cannotDeletePumpManager(Error)
    }

    @Environment(\.guidanceColors) var guidanceColors
    @Environment(\.insulinTintColor) var insulinTintColor
    @Environment(\.allowDebugFeatures) var allowDebugFeatures
    @ObservedObject var viewModel: SettingsViewModel

    @State private var displayDeleteWarning = false
    @State private var showSuspendOptions = false
    @State private var presentedAlert: PresentedAlert?
    @State private var shouldDeletePumpManager = false
    @State private var showSyncTimeOptions = false

    var body: some View {
        List {
            statusSection

            activitySection

            deviceDetailsSection

            if allowDebugFeatures {
                deletePumpManagerSection
            }
        }
        .insetGroupedListStyle()
        .navigationBarItems(trailing: doneButton)
        .navigationBarTitle(Text(viewModel.pumpManagerTitle), displayMode: .large)
        .alert(item: $presentedAlert, content: alert(for:))
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            VStack(spacing: 8) {
                pumpProgressView
                    .openVirtualPumpSettingsOnLongPress(enabled: allowDebugFeatures, pumpManager: viewModel.pumpManager)
                insulinInfo
                descriptiveText
            }
        }
    }
    
    @ViewBuilder
    private var pumpProgressView: some View {
        let viewModel = viewModel.expirationProgressViewModel.viewModel()
        VStack(spacing: 8) {
            PumpExpirationProgressView(viewModel: viewModel)
            Divider()
        }
    }
        
    var insulinInfo: some View {
        InsulinStatusView(viewModel: viewModel.insulinStatusViewModel)
            .environment(\.guidanceColors, guidanceColors)
            .environment(\.insulinTintColor, insulinTintColor)
    }
    
    @ViewBuilder
    var descriptiveText: some View {
        if viewModel.descriptiveTextTitle != nil || viewModel.descriptiveText != nil {
            VStack(alignment: .leading) {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    if let descriptiveTextTitle = viewModel.descriptiveTextTitle {
                        FixedHeightText(descriptiveTextTitle)
                            .font(.footnote.weight(.bold))
                    }
                    
                    if let descriptiveText = viewModel.descriptiveText {
                        FixedHeightText(descriptiveText)
                            .multilineTextAlignment(.leading)
                            .font(.footnote.weight(.semibold))
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }
    
    @ViewBuilder
    private var activitySection: some View {
        suspendResumeInsulinSubSection

        notificationSubSection
            .disabled(viewModel.insulinDeliveryDisabled)

        replacePumpSubSection
    }

    private var suspendResumeInsulinSubSection: some View {
        Section(header: SectionHeader(label: LocalizedString("Activity", comment: "Section header for the activity section"))) {
            Button(action: suspendResumeTapped) {
                HStack(spacing: 8) {
                    // https://stackoverflow.com/questions/75046730/swiftui-list-divider-unwanted-inset-at-the-start-when-non-text-component-is-u
                    Text("").frame(maxWidth: 0)
                        .accessibilityHidden(true)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        if viewModel.suspendResumeInsulinDeliveryStatus.showPauseIcon {
                            Image(systemName: "pause.circle.fill")
                                .foregroundColor(viewModel.suspendResumeInsulinDeliveryStatus != .suspended ? nil : guidanceColors.warning)
                        }
                        
                        Text(viewModel.suspendResumeInsulinDeliveryStatus.localizedLabel)
                            .fontWeight(.semibold)
                    }
                    
                    if viewModel.transitioningSuspendResumeInsulinDelivery {
                        ProgressView()
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .actionSheet(isPresented: $showSuspendOptions) {
                   suspendOptionsActionSheet
                }
            }
            .disabled(viewModel.insulinDeliveryDisabled || viewModel.transitioningSuspendInsulinDelivery || viewModel.transitioningSuspendResumeInsulinDelivery)
            if viewModel.isInsulinDeliverySuspendedByUser {
                LabeledValueView(label: LocalizedString("Suspended At", comment: "Label for suspended at field"),
                                 value: viewModel.suspendedAtString)
            }
        }
    }

    private var suspendOptionsActionSheet: ActionSheet {
        let completion: (Error?) -> Void = { (error) in
            if let error = error {
                self.presentedAlert = .suspendInsulinDeliveryError(error)
            }
        }

        var suspendReminderDelayOptions: [SwiftUI.Alert.Button] = viewModel.suspendReminderDelayOptions.map { suspendReminderDelay in
            .default(Text(viewModel.suspendReminderTimeFormatter.string(from: suspendReminderDelay)!),
                     action: { viewModel.suspendInsulinDelivery(reminderDelay: suspendReminderDelay, completion: completion) })
        }
        suspendReminderDelayOptions.append(.cancel())

        return ActionSheet(
            title: FrameworkLocalizedText("Delivery Suspension Reminder", comment: "Title for suspend duration selection action sheet"),
            message: FrameworkLocalizedText("How long would you like to suspend insulin delivery for?", comment: "Message for suspend duration selection action sheet"),
            buttons: suspendReminderDelayOptions)
    }

    private func suspendResumeTapped() {
        if viewModel.isInsulinDeliverySuspended {
            viewModel.resumeInsulinDelivery() { (error) in
                if let error = error {
                    self.presentedAlert = .resumeInsulinDeliveryError(error)
                }
            }
        } else {
            showSuspendOptions = true
        }
    }

    @ViewBuilder
    private var deviceDetailsSection: some View {
        NavigationLink(destination:
                        DeviceDetailsView(
                            viewModel: viewModel,
                            pumpManagerState: viewModel.pumpManagerState,
                            insulinQuantityFormatter: viewModel.insulinQuantityFormatter,
                            getBatteryLevel: viewModel.getBatteryLevel)
                        .environment(\.allowDebugFeatures, allowDebugFeatures)
                        .environment(\.insulinTintColor, insulinTintColor)
                        .environment(\.guidanceColors, guidanceColors)
        ) {
            FrameworkLocalizedText("Pump Details", comment: "Description label for device details in pump settings")
        }
        
        pumpTimeSubSection
            .disabled(viewModel.insulinDeliveryDisabled)
    }
    
    private var replacePumpSubSection: some View {
        Section {
            Button(action: viewModel.replacePartsSelected) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        FrameworkLocalizedText("Replace Pump", comment: "Button to replace pump")
                            .foregroundColor(.accentColor)
                            .padding(.bottom, 2)
                    }
                }
                Spacer()
                Image.disclosureIndicator
            }
        }
    }

    private var notificationSubSection: some View {
        Section {
            NavigationLink(destination:
                            NotificationSettingsView(
                                expiryWarningDuration: viewModel.expiryWarningDuration,
                                allowedExpiryWarningDurations: viewModel.allowedExpiryWarningDurations,
                                expiryReminderRepeat: viewModel.expiryReminderRepeat,
                                lowReservoirWarningThresholdInUnits: viewModel.lowReservoirWarningThresholdInUnits,
                                allowedLowReservoirWarningThresholdsInUnits: viewModel.allowedLowReservoirWarningThresholdsInUnits,
                                insulinQuantityFormatter: viewModel.insulinQuantityFormatter,
                                onSaveExpiryWarningDuration: viewModel.saveExpiryWarningDuration,
                                onSaveLowReservoirWarning: viewModel.saveLowReservoirWarningThreshold)
                            .environment(\.allowDebugFeatures, allowDebugFeatures)
            ) {
                FrameworkLocalizedText("Notification Settings", comment: "Description label for notification settings in pump settings")
            }
        }
    }

    private var pumpTimeSubSection: some View {
        Section(footer: pumpTimeSubSectionFooter) {
            HStack {
                FrameworkLocalizedText("Pump Time", comment: "The title of the command to change pump time zone")
                    .foregroundColor(viewModel.insulinDeliveryDisabled ? .secondary : viewModel.canSynchronizePumpTime ? .primary : guidanceColors.critical)
                Spacer()
                if viewModel.isClockOffset {
                    Image(systemName: "clock.fill")
                        .foregroundColor(viewModel.insulinDeliveryDisabled ? .secondary : guidanceColors.warning)
                }
                TimeView(timeOffset: viewModel.detectedSystemTimeOffset, timeZone: viewModel.timeZone)
                    .foregroundColor(viewModel.insulinDeliveryDisabled ? .secondary : viewModel.isClockOffset ? guidanceColors.warning : nil)
            }
            if viewModel.synchronizingTime {
                HStack {
                    FrameworkLocalizedText("Adjusting Pump Time...", comment: "Text indicating ongoing pump time synchronization")
                        .foregroundColor(.secondary)
                    Spacer()
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                }
            } else if self.viewModel.timeZone != TimeZone.currentFixed,
                      viewModel.canSynchronizePumpTime
            {
                Button(action: {
                    showSyncTimeOptions = true
                }) {
                    FrameworkLocalizedText("Sync to Current Time", comment: "The title of the command to change pump time zone")
                }
                .actionSheet(isPresented: $showSyncTimeOptions) {
                    syncPumpTimeActionSheet
                }
            }
        }
    }

    @ViewBuilder
    private var pumpTimeSubSectionFooter: some View {
        if !viewModel.canSynchronizePumpTime {
            FrameworkLocalizedText("When the device time is manually set, Tidepool Loop will not synchronize the pump time to the device time.", comment: "Description for why the pump time is not synchronized")
        }
    }

    private var deletePumpManagerSection: some View {
        Section {
            Button(action:{
                displayDeleteWarning = true
            }) {
                FrameworkLocalizedText("Delete Pump", comment: "Delete Pump Manager button title")
                    .foregroundColor(guidanceColors.critical)
            }
            .sheet(isPresented: $displayDeleteWarning) {
                deleteWarning
            }
        }
    }
    
    private var deleteWarning: some View {
        AdditionalDescriptionView(title: LocalizedString("Delete Pump", comment: "Title of additional description for deleting the Pump manager"),
                                  boldedMessage: LocalizedString("This will disconnect from your existing pump and delete all the pump settings. In order to use a pump, you will need to complete the setup process again.", comment: "Warning for deleting the pump manager"),
                                  additionalDescription: LocalizedString("Do not use this to replace a Insulin Delivery pump. If you are looking to replace a Insulin Delivery pump, select replace pump in settings.", comment: "Description for deleting the pump manager"),
                                  confirmButtonTitle: LocalizedString("Delete pump", comment: "Confirmation button title"),
                                  confirmButtonType: .destructive,
                                  confirmAction: { shouldDeletePumpManager = true },
                                  displayCancelButton: true)
            .onDisappear() {
                if shouldDeletePumpManager {
                    viewModel.deletePumpManagerHandler?() { error in
                        if let error = error {
                            self.presentedAlert = .cannotDeletePumpManager(error)
                            self.shouldDeletePumpManager = false
                        }
                    }
                }
            }
    }
    
    private var doneButton: some View {
        Button(LocalizedString("Done", comment: "Settings done button label"), action: {
            viewModel.dismissSettings()
        })
    }

    var syncPumpTimeActionSheet: ActionSheet {
       ActionSheet(title: FrameworkLocalizedText("Time Change Detected", comment: "Title for pump sync time action sheet."), message: FrameworkLocalizedText("The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?", comment: "Message for pump sync time action sheet"), buttons: [
          .default(FrameworkLocalizedText("Yes, Sync to Current Time", comment: "Button text to confirm pump time sync")) {
              self.viewModel.changeTimeZoneTapped() { error in
                  if let error = error {
                      self.presentedAlert = .syncTimeError(error)
                  }
              }
          },
          .cancel(FrameworkLocalizedText("No, Keep Pump As Is", comment: "Button text to cancel pump time sync"))
       ])
    }

    private func alert(for presentedAlert: PresentedAlert) -> SwiftUI.Alert {
        switch presentedAlert {
        case .suspendInsulinDeliveryError(let error):
            return Alert(
                title: FrameworkLocalizedText("Failed to Suspend Insulin Delivery", comment: "Alert title for error when suspending insulin delivery"),
                message: Text(message(forError: error))
            )
        case .resumeInsulinDeliveryError(let error):
            return Alert(
                title: FrameworkLocalizedText("Failed to Resume Insulin Delivery", comment: "Alert title for error when starting insulin delivery"),
                message: Text(message(forError: error))
            )
        case .syncTimeError(let error):
            return SwiftUI.Alert(
               title: FrameworkLocalizedText("Failed to Set Pump Time", comment: "Alert title for time sync error"),
               message: Text(message(forError: error))
            )
        case .cannotDeletePumpManager(let error):
            return SwiftUI.Alert(
               title: FrameworkLocalizedText("Failed to delete pump manager", comment: "Alert title for cannot delete pump manager error"),
               message: Text(message(forError: error))
            )
        }
    }
    
    private func message(forError error: Error) -> String {
        if let localizedError = error as? LocalizedError {
            return localizedError.message
        } else {
            return error.localizedDescription
        }
    }
}

extension SettingsView.PresentedAlert: Identifiable {
    var id: Int {
        switch self {
        case .resumeInsulinDeliveryError:
            return 0
        case .suspendInsulinDeliveryError:
            return 1
        case .syncTimeError:
            return 2
        case .cannotDeletePumpManager:
            return 3
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0)])!
        let deviceInformation =  DeviceInformation(identifier: UUID(),
                                                   serialNumber: "SerialNumber",
                                                   firmwareRevision: "f1.2.3.4",
                                                   hardwareRevision: "h4.3.2.1",
                                                   batteryLevel: 100,
                                                   reportedRemainingLifetime: InsulinDeliveryPumpManager.lifespan)
        let pumpManagerState = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule,
                                                        maxBolusUnits: 10.0,
                                                        pumpState: IDPumpState(deviceInformation: deviceInformation))
        let pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState)
        let viewModel = SettingsViewModel(pumpManager: pumpManager, navigator: MockNavigator(), completionHandler: { })
        return Group {
            SettingsView(viewModel: viewModel)
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE"))
                .previewDisplayName("SE light")
            SettingsView(viewModel: viewModel)
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS Max"))
                .previewDisplayName("XS Max dark")
        }
    }
}

extension LocalizedError {
    var message: String {
        var message = ""
        
        if let errorDescription {
            message = errorDescription
        }
        
        if let failureReason {
            if message.isEmpty == true {
                message = failureReason
            } else {
                message.append("\n\n\(failureReason)")
            }
        }
        
        if let recoverySuggestion {
            if message.isEmpty == true {
                message = recoverySuggestion
            } else {
                message.append("\n\n\(recoverySuggestion)")
            }
        }
        
        return message
    }
}
