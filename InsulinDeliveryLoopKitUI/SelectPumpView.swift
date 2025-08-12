//
//  SelectPumpView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKitUI
import InsulinDeliveryLoopKit

struct SelectPumpView: View, HorizontalSizeClassOverride {
    @Environment(\.guidanceColors) var guidanceColors

    @ObservedObject var viewModel: WorkflowViewModel

    @State private var showFindSerialNumberInstructions = false

    var body: some View {
        VStack {
            selectPump
            Spacer()
            actionContent
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: CancelWorkflowWarningButton(viewModel: viewModel))
        .edgesIgnoringSafeArea(.bottom)
    }

    private var selectPump: some View {
        RoundedCardScrollView(title: LocalizedString("Select Pump", comment: "Title for select pump page")) {
            instructions
            if viewModel.hasDetectedDevices {
                pumpListCard
            } else {
                noPumpsDetectedCard
            }
        }
    }

    private var instructions: some View {
        RoundedCardTitle(LocalizedString("Tap to select the pump with the correct serial number.", comment: "Instructions on how to select the pump."))
            .padding(.bottom)
    }

    private var pumpListCard: some View {
        RoundedCard {
            pumpList
        }
    }

    @ViewBuilder
    private var pumpList: some View {
        ForEach(viewModel.devices) { device in
            SelectableDevice(device: device, selectedDeviceSerialNumber: $viewModel.selectedDeviceSerialNumber)
        }
    }

    private var noPumpsDetectedCard: some View {
        RoundedCard(alignment: .center) {
            noPumpsDetectedWarning
            noPumpsHelperText
            noPumpsImage
        }
    }

    private var noPumpsDetectedWarning: some View {
        HStack {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(guidanceColors.warning)
            FrameworkLocalizedText("No pumps located", comment: "Message when no pumps have been detected")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }

    private var noPumpsHelperText: some View {
        FrameworkLocalizedText("Move your device closer to the pump and try again.", comment: "Helper text when no pumps are detected")
            .font(.caption)
            .multilineTextAlignment(.center)
    }

    private var noPumpsImage: some View {
        Image(systemName:"wifi")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 200)
            .foregroundStyle(Color.secondary)
            .padding()
    }

    private var actionContent: some View {
        VStack {
            if !viewModel.deviceSelected {
                progressView
            }
            continueButton
        }
        .background(Color(UIColor.systemBackground).shadow(radius: 5))
    }

    private var progressView: some View {
        VStack {
            HStack { Spacer () }
            ProgressIndicatorView(state: .indeterminantProgress)
                .padding(.horizontal)
        }
        .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
    }

    private var continueButton: some View {
        Button(action: viewModel.connectToSelectedDevice) {
            FrameworkLocalizedText("Continue", comment: "Continue setup button")
                .actionButtonStyle()
        }
        .disabled(!viewModel.deviceSelected)
        .padding()
    }
}

struct SelectPumpView_Previews: PreviewProvider {
    static var previews: some View {
        let pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        let pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState)
        let viewModel = WorkflowViewModel(pumpWorkflowHelper: pumpManager,
                                          navigator: MockNavigator())
        return Group {
            SelectPumpView(viewModel: viewModel)
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE"))
                .previewDisplayName("SE light")
            
            SelectPumpView(viewModel: viewModel)
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS Max"))
                .previewDisplayName("XS Max dark")
        }
    }
}
