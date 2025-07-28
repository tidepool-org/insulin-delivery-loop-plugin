//
//  OpenVirtualPumpSettingsOnLongPressGesture.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Rick Pasetto on 3/11/22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import InsulinDeliveryLoopKit

extension View {
    func openVirtualPumpSettingsOnLongPress(enabled: Bool = true, minimumDuration: Double = 5, _ virtualPump: VirtualInsulinDeliveryPump?) -> some View {
        modifier(OpenVirtualPumpSettingsOnLongPressGesture(enabled: enabled, minimumDuration: minimumDuration, virtualPump: virtualPump, pumpManager: nil))
    }
    func openVirtualPumpSettingsOnLongPress(enabled: Bool = true, minimumDuration: Double = 5, pumpManager: InsulinDeliveryPumpManager) -> some View {
        modifier(OpenVirtualPumpSettingsOnLongPressGesture(enabled: enabled, minimumDuration: minimumDuration, virtualPump: nil, pumpManager: pumpManager))
    }
}

fileprivate struct OpenVirtualPumpSettingsOnLongPressGesture: ViewModifier {
    private let enabled: Bool
    private let minimumDuration: TimeInterval
    private let virtualPump: VirtualInsulinDeliveryPump?
    private let pumpManager: InsulinDeliveryPumpManager?
    @State private var mockPumpSettingsDisplayed = false

    init(enabled: Bool, minimumDuration: Double, virtualPump: VirtualInsulinDeliveryPump? = nil, pumpManager: InsulinDeliveryPumpManager? = nil) {
        self.enabled = enabled
        self.minimumDuration = minimumDuration
        self.virtualPump = virtualPump ?? pumpManager?.getVirtualPump()
        self.pumpManager = pumpManager
    }

    func body(content: Content) -> some View {
        if let virtualPump = virtualPump, enabled {
            modifiedContent(content: content, virtualPump: virtualPump)
        } else {
            content
        }
    }
    
    func modifiedContent(content: Content, virtualPump: VirtualInsulinDeliveryPump) -> some View {
        ZStack {
            content
                .onLongPressGesture(minimumDuration: minimumDuration) {
                    mockPumpSettingsDisplayed = true
                }
            NavigationLink(destination: MockPumpSettingsView(viewModel: MockPumpSettingsViewModel(virtualPump: virtualPump, pumpManager: pumpManager)), isActive: $mockPumpSettingsDisplayed) {
                EmptyView()
            }
            .opacity(0) // <- Hides the Chevron
            .buttonStyle(PlainButtonStyle())
            .disabled(true)
        }
    }
}

