//
//  PumpExpiryWarningEditView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import LoopKitUI
import SwiftUI

struct PumpExpiryWarningEditView: View {
    enum PresentationMode {
        case onboarding
        case settings
    }
    
    typealias ExpiryReminderRepeat = SettingsViewModel.ExpiryReminderRepeat
    
    @State private var selectedValue: TimeInterval
    @State private var expiryReminderRepeat: ExpiryReminderRepeat

    private let initialValue: (TimeInterval, ExpiryReminderRepeat)
    let timeFormatter: DateComponentsFormatter
    let allowedDurations: [TimeInterval]
    let showInstructionalContent: Bool
    var onSave: SettingsViewModel.ExpirySaveCompletion?
    var onFinish: (() -> Void)?
    var onPause: (() -> Void)?
    var presentationMode: PresentationMode

    init(expiryWarningDuration: TimeInterval,
         allowedDurations: [TimeInterval],
         showInstructionalContent: Bool,
         expiryReminderRepeat: ExpiryReminderRepeat,
         timeFormatter: DateComponentsFormatter,
         presentationMode: PresentationMode = .settings,
         onSave: SettingsViewModel.ExpirySaveCompletion? = nil,
         onPause: (() -> Void)? = nil,
         onFinish: (() -> Void)? = nil)
    {
        self.initialValue = (expiryWarningDuration, expiryReminderRepeat)
        self.allowedDurations = allowedDurations
        self.showInstructionalContent = showInstructionalContent
        self.timeFormatter = timeFormatter
        self.presentationMode = presentationMode
        self.onSave = onSave
        self.onPause = onPause
        self.onFinish = onFinish
        self._expiryReminderRepeat = State(initialValue: expiryReminderRepeat)
        self._selectedValue = State(initialValue: expiryWarningDuration)
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
            onSave?(selectedValue, expiryReminderRepeat)
            onPause?()
        }) {
            FrameworkLocalizedText("Close", comment: "Button title for suspending onboarding during pump expiry warning edit")
        }
    }


    private var cancelButton: some View {
        Button(action: {
            onFinish?()
        }) {
            FrameworkLocalizedText("Cancel", comment: "Button title for cancelling pump expiry warning edit")
        }
    }

    var content: some View {
        VStack {
            RoundedCardScrollView(title: LocalizedString("Pump Expiration", comment: "Title for pump expiry warning edit page")) {
                if showInstructionalContent {
                    instructionalContent
                }
                warningValueEditor
                repeatReminderEditor
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
            FixedHeightText(LocalizedString("Set your pump expiration warning", comment: "PumpExpiryWarningEditView instructional content header"))
                .font(.headline)
                .padding(.bottom, 1)
            FixedHeightText(LocalizedString("Set to receive warning and reminder alerts when your pump is nearing expiration. Scroll to set the number of days before expiration you would like to be notified and the frequency of expiration reminders.", comment: "PumpExpiryWarningEditView instructional content body"))
                .font(.footnote)
        }
    }


    @ViewBuilder
    private var warningValueEditor: some View {
        RoundedCard(footer: footerText) {
            ExpandableSetting(
                isEditing: .constant(true),
                leadingValueContent: {
                    FrameworkLocalizedText("Expiration Warning", comment: "Label of pump expiration warning row")
                },
                trailingValueContent: {
                    Text(timeFormatter.string(from: selectedValue) ?? "")
                        .foregroundColor(.accentColor)
                },
                expandedContent: { picker }
            )
        }
    }
    
    private var footerText: String {
        LocalizedString("The app will notify you to replace your pump. Select how many days before expiration you would like to be notified. This notification may not be turned off.", comment: "Description for pump expiration warning editor")
    }

    private var picker: some View {
        Picker(selection: $selectedValue) {
            ForEach(allowedDurations, id: \.self) { value in
                Text(self.timeFormatter.string(from: value) ?? "Time Format Error")
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.wheel)
    }
    
    struct PumpExpiryReminderEditView: View {
        @Binding var expiryReminderRepeat: ExpiryReminderRepeat
        
        var body: some View {
            SingleSelectionCheckListView(
                footer: LocalizedString("""
                    By selecting Daily, the app will remind you every day following the initial warning message until the pump is due to expire.
                    
                    By selecting Day Before, the app will remind you one day before the pump is due to expire.
                    """, comment: "Footer text for Repeat Reminders Edit View"),
                items: ExpiryReminderRepeat.allCases,
                selectedItem: $expiryReminderRepeat
            )
            // Note: this used to have `.padding(.top)` here but unfortunately the wrong background color shows in the navigation title area, but in Dark Mode, as a result.
            .navigationTitle(LocalizedString("Repeat Reminders", comment: "Title for Repeat Reminders Edit View"))
        }
    }
       
    @ViewBuilder
    private var repeatReminderEditor: some View {
        RoundedCard(footer: LocalizedString("Set additional reminders following the initial warning message to receive notifications about the pump’s expiration.", comment: "Footer text for repeat reminder card")) {
            NavigationLink(destination: PumpExpiryReminderEditView(expiryReminderRepeat: $expiryReminderRepeat)) {
                RoundedCardValueRow(
                    label: LocalizedString("Repeat Reminder", comment: "Repeat reminder value label"),
                    value: expiryReminderRepeat.description,
                    highlightValue: false,
                    disclosure: true
                )
            }
        }
    }

    private var saveButtonText: String {
        if presentationMode == .onboarding {
            return LocalizedString("Continue", comment: "Button title for continuing when expiry warning time not modified")
        } else {
            return LocalizedString("Save", comment: "Button title for saving expiry warning time")
        }
    }

    private func saveTapped() {
        if valueChanged {
            // Presentation of an expiration alert that is associated with changing this value may impact
            // dismissal of the dialog, so we delay a bit. 
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onSave?(selectedValue, expiryReminderRepeat)
            }
        }
        self.onFinish?()
    }

    private var valueChanged: Bool {
        return (selectedValue, expiryReminderRepeat) != initialValue
    }
}

struct ExpiryWarningDurationEditView_Previews: PreviewProvider {
    static var previews: some View {
        var allowedDurations: [TimeInterval] = []
        for days in 4...30 {
            allowedDurations.append(.days(days))
        }
        let timeFormatter = DateComponentsFormatter()
        timeFormatter.unitsStyle = .full
        timeFormatter.allowedUnits = [.day]

        return ContentPreview {
            PumpExpiryWarningEditView(
                expiryWarningDuration: .days(10),
                allowedDurations: allowedDurations,
                showInstructionalContent: true,
                expiryReminderRepeat: .daily,
                timeFormatter: timeFormatter)
        }
    }
}
