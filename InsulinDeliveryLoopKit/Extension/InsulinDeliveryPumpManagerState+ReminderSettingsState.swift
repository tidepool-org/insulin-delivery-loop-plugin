//
//  InsulinDeliveryPumpManagerState+ReminderSettingsState.swift
//  InsulinDeliveryLoopKit
//
//  Created by Rick Pasetto on 2/16/22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit

extension InsulinDeliveryPumpManagerState {
    public struct NotificationSettingsState {
        static var `default`: Self { Self() }
        
        public enum ExpiryReminderRepeat: String, Codable, CaseIterable {
            static var `default`: Self { .never }
            case daily, dayBefore, never
        }
        
        public var expiryReminderRepeat: ExpiryReminderRepeat
        
        public init() {
            expiryReminderRepeat = .default
        }
    }
}

extension InsulinDeliveryPumpManagerState.NotificationSettingsState: RawRepresentable, Codable, Equatable {
    public typealias RawValue = PumpManager.RawStateValue
    
    private enum NotificationSettingsStateKey: String {
        case expiryReminderRepeat
    }
    
    public var rawValue: RawValue {
        var rawValue: RawValue = [:]
        rawValue[NotificationSettingsStateKey.expiryReminderRepeat.rawValue] = self.expiryReminderRepeat.rawValue
        return rawValue
    }
    
    public init?(rawValue: RawValue) {
        self.expiryReminderRepeat = (rawValue[NotificationSettingsStateKey.expiryReminderRepeat.rawValue] as? ExpiryReminderRepeat.RawValue)
            .flatMap({ ExpiryReminderRepeat(rawValue: $0) }) ?? .default
    }
}
