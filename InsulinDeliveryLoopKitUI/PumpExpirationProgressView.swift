//
//  ComponentExpirationProgressView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import InsulinDeliveryLoopKit

struct PumpExpirationProgressView: View {
    @Environment(\.guidanceColors) var guidanceColors
    @Environment(\.insulinTintColor) var insulinTintColor
    
    @ObservedObject var viewModel: PumpExpirationProgressViewModel
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            componentImage
            expirationArea
                .disabled(viewModel.isInsulinSuspended)
                .offset(y: -3)
        }
    }
    
    var componentImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(frameworkColor: "LightGrey")!)
                .frame(width: 77, height: 76)
            Image(frameworkImage: "pump-simulator")
                .resizable()
                .aspectRatio(contentMode: ContentMode.fit)
                .frame(maxHeight: 70)
                .frame(width: 70)
        }
    }
    
    var expirationArea: some View {
        VStack(alignment: .leading) {
            expirationText
                .offset(y: 4)
            expirationTime
                .offset(y: 10)
            progressBar
        }
    }
    
    var expirationText: some View {
        Text(viewModel.expirationString)
            .font(.system(size: 15, weight: .medium, design: .default))
            .foregroundColor(viewModel.isExpired ? guidanceColors.critical : .secondary)
    }
    
    var expirationTime: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(viewModel.expirationTimeTuple.interval)
                .font(.system(size: 24, weight: .heavy, design: .default))
                .foregroundColor(expirationTimeColor)
            Text(viewModel.expirationTimeTuple.units)
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundColor(.secondary)
                .offset(x: -3)
        }
    }
    
    var expirationTimeColor: Color {
        switch viewModel.expirationTimeColor {
        case .critical:
            return guidanceColors.critical
        case .warning:
            return guidanceColors.warning
        case .normal:
            return .primary
        case .dimmed:
            return .secondary
        }
    }
    
    var progressBar: some View {
        ExpirationProgressBar(value: viewModel.expirationProgress)
    }
    
    struct ExpirationProgressBar: View {
        @Environment(\.guidanceColors) var guidanceColors
        @Environment(\.insulinTintColor) var insulinTintColor

        var value: DeviceLifecycleProgress?
        
        var body: some View {
            content
                .accentColor(progressBarColor)
        }
        @ViewBuilder
        private var content: some View {
            progressView
        }
        private var progressView: some View {
            ProgressView(progress: value?.percentComplete ?? 0.0)
        }
        
        var progressBarColor: Color {
            switch value?.progressState {
            case .critical:
                return guidanceColors.critical
            case .warning:
                return guidanceColors.warning
            case .normalPump:
                return insulinTintColor
            case .dimmed:
                return .secondary
            default:
                return .secondary
            }
        }
    }
    
}
