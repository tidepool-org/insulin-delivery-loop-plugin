//
//  InsulinDeliveryServicesConfiguration.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2020-03-19.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import CoreBluetooth
import BluetoothCommonKit
import InsulinDeliveryServiceKit

extension PeripheralManager.Configuration {
    static var pumpGeneralConfiguration: PeripheralManager.Configuration {
        return PeripheralManager.Configuration(
            serviceCharacteristics: [
                InsulinDeliveryCharacteristicUUID.service.cbUUID: [
                    InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID,
                    InsulinDeliveryCharacteristicUUID.status.cbUUID,
                    InsulinDeliveryCharacteristicUUID.annunciationStatus.cbUUID,
                    InsulinDeliveryCharacteristicUUID.features.cbUUID,
                    InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.commandData.cbUUID,
                    InsulinDeliveryCharacteristicUUID.recordAccessControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.historyData.cbUUID
                ],
                DeviceInfoCharacteristicUUID.service.cbUUID: [
                    DeviceInfoCharacteristicUUID.manufacturerNameString.cbUUID,
                    DeviceInfoCharacteristicUUID.modelNumberString.cbUUID,
                    DeviceInfoCharacteristicUUID.systemID.cbUUID,
                    DeviceInfoCharacteristicUUID.firmwareRevisionString.cbUUID
                ],
                BatteryCharacteristicUUID.service.cbUUID: [
                    BatteryCharacteristicUUID.batteryLevel.cbUUID
                ],
                ImmediateAlertCharacteristicUUID.service.cbUUID: [
                    ImmediateAlertCharacteristicUUID.alertLevel.cbUUID
                ],
                DeviceTimeCharacteristicUUID.service.cbUUID: [
                    DeviceTimeCharacteristicUUID.feature.cbUUID,
                    DeviceTimeCharacteristicUUID.parameters.cbUUID,
                    DeviceTimeCharacteristicUUID.deviceTime.cbUUID,
                    DeviceTimeCharacteristicUUID.controlPoint.cbUUID
                ]
            ],
            notifyingCharacteristics: [
                InsulinDeliveryCharacteristicUUID.service.cbUUID: [
                    InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID,
                    InsulinDeliveryCharacteristicUUID.status.cbUUID,
                    InsulinDeliveryCharacteristicUUID.annunciationStatus.cbUUID,
                    InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.commandData.cbUUID,
                    InsulinDeliveryCharacteristicUUID.recordAccessControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.historyData.cbUUID
                ],
                DeviceTimeCharacteristicUUID.service.cbUUID: [
                    DeviceTimeCharacteristicUUID.controlPoint.cbUUID
                ],
            ],
            valueUpdateMacros: [:],
            willServiceSetChange: false
        )
    }
    
    static var pumpAuthorizationControlConfiguration: PeripheralManager.Configuration {
        return PeripheralManager.Configuration(
            serviceCharacteristics: [
                ACCharacteristicUUID.service.cbUUID: [
                    ACCharacteristicUUID.status.cbUUID,
                    ACCharacteristicUUID.dataIn.cbUUID,
                    ACCharacteristicUUID.dataOutNotify.cbUUID,
                    ACCharacteristicUUID.dataOutIndicate.cbUUID,
                    ACCharacteristicUUID.controlPoint.cbUUID
                ],
                InsulinDeliveryCharacteristicUUID.service.cbUUID: [
                    InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID,
                    InsulinDeliveryCharacteristicUUID.status.cbUUID,
                    InsulinDeliveryCharacteristicUUID.annunciationStatus.cbUUID,
                    InsulinDeliveryCharacteristicUUID.features.cbUUID,
                    InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.commandData.cbUUID,
                    InsulinDeliveryCharacteristicUUID.recordAccessControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.historyData.cbUUID
                ],
                DeviceInfoCharacteristicUUID.service.cbUUID: [
                    DeviceInfoCharacteristicUUID.manufacturerNameString.cbUUID,
                    DeviceInfoCharacteristicUUID.modelNumberString.cbUUID,
                    DeviceInfoCharacteristicUUID.systemID.cbUUID,
                    DeviceInfoCharacteristicUUID.firmwareRevisionString.cbUUID
                ],
                BatteryCharacteristicUUID.service.cbUUID: [
                    BatteryCharacteristicUUID.batteryLevel.cbUUID
                ],
                ImmediateAlertCharacteristicUUID.service.cbUUID: [
                    ImmediateAlertCharacteristicUUID.alertLevel.cbUUID
                ],
                DeviceTimeCharacteristicUUID.service.cbUUID: [
                    DeviceTimeCharacteristicUUID.feature.cbUUID,
                    DeviceTimeCharacteristicUUID.parameters.cbUUID,
                    DeviceTimeCharacteristicUUID.deviceTime.cbUUID,
                    DeviceTimeCharacteristicUUID.controlPoint.cbUUID
                ]
            ],
            notifyingCharacteristics: [
                ACCharacteristicUUID.service.cbUUID: [
                    ACCharacteristicUUID.status.cbUUID,
                    ACCharacteristicUUID.dataOutNotify.cbUUID,
                    ACCharacteristicUUID.dataOutIndicate.cbUUID,
                    ACCharacteristicUUID.controlPoint.cbUUID
                ],
                InsulinDeliveryCharacteristicUUID.service.cbUUID: [
                    InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID,
                    InsulinDeliveryCharacteristicUUID.status.cbUUID,
                    InsulinDeliveryCharacteristicUUID.annunciationStatus.cbUUID,
                    InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.commandData.cbUUID,
                    InsulinDeliveryCharacteristicUUID.recordAccessControlPoint.cbUUID,
                    InsulinDeliveryCharacteristicUUID.historyData.cbUUID
                ],
                DeviceTimeCharacteristicUUID.service.cbUUID: [
                    DeviceTimeCharacteristicUUID.controlPoint.cbUUID
                ],
            ],
            valueUpdateMacros: [:],
            willServiceSetChange: false
        )
    }
}
