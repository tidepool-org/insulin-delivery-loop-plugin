//
//  PendingInsulinDeliveryCommand.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2022-03-29.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation

struct PendingInsulinDeliveryCommand: RawRepresentable, Equatable {
    typealias RawValue = [String: Any]

    enum PendingInsulinDeliveryCommandKey: String {
        case commandType
        case commandDate
    }

    enum CommandType: Codable, Equatable {
        case bolus(Double)
        case cancelBolus
        case cancelTempBasal
        case resumeInsulinDelivery
        case suspendInsulinDelivery
        case tempBasal(Double, TimeInterval)
    }

    let type: CommandType
    let date: Date

    init(type: CommandType, date: Date = Date()) {
        self.type = type
        self.date = date
    }

    init?(rawValue: RawValue) {
        guard let rawCommandType = rawValue[PendingInsulinDeliveryCommandKey.commandType.rawValue] as? Data,
              let commandType = try? PropertyListDecoder().decode(CommandType.self, from: rawCommandType),
              let commandDate = rawValue[PendingInsulinDeliveryCommandKey.commandDate.rawValue] as? Date
        else {
            return nil
        }

        self.type = commandType
        self.date = commandDate
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [:]

        rawValue[PendingInsulinDeliveryCommandKey.commandDate.rawValue] = date
        if let rawCommandType = try? PropertyListEncoder().encode(type) {
            rawValue[PendingInsulinDeliveryCommandKey.commandType.rawValue] = rawCommandType
        }

        return rawValue
    }
}
