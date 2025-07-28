//
//  TestInsulinDeliveryPump.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-07-24.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
@testable import InsulinDeliveryLoopKit

class TestInsulinDeliveryPump: InsulinDeliveryPump {
    func setupUUIDToHandleMap() {
        self.state.uuidToHandleMap = [
            InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID: 1,
            InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID: 2,
            DeviceTimeCharacteristicUUID.controlPoint.cbUUID: 3,
            DeviceTimeCharacteristicUUID.deviceTime.cbUUID: 4,
            ACCharacteristicUUID.controlPoint.cbUUID: 5,
        ]
    }

    func setupDeviceInformation(therapyControlState: InsulinTherapyControlState = .run, pumpOperationalState: PumpOperationalState = .ready) {
        self.state.deviceInformation = DeviceInformation(identifier: UUID(), serialNumber: "12345678", therapyControlState: therapyControlState, pumpOperationalState: pumpOperationalState)
    }

    func setTherapyControlStateTo(_ therapyControlState: InsulinTherapyControlState) {
        self.state.deviceInformation?.therapyControlState = therapyControlState
    }

    func setOperationalStateTo(_ pumpOperationalState: PumpOperationalState) {
        self.state.deviceInformation?.pumpOperationalState = pumpOperationalState
    }
    
    func startDeliveringInsulin() {
        setOperationalStateTo(.ready)
        setTherapyControlStateTo(.run)
    }

