//
//  AlertSound.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-12.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit

public enum AlertSound: String, Codable, CaseIterable {
    case vibrate = "Vibrate"
    case `default` = "Default"
    case error = "Error"
    case maintenance = "Maintenance"
    case warning = "Warning"
}

// TODO need new sounds
public extension AlertSound {
    var filename: String? {
        switch self {
        case .vibrate, .`default`: return nil
        case .error:
            return "03_Tidepool_Error_Mn_+3dB.wav"
        case .maintenance:
            return "02_Tidepool_Maintenance_Mn_+3dB.wav"
        case .warning:
            return "01_Tidepool_Warning_Mn_+6dB.wav"
        }
    }
}

public extension Alert.Sound {
    init?(from sound: AlertSound) {
        switch sound {
        case .vibrate: self = .vibrate
        case .`default`: return nil
        case .error, .maintenance, .warning:
            guard let filename = sound.filename else { return nil }
            self = .sound(name: filename)
        }
    }
}
