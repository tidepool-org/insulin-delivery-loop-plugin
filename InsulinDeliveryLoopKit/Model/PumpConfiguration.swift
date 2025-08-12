//
//  PumpConfiguration.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2021-09-23.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation

public struct PumpConfiguration: Equatable, Codable {
    
    public var bolusMaximum: Double
    
    public var expiryWarningDuration: TimeInterval

    public var reservoirLevelWarningThresholdInUnits: Int

    public init(bolusMaximum: Double,
                expiryWarningDuration: TimeInterval,
                reservoirLevelWarningThresholdInUnits: Int)
    {
        self.bolusMaximum = bolusMaximum
        self.expiryWarningDuration = expiryWarningDuration
        self.reservoirLevelWarningThresholdInUnits = reservoirLevelWarningThresholdInUnits
    }

    var allowedExpiryWarningDurations: [TimeInterval] {
        var allowedDurations: [TimeInterval] = []
        for days in 1...4 {
            allowedDurations.append(.days(days))
        }
        return allowedDurations
    }

    var allowedLowReservoirWarningThresholdsInUnits: [Int] {
        Array(stride(from: 5, through: 40, by: 5))
    }
    
    public static var defaultConfiguration: PumpConfiguration {
        PumpConfiguration(bolusMaximum: 10,
                          expiryWarningDuration: .days(1),
                          reservoirLevelWarningThresholdInUnits: 20)
    }

    public static var newPumpConfiguration: PumpConfiguration {
        PumpConfiguration(bolusMaximum: 0,
                          expiryWarningDuration: 0,
                          reservoirLevelWarningThresholdInUnits: 0)
    }
}