    func respondToTempBasalAdjustmentWithSuccess() {
        let requestOpcode = IDControlPointOpcode.setTempBasalAdjustment
        let responseCode = IDControlPointResponseCode.success
        var response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(requestOpcode.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        self.manageInsulinDeliveryControlPointResponse(response)
    }

    func respondToSetTherapyControlState(responseCode: IDControlPointResponseCode = .success, therapyControlState: InsulinTherapyControlState? = nil) {
        var response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(IDControlPointOpcode.setTherapyControlState.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        if let therapyControlState = therapyControlState {
            self.state.deviceInformation?.therapyControlState = therapyControlState
        }
        self.manageInsulinDeliveryControlPointResponse(response)
    }

    func respondToStartPriming(responseCode: IDControlPointResponseCode = .success) {
        var response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(IDControlPointOpcode.startPriming.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        self.state.deviceInformation?.pumpOperationalState = .priming
        self.manageInsulinDeliveryControlPointResponse(response)
    }

    func respondToStopPriming(responseCode: IDControlPointResponseCode = .success) {
        var response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(IDControlPointOpcode.stopPriming.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        self.state.deviceInformation?.pumpOperationalState = .ready
        self.manageInsulinDeliveryControlPointResponse(response)
    }

    func respondToGetTime(_ date: Date = Date(), using timeZone: TimeZone = .current) {
        let baseTime = date.baseTimeInSecondsFromEpoch2000
        let statusFlags = DTStatusFlag([.epochYear2000, .utcAligned])

        var response = Data(baseTime)
        response.append(timeZone.gattTimeZoneOffset)
        response.append(timeZone.dstOffset.rawValue)
        response.append(statusFlags.rawValue)
        response = response.appendingCRCPrefix()

        self.managerDeviceTimeData(response)
    }

    func respondToSetTime(responseCode: DTControlPointResponseCode = .success) {
        var response = Data(DTControlPointOpcode.responseCode.rawValue)
        response.append(DTControlPointOpcode.proposeTimeUpdate.rawValue)
        response.append(responseCode.rawValue)
        response = response.appendingCRCPrefix()

        self.managerDeviceTimeControlPointResponse(response)
    }

    func respondToSetBolusWithSuccess(bolusID: BolusID) {
        let opcode = IDControlPointOpcode.setBolusResponse
        var response = Data(opcode.rawValue)
        response.append(bolusID)
        response.append(self.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        self.manageInsulinDeliveryControlPointResponse(response)
    }

    func respondToCancelBolusWithSuccess(bolusID: BolusID) {
        let opcode = IDControlPointOpcode.cancelBolusResponse
        var response = Data(opcode.rawValue)
        response.append(bolusID)
        response.append(self.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        self.manageInsulinDeliveryControlPointResponse(response)
    }

    func sendBolusCancelledAnnunciation(bolusID: BolusID, programmedAmount: Double, deliveredAmount: Double) {
        let flags = AnnunciationStatusFlag.init(arrayLiteral: [.presentAnnunciation, .presentAuxInfo1, .presentAuxInfo2, .presentAuxInfo3, .presentAuxInfo4])
        let annunciationID: UInt16 = 4
        let annunciationType = AnnunciationType.bolusCanceled
        let annunciationStatus = AnnunciationStatus.pending

        let bolusType: BolusType = .fast
        let padding: UInt8 = 0x00
        var auxiliaryData = Data(bolusID)
        auxiliaryData.append(bolusType.rawValue)
        auxiliaryData.append(padding)
        auxiliaryData.append(programmedAmount.sfloat)
        auxiliaryData.append(deliveredAmount.sfloat)

        var response = Data(flags.rawValue)
        response.append(annunciationID)
        response.append(annunciationType.rawValue)
        response.append(annunciationStatus.rawValue)
        response.append(auxiliaryData)
        response.append(UInt8(1)) // E2ECounter
        response = response.appendingCRC()

        self.manageInsulinDeliveryAnnunciationStatusData(response)
    }
    
    func respondToCancelTempBasal(responseCode: IDControlPointResponseCode = .success) {
        var response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(IDControlPointOpcode.cancelTempBasalAdjustment.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()
        
        self.manageInsulinDeliveryControlPointResponse(response)
    }
        

    func respondToSetReservoirLevel(responseCode: IDControlPointResponseCode = .success) {
        // the last step of setting the reservoir level is activating the basal profile. So respond with that.
        var response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(IDControlPointOpcode.setInitialResevoirFillLevel.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        self.manageInsulinDeliveryControlPointResponse(response)
    }
    
    func respondToResetReservoirInsulinOperationTime(responseCode: IDControlPointResponseCode = .success) {
        // the last step of setting the reservoir level is activating the basal profile. So respond with that.
        var response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(IDControlPointOpcode.resetResevoirInsulinOperationTime.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        self.manageInsulinDeliveryControlPointResponse(response)
    }
    
    func respondToWriteBasalRate(responseCode: IDControlPointResponseCode = .success) {
        // the last step of setting the reservoir level is activating the basal profile. So respond with that.
        var response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(IDControlPointOpcode.writeBasalRateTemplate.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        self.manageInsulinDeliveryControlPointResponse(response)
    }
    
    func respondToActivateProfileTemplate(responseCode: IDControlPointResponseCode = .success) {
        // the last step of setting the reservoir level is activating the basal profile. So respond with that.
        var response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(IDControlPointOpcode.activateProfileTemplates.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        self.manageInsulinDeliveryControlPointResponse(response)
    }
    
    func respondToGetDeliveredInsulin(bolusDelivered: Int = 100, basalDelivered: Int = 100, responseCode: IDControlPointResponseCode = .success) {
        var response = Data(IDStatusReaderOpcode.getDeliveredInsulinResponse.rawValue)
        response.append(UInt32(bolusDelivered))
        response.append(UInt32(basalDelivered))
        response.append(self.insulinDeliveryStatusReader.e2eCounter)
        response = response.appendingCRC()
        
        self.manageInsulinDeliveryStatusReaderResponse(response)
    }
    
    func respondToGetActiveBasalRate(scheduleBasalRate: Double, tempBasalRate: Double? = nil, tempBasalDuration: TimeInterval? = nil, tempBasalRemaining: TimeInterval? = nil) {
        var flags: ActiveBasalRateFlag = [.deliveryContextPresent]
        if tempBasalRate != nil {
            flags.insert(.tbrPresent)
        }
        
        var response = Data(IDStatusReaderOpcode.getActiveBasalRateDeliveryResponse.rawValue)
        response.append(flags.rawValue)
        response.append(UInt8(1)) // profile number
        response.append(scheduleBasalRate.sfloat)
        if let tempBasalRate = tempBasalRate,
           let tempBasalDuration = tempBasalDuration
        {
            response.append(TempBasalType.absolute.rawValue)
            response.append(tempBasalRate.sfloat)
            response.append(UInt16(tempBasalDuration.minutes))
            response.append(UInt16(tempBasalRemaining?.minutes ?? tempBasalDuration.minutes))
        }
        response.append(TempBasalDeliveryContext.apController.rawValue)
        response.append(self.insulinDeliveryStatusReader.e2eCounter)
        response = response.appendingCRC()
        
        self.manageInsulinDeliveryStatusReaderResponse(response)
    }
    
    func respondToGetRemainingLifeTime(remainingLifetime: TimeInterval = .days(4)) {
        var response = Data(IDStatusReaderOpcode.getCounterResponse.rawValue)
        response.append(CounterType.lifetime.rawValue)
        response.append(CounterValueSelection.remaining.rawValue)
        response.append(Int32(remainingLifetime.minutes))
        response.append(self.insulinDeliveryStatusReader.e2eCounter)
        response = response.appendingCRC()
        
        self.manageInsulinDeliveryStatusReaderResponse(response)
    }
    
    func respondToInvalidateKey(_ responseCode: ACControlPointResponseCode = .success) {
        var response = Data(ACControlPointOpcode.responseCode.rawValue)
        response.append(ACControlPointOpcode.invalidateKey.rawValue)
        response.append(responseCode.rawValue)
        
        self.manageACControlPointResponse(response: response, isSegmented: false)
    }
    
    func issueActiveBasalRateChanged() {
        let flag: InsulinDeliveryStatusChangedFlag = [.activeBasalRateStatusChanged]
        var response = Data(flag.rawValue)
        response.append(UInt8(1)) // E2E-copunter
        response = response.appendingCRC()
        
        self.manageInsulinDeliveryStatusChangedData(response)
    }
    
    var confirmedAnnunciations = [Annunciation]()
    var confirmAnnunciationResult: DeviceCommResult<Void>?
    override func confirmAnnunciation(_ annunciation: Annunciation, completion: @escaping ProcedureResultCompletion) {
        confirmedAnnunciations.append(annunciation)
        if let confirmAnnunciationResult = confirmAnnunciationResult {
            completion(confirmAnnunciationResult)
        } else {
            super.confirmAnnunciation(annunciation, completion: completion)
        }
    }
    
    var suspendInsulinDeliveryResult: DeviceCommResult<PumpDeliveryStatus?>?
    override func suspendInsulinDelivery(completion: @escaping PumpDeliveryStatusCompletion) {
        if let suspendInsulinDeliveryResult = suspendInsulinDeliveryResult {
            completion(suspendInsulinDeliveryResult)
        } else {
            super.suspendInsulinDelivery(completion: completion)
        }
    }
    
    var pumpDeliveryStatus: DeviceCommResult<PumpDeliveryStatus?>?
    override func updateStatus(completion: @escaping PumpDeliveryStatusCompletion) {
        if let pumpDeliveryStatus = pumpDeliveryStatus {
            switch pumpDeliveryStatus {
            case .success(_):
                delegate?.pumpDidSync(self)
            default:
                break
            }
            completion(pumpDeliveryStatus)
        } else {
            super.updateStatus(completion: completion)
        }
    }

    func reportHistoryEventTherapyControlStateChanged() {
        let eventType = IDHistoryEventType.therapyControlStateChanged
        let sequenceNumber: HistoryEventSequenceNumber = 100
        let relativeOffet: UInt16 = 10
        var auxData = Data(InsulinTherapyControlState.stop.rawValue)
        auxData.append(InsulinTherapyControlState.run.rawValue)

        var historyData = Data(eventType.rawValue)
        historyData.append(sequenceNumber)
        historyData.append(relativeOffet)
        historyData.append(auxData)
        historyData = historyData.appendingCRC()

        self.manageInsulinDeliveryHistoryData(historyData)
    }
    

    func reportHistoryEventError() {
        self.manageInsulinDeliveryHistoryData(Data([0x01, 0x02, 0x03, 0x04]))
    }

    func sendKeyExchangeResponseEnableACS() {
        var response = Data(KEControlPointOpcode.responseCode.rawValue)
        response.append(KEControlPointOpcode.enableACS.rawValue)
        response.append(KEControlPointResponseCode.success.rawValue)

        self.manageKEControlPointResponse(response)
    }

    func sendKeyExchangeResponseEnableACSError() {
        var response = Data(KEControlPointOpcode.responseCode.rawValue)
        response.append(KEControlPointOpcode.enableACS.rawValue)
        response.append(UInt8(0xff))

        self.manageKEControlPointResponse(response)
    }

    func sendInsulinDeliveryControlPointResponseError(requestOpcode: IDControlPointOpcode) {
        var response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(requestOpcode.rawValue)
        response.append(UInt8(0xff))

        self.manageInsulinDeliveryControlPointResponse(response)
    }

    func sendInsulinDeliveryStatusReaderResponseError(requestOpcode: IDStatusReaderOpcode) {
        var response = Data(IDStatusReaderOpcode.responseCode.rawValue)
        response.append(requestOpcode.rawValue)
        response.append(UInt8(0xff))

        self.manageInsulinDeliveryStatusReaderResponse(response)
    }

    func sendRecordAccessControlPointResponseError(requestOpcode: RACPOpcode) {
        var response = Data(RACPOpcode.responseCode.rawValue)
        response.append(RACPOperator.nullOperator.rawValue)
        response.append(requestOpcode.rawValue)
        response.append(UInt8(0xff))

        self.manageRecordAccessControlPointResponse(response)
    }

    func sendInsulinDeliveryStatusDataError() {
        self.manageInsulinDeliveryStatusData(Data([0x01, 0x02, 0x03, 0x04]))
    }

    func sendInsulinDeliveryStatusChangedDataError() {
        self.manageInsulinDeliveryStatusChangedData(Data([0x01, 0x02, 0x03, 0x04]))
    }

    func sendInsulinDeliveryAnnunciationStatusDataError() {
        self.manageInsulinDeliveryAnnunciationStatusData(Data([0x01, 0x02, 0x03, 0x04]))
    }

    func sendInsulinDeliveryStatusData(therapyControlState: InsulinTherapyControlState = .run, pumpOperationalState: PumpOperationalState = .ready) {
        let reservoirLevel = 150.0
        var data = Data(therapyControlState.rawValue)
        data.append(pumpOperationalState.rawValue)
        data.append(reservoirLevel.sfloat)
        data.append(InsulinDeliveryStatusFlag([.reservoirAttached]).rawValue)
        data.append(UInt8(0x01)) // E2E counter
        data = data.appendingCRC()

        self.manageInsulinDeliveryStatusData(data)
    }

    func sendInsulinDeliveryStatusChangedData() {
        var data = Data(InsulinDeliveryStatusChangedFlag.allZeros.rawValue)
        data.append(UInt8(0x01)) // E2E counter
        data = data.appendingCRC()

        self.manageInsulinDeliveryStatusChangedData(data)
    }

    func sendInsulinDeliveryAnnunciationStatusDataNoAnnunciations() {
        var data = Data(AnnunciationStatusFlag.allZeros.rawValue)
        data.append(UInt8(0x01)) // E2E counter
        data = data.appendingCRC()

        self.manageInsulinDeliveryAnnunciationStatusData(data)
    }

    func sendInsulinDeliveryAnnunciationStatusData() {
        let annunciationID: AnnunciationIdentifier = 123

        var data = Data(AnnunciationStatusFlag([.presentAnnunciation]).rawValue)
        data.append(annunciationID)
        data.append(AnnunciationType.endOfPumpLifetime.rawValue)
        data.append(AnnunciationStatus.pending.rawValue)
        data.append(UInt8(0x01)) // E2E counter
        data = data.appendingCRC()

        self.manageInsulinDeliveryAnnunciationStatusData(data)
    }

    func reportUpdatedBolusDelivery(bolusID: BolusID, insulinDelivered: Double) {
        var response = Data(IDStatusReaderOpcode.getActiveBolusDeliveryResponse.rawValue)
        response.append(UInt8(0x00)) // flags
        response.append(bolusID)
        response.append(BolusType.fast.rawValue)
        response.append(insulinDelivered.sfloat)
        response.append(0.sfloat) // extended bolus is 0 for fast
        response.append(UInt8(0x01)) // E2E counter
        response = response.appendingCRC()

        self.manageInsulinDeliveryStatusReaderResponse(response)
    }
}
