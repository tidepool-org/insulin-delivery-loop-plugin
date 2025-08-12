//
//  MockPumpSettingsView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKitUI
import InsulinDeliveryLoopKit
import InsulinDeliveryServiceKit

struct MockPumpSettingsView: View {
    @Environment(\.presentationMode) var presentationMode

    @StateObject var viewModel: MockPumpSettingsViewModel

    var body: some View {
        Form {
            Section(header: SectionHeader(label: "Connectivity")) {
                Toggle(isOn: $viewModel.disconnectComms) {
                   Text("Disconnect Comms")
                }
                Toggle(isOn: $viewModel.uncertainDeliveryEnabled) {
                   Text("Uncertain Delivery")
                }
                Toggle(isOn: $viewModel.uncertainDeliveryCommandReceived) {
                    Text("Command Received")
                        .foregroundColor(viewModel.uncertainDeliveryEnabled ? .primary : .secondary)
                }.disabled(!viewModel.uncertainDeliveryEnabled)
            }

            Section(header: SectionHeader(label: "Alerts")) {
                mockPumpIssueAlert
            }

            stoppedNotificationTimeDelaySection

            Section(header: SectionHeader(label: "Simulate Errors")) {
                MockPumpErrorPickerView(title: "Error On Next Comms", error: $viewModel.errorOnNextComms)
                MockPumpErrorPickerView(title: "Authentication Error", error: $viewModel.authenticationError)
            }

            Section(header: SectionHeader(label: "Simulate Replacement")) {
                DatePicker("Pump",
                           selection: Binding(get: { viewModel.fakePumpReplacementDate ?? Date() },
                                              set: { viewModel.fakePumpReplacementDate =  $0 }))
            }

            Section(header: SectionHeader(label: "Reservoir Remaining")) {
                reservoirRemainingEntry
            }
            
            Section(header: SectionHeader(label: "Battery Percent")) {
                batteryPercentEntry
            }

            if viewModel.isDeliveringInsulin {
                Section(header: SectionHeader(label: "Insulin Delivery")) {
                    Toggle(isOn: $viewModel.causeInsulinDeliveryInterruption) {
                        Text("Cause insulin delivery interruption")
                    }
                }

                Section(header: SectionHeader(label: "Bolus")) {
                    if viewModel.isBolusActive {
                        Text("Bolus In Progress")
                        Toggle(isOn: $viewModel.causeBolusInterruption) {
                            Text("Cause bolus interruption")
                        }
                    }
                }

                Section(header: SectionHeader(label: "Basal")) {
                    if viewModel.isTempBasalActive {
                        Text("Temp Basal In Progress")
                        Toggle(isOn: $viewModel.causeTempBasalInterruption) {
                            Text("Cause temp basal interruption")
                        }
                    } else {
                        Text("Scheduled Basal In Progress")
                    }
                }
            } else {
                Section(header: SectionHeader(label: "Insulin Delivery")) {
                    Text("Insulin Delivery is Suspended")
                }
            }
        }
        .onAppear {
            viewModel.updateState()
        }
        .navigationBarTitle("Mock Insulin Delivery Pump")
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: backButton)
    }
    
    struct MockPumpErrorPickerView<T: SimulatedError>: View {
        let title: String
        @Binding var error: T
        
        var body: some View {
            HStack {
                Text(title)
                Spacer()
                Picker(title, selection: $error) {
                    ForEach(T.allCases, id: \.self) { e in
                        Text(e.rawValue)
                            .tag(e)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var backButton: some View {
        BackButton {
            viewModel.commitUpdatedSettings()
            self.presentationMode.wrappedValue.dismiss()
        }
    }
    
    var reservoirRemainingEntry: some View {
        return MockPumpReservoirRemainingEntryView(reservoirRemaining: $viewModel.reservoirString)
    }

    struct MockPumpReservoirRemainingEntryView: View {
        @Binding var reservoirRemaining: String

        var body: some View {
            // TextField only updates continuously as the user types if the value is a String
            TextField("Enter reservoir remaining value",
                      text: $reservoirRemaining)
                .keyboardType(.decimalPad)
        }
    }
    
    var batteryPercentEntry: some View {
        return MockPumpBatteryPercentEntryView(batteryLevel: $viewModel.batteryLevelString)
    }

    struct MockPumpBatteryPercentEntryView: View {
        @Binding var batteryLevel: String

        var body: some View {
            // TextField only updates continuously as the user types if the value is a String
            TextField("Enter battery percent value",
                      text: $batteryLevel)
                .keyboardType(.numberPad)
        }
    }
    
    private var stoppedNotificationTimeDelaySection: some View {
        Section(footer: Text("Time delay before issuing a \"Pump Stopped\" Notification after Insulin Delivery stops")) {
            MockPumpStoppedNotificationEntryView(title: "Time delay", delay: $viewModel.stoppedNotificationDelay)
                .animation(nil)
        }
    }

    struct MockPumpStoppedNotificationEntryView: View {
        let title: String
        @Binding var delay: TimeInterval
        @State var isEditing: Bool = false
        var body: some View {
            ExpandableSetting(isEditing: $isEditing,
                              leadingValueContent: {
                Text(title)
            },
                              trailingValueContent: {
                Text(RelativeDateTimeFormatter().localizedString(fromTimeInterval: delay))
            },
                              expandedContent: {
                DurationPicker(duration: $delay, validDurationRange: TimeInterval.minutes(1)...TimeInterval.hours(1), minuteInterval: 1)
            }
                              )
        }
    }
    
    private var mockPumpIssueAlert: some View {
        MockPumpIssueAlertView(delaySeconds: $viewModel.annunciationTypeToIssueDelay,
                               alert: $viewModel.annunciationTypeToIssue)
    }

    struct MockPumpIssueAlertView: View {
        @Binding var delaySeconds: TimeInterval
        @Binding var alert: AnnunciationType?
        
        var body: some View {
            HStack {
                Text("After")
                Picker("", selection: $delaySeconds) {
                    ForEach(Array(stride(from: 5.0, to: 30.0.nextUp, by: 5.0)), id: \.self) {
                        Text("\(Int($0))")
                    }
                }
                .pickerStyle(.menu)
                Picker("seconds, issue alert:", selection: $alert) {
                    ForEach(annunciations, id: \.self) { annunciation in
                        Text(pickerValue(for: annunciation)).tag(annunciation)
                    }
                }
            }
        }
        
        private func pickerValue(for annunciation: AnnunciationType?) -> String {
            guard let annunciation = annunciation else {
                return "none"
            }

            return "\(annunciation.description)"
        }
        
        private var annunciations: [AnnunciationType?] {
            [nil] + AnnunciationType.allCases
        }
    }
    
}

struct MockPumpSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        MockPumpSettingsView(viewModel: MockPumpSettingsViewModel())
    }
}
