//
//  InsulinDeliveryHUDProvider.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2020-08-21.
//  Copyright © 2020 Tidepool Project. All rights reserved.
//

import Foundation
import SwiftUI
import LoopKit
import LoopKitUI
import InsulinDeliveryLoopKit

internal class InsulinDeliveryHUDProvider: NSObject, HUDProvider {
    var managerIdentifier: String {
        return InsulinDeliveryPumpManager.managerIdentifier
    }

    private let pumpManager: InsulinDeliveryPumpManager

    private var reservoirView: ReservoirView?

    private let bluetoothProvider: BluetoothProvider

    private let colorPalette: LoopUIColorPalette

    private let allowedInsulinTypes: [InsulinType]
    
    var visible: Bool = false {
        didSet {
            if oldValue != visible && visible {
                hudDidAppear()
            }
        }
    }

    public init(pumpManager: InsulinDeliveryPumpManager,
                bluetoothProvider: BluetoothProvider,
                colorPalette: LoopUIColorPalette,
                allowedInsulinTypes: [InsulinType])
    {
        self.pumpManager = pumpManager
        self.bluetoothProvider = bluetoothProvider
        self.colorPalette = colorPalette
        self.allowedInsulinTypes = allowedInsulinTypes
        super.init()
        self.pumpManager.addPumpObserver(self, queue: .main)
    }

    public func createHUDView() -> BaseHUDView? {
        reservoirView = ReservoirView.instantiate()
        updateReservoirView()

        return reservoirView
    }

    public func didTapOnHUDView(_ view: BaseHUDView, allowDebugFeatures: Bool) -> HUDTapAction? {
        let vc = pumpManager.settingsViewController(bluetoothProvider: bluetoothProvider, colorPalette: colorPalette, allowDebugFeatures: allowDebugFeatures, allowedInsulinTypes: allowedInsulinTypes)
        return HUDTapAction.presentViewController(vc)
    }

    func hudDidAppear() {
        updateReservoirView()
    }
    
    public var hudViewRawState: HUDProvider.HUDViewRawState {
        var rawValue: HUDProvider.HUDViewRawState = [:]
        
        if let reservoirLevel = pumpManager.reservoirLevel {
            rawValue["reservoirLevel"] = reservoirLevel
        }
        rawValue["reservoirWarningThreshold"] = pumpManager.lowReservoirWarningThresholdInUnits

        return rawValue
    }

    public static func createHUDView(rawValue: HUDProvider.HUDViewRawState) -> BaseHUDView? {
        guard let reservoirLevel = rawValue["reservoirLevel"] as? Double,
            let reservoirWarningThreshold = rawValue["reservoirWarningThreshold"] as? Int else {
            return nil
        }
        
        let reservoirView = ReservoirView.instantiate()
        reservoirView.update(level: reservoirLevel, threshold: reservoirWarningThreshold)
        
        return reservoirView
    }

    private func updateReservoirView() {
        guard let reservoirView = reservoirView else {
            return
        }

        reservoirView.update(level: pumpManager.reservoirLevel, threshold: pumpManager.lowReservoirWarningThresholdInUnits)
    }
}

extension InsulinDeliveryHUDProvider: InsulinDeliveryPumpObserver {
    func pumpDidUpdateState() {
        updateReservoirView()
    }
}
