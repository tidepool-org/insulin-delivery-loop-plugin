//
//  SettingsProvider.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2020-04-28.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit

protocol SettingsProvider: AnyObject {
    var maxBolusUnits: Double? { get set }
    var basalSchedule: BasalRateSchedule? { get set }
    var maxBasalRateUnitsPerHour: Double? { get set }
}
