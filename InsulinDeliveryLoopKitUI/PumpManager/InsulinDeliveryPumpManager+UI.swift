//
//  InsulinDeliveryPumpManager+UI.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2020-03-13.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import UIKit
import SwiftUI
import LoopKit
import LoopKitUI
import InsulinDeliveryLoopKit

extension InsulinDeliveryPumpManager: PumpManagerUI {

    public static var onboardingImage: UIImage? {
        return UIImage(named: "pump-simulator", in: Bundle(for: WorkflowViewModel.self), compatibleWith: nil)
    }

    // TODO handle allowedInsulinTypes
    public static func setupViewController(initialSettings settings: PumpManagerSetupSettings, bluetoothProvider: BluetoothProvider, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool, prefersToSkipUserInteraction: Bool, allowedInsulinTypes: [InsulinType]) -> SetupUIResult<PumpManagerViewController, PumpManagerUI> {
        
        if prefersToSkipUserInteraction,
           let manager = self.init(state: InsulinDeliveryPumpManagerState(basalRateSchedule: settings.basalSchedule, maxBolusUnits: settings.maxBolusUnits)) as? MockInsulinDeliveryPumpManager
        {
            manager.acceptDefaultsAndSkipOnboarding()
            return .createdAndOnboarded(manager)
        } else {
            let vc = IDSViewCoordinator(colorPalette: colorPalette,
                                        pumpManagerType: self,
                                        basalSchedule: settings.basalSchedule,
                                        maxBolusUnits: settings.maxBolusUnits,
                                        allowDebugFeatures: allowDebugFeatures)
            return .userInteractionRequired(vc)
        }
    }

    public func settingsViewController(bluetoothProvider: BluetoothProvider, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool, allowedInsulinTypes: [InsulinType]) -> PumpManagerViewController {
        return IDSViewCoordinator(pumpManager: self, colorPalette: colorPalette, allowDebugFeatures: allowDebugFeatures)
    }

    public func deliveryUncertaintyRecoveryViewController(colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) -> (UIViewController & CompletionNotifying) {
        return IDSViewCoordinator(pumpManager: self, colorPalette: colorPalette, allowDebugFeatures: allowDebugFeatures)
    }
    
    public var smallImage: UIImage? {
        return UIImage(named: "pump-simulator", in: Bundle(for: WorkflowViewModel.self), compatibleWith: nil)
    }

    public func hudProvider(bluetoothProvider: BluetoothProvider, colorPalette: LoopUIColorPalette, allowedInsulinTypes: [InsulinType]) -> HUDProvider? {
        return InsulinDeliveryHUDProvider(pumpManager: self, bluetoothProvider: bluetoothProvider, colorPalette: colorPalette, allowedInsulinTypes: allowedInsulinTypes)
    }
    
    public static func createHUDView(rawValue: [String: Any]) -> BaseHUDView? {
        return InsulinDeliveryHUDProvider.createHUDView(rawValue: rawValue)
    }
}

extension InsulinDeliveryPumpManager: InsulinDeliveryPumpManagerStatePublisher { }

// MARK: - PumpStatusIndicator
extension InsulinDeliveryPumpManager {
    
    var expirationProgressViewModel: ExpirationProgressViewModel {
        return ExpirationProgressViewModel(statePublisher: self)
    }

    public var pumpLifecycleProgress: DeviceLifecycleProgress? {
        return expirationProgressViewModel.expirationProgress
    }
    
    public var pumpStatusBadge: DeviceStatusBadge? {
        return insulinDeliveryPumpStatusBadge
    }

}

extension InsulinDeliveryPumpStatusBadge: DeviceStatusBadge {
    public var image: UIImage? {
        switch self {
        case .lowBattery:
            return UIImage(frameworkImage: "battery.circle.fill")
        case .timeSyncNeeded:
            return UIImage(systemName: "clock.fill")
        }
    }
    
    public var state: DeviceStatusBadgeState {
        switch self {
        case .lowBattery:
            return .warning
        case .timeSyncNeeded:
            return .warning
        }
    }
}
