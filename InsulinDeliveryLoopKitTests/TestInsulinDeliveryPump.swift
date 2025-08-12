//
//  TestInsulinDeliveryPump.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-07-24.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import BluetoothCommonKit
import InsulinDeliveryServiceKit
@testable import InsulinDeliveryLoopKit

class TestInsulinDeliveryPump: InsulinDeliveryPump {
    func setupUUIDToHandleMap() {
        state.uuidToHandleMap = [
            InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID: 1,
            InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID: 2,
            DeviceTimeCharacteristicUUID.controlPoint.cbUUID: 3,
            DeviceTimeCharacteristicUUID.deviceTime.cbUUID: 4,
            ACCharacteristicUUID.controlPoint.cbUUID: 5,
        ]
    }

    func setupDeviceInformation(therapyControlState: InsulinTherapyControlState = .run, pumpOperationalState: PumpOperationalState = .ready) {
        state.deviceInformation = DeviceInformation(identifier: UUID(), serialNumber: "12345678", therapyControlState: therapyControlState, pumpOperationalState: pumpOperationalState, reportedRemainingLifetime: InsulinDeliveryPumpManager.lifespan)
    }

    func setTherapyControlStateTo(_ therapyControlState: InsulinTherapyControlState) {
        state.deviceInformation?.therapyControlState = therapyControlState
    }

    func setOperationalStateTo(_ pumpOperationalState: PumpOperationalState) {
        state.deviceInformation?.pumpOperationalState = pumpOperationalState
    }
    
    func startDeliveringInsulin() {
        setOperationalStateTo(.ready)
        setTherapyControlStateTo(.run)
    }

    func respondToTempBasalAdjustmentWithSuccess() {
        let requestOpcode = IDCommandControlPointOpcode.setTempBasalAdjustment
        let responseCode = IDCommandControlPointResponseCode.success
        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(requestOpcode.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.idCommand.e2eCounter)
        response = response.appendingCRC()

        manageInsulinDeliveryCommandControlPointResponse(response)
    }

    func respondToSetTherapyControlState(responseCode: IDCommandControlPointResponseCode = .success, therapyControlState: InsulinTherapyControlState? = nil) {
        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(IDCommandControlPointOpcode.setTherapyControlState.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.idCommand.e2eCounter)
        response = response.appendingCRC()

        if let therapyControlState = therapyControlState {
            state.deviceInformation?.therapyControlState = therapyControlState
        }
        manageInsulinDeliveryCommandControlPointResponse(response)
    }

    func respondToStartPriming(responseCode: IDCommandControlPointResponseCode = .success) {
        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(IDCommandControlPointOpcode.startPriming.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.idCommand.e2eCounter)
        response = response.appendingCRC()

        state.deviceInformation?.pumpOperationalState = .priming
        manageInsulinDeliveryCommandControlPointResponse(response)
    }

    func respondToStopPriming(responseCode: IDCommandControlPointResponseCode = .success) {
        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(IDCommandControlPointOpcode.stopPriming.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.idCommand.e2eCounter)
        response = response.appendingCRC()

        state.deviceInformation?.pumpOperationalState = .ready
        manageInsulinDeliveryCommandControlPointResponse(response)
    }

    func respondToGetTime(_ date: Date = Date(), using timeZone: TimeZone = .current) {
        let baseTime = date.baseTimeInSecondsFromEpoch2000
        let statusFlags = DTStatusFlag([.epochYear2000, .utcAligned])

        var response = Data(baseTime)
        response.append(timeZone.gattTimeZoneOffset)
        response.append(timeZone.dstOffset.rawValue)
        response.append(statusFlags.rawValue)
        response = response.appendingCRCPrefix()

        managerDeviceTimeData(response)
    }

    func respondToSetTime(responseCode: DTControlPointResponseCode = .success) {
        var response = Data(DTControlPointOpcode.responseCode.rawValue)
        response.append(DTControlPointOpcode.proposeTimeUpdate.rawValue)
        response.append(responseCode.rawValue)
        response = response.appendingCRCPrefix()

        managerDeviceTimeControlPointResponse(response)
    }

    func respondToSetBolusWithSuccess(bolusID: BolusID) {
        let opcode = IDCommandControlPointOpcode.setBolusResponse
        var response = Data(opcode.rawValue)
        response.append(bolusID)
        response.append(self.idCommand.e2eCounter)
        response = response.appendingCRC()

        manageInsulinDeliveryCommandControlPointResponse(response)
    }

    func respondToCancelBolusWithSuccess(bolusID: BolusID) {
        let opcode = IDCommandControlPointOpcode.cancelBolusResponse
        var response = Data(opcode.rawValue)
        response.append(bolusID)
        response.append(self.idCommand.e2eCounter)
        response = response.appendingCRC()

        manageInsulinDeliveryCommandControlPointResponse(response)
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

        manageInsulinDeliveryAnnunciationStatusData(response)
    }
    
    func respondToCancelTempBasal(responseCode: IDCommandControlPointResponseCode = .success) {
        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(IDCommandControlPointOpcode.cancelTempBasalAdjustment.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.idCommand.e2eCounter)
        response = response.appendingCRC()
        
        manageInsulinDeliveryCommandControlPointResponse(response)
    }
        

    func respondToSetReservoirLevel(responseCode: IDCommandControlPointResponseCode = .success) {
        // the last step of setting the reservoir level is activating the basal profile. So respond with that.
        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(IDCommandControlPointOpcode.setInitialResevoirFillLevel.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.idCommand.e2eCounter)
        response = response.appendingCRC()

        manageInsulinDeliveryCommandControlPointResponse(response)
    }
    
    func respondToResetReservoirInsulinOperationTime(responseCode: IDCommandControlPointResponseCode = .success) {
        // the last step of setting the reservoir level is activating the basal profile. So respond with that.
        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(IDCommandControlPointOpcode.resetResevoirInsulinOperationTime.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.idCommand.e2eCounter)
        response = response.appendingCRC()

        manageInsulinDeliveryCommandControlPointResponse(response)
    }
    
    func respondToWriteBasalRate(responseCode: IDCommandControlPointResponseCode = .success) {
        // the last step of setting the reservoir level is activating the basal profile. So respond with that.
        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(IDCommandControlPointOpcode.writeBasalRateTemplate.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.idCommand.e2eCounter)
        response = response.appendingCRC()

        manageInsulinDeliveryCommandControlPointResponse(response)
    }
    
    func respondToActivateProfileTemplate(responseCode: IDCommandControlPointResponseCode = .success) {
        // the last step of setting the reservoir level is activating the basal profile. So respond with that.
        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(IDCommandControlPointOpcode.activateProfileTemplates.rawValue)
        response.append(responseCode.rawValue)
        response.append(self.idCommand.e2eCounter)
        response = response.appendingCRC()

        manageInsulinDeliveryCommandControlPointResponse(response)
    }
    
    func respondToGetDeliveredInsulin(bolusDelivered: Int = 100, basalDelivered: Int = 100, responseCode: IDCommandControlPointResponseCode = .success) {
        var response = Data(IDStatusReaderOpcode.getDeliveredInsulinResponse.rawValue)
        response.append(UInt32(bolusDelivered))
        response.append(UInt32(basalDelivered))
        response.append(self.idStatusReader.e2eCounter)
        response = response.appendingCRC()
        
        manageInsulinDeliveryStatusReaderResponse(response)
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
        response.append(BasalDeliveryContext.aidController.rawValue)
        response.append(self.idStatusReader.e2eCounter)
        response = response.appendingCRC()
        
        manageInsulinDeliveryStatusReaderResponse(response)
    }
    
    func respondToGetRemainingLifeTime(remainingLifetime: TimeInterval = .days(4)) {
        var response = Data(IDStatusReaderOpcode.getCounterResponse.rawValue)
        response.append(CounterType.lifetime.rawValue)
        response.append(CounterValueSelection.remaining.rawValue)
        response.append(Int32(remainingLifetime.minutes))
        response.append(self.idStatusReader.e2eCounter)
        response = response.appendingCRC()
        
        manageInsulinDeliveryStatusReaderResponse(response)
    }
    
    func respondToInvalidateKey(_ responseCode: ACControlPointResponseCode = .success) {
        var response = Data(ACControlPointOpcode.responseCode.rawValue)
        response.append(ACControlPointOpcode.invalidateKey.rawValue)
        response.append(responseCode.rawValue)
        
        manageACControlPointResponse(response: response, isSegmented: false)
    }
    
    func issueActiveBasalRateChanged() {
        let flag: IDStatusChangedFlag = [.activeBasalRateStatusChanged]
        var response = Data(flag.rawValue)
        response.append(UInt8(1)) // E2E-copunter
        response = response.appendingCRC()
        
        manageInsulinDeliveryStatusChangedData(response)
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
        let sequenceNumber: RecordNumber = 100
        let relativeOffet: UInt16 = 10
        var auxData = Data(InsulinTherapyControlState.stop.rawValue)
        auxData.append(InsulinTherapyControlState.run.rawValue)

        var historyData = Data(eventType.rawValue)
        historyData.append(sequenceNumber)
        historyData.append(relativeOffet)
        historyData.append(auxData)
        historyData = historyData.appendingCRC()

        manageInsulinDeliveryHistoryData(historyData)
    }
    

    func reportHistoryEventError() {
        manageInsulinDeliveryHistoryData(Data([0x01, 0x02, 0x03, 0x04]))
    }

    func sendidCommandResponseError(requestOpcode: IDCommandControlPointOpcode) {
        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(requestOpcode.rawValue)
        response.append(UInt8(0xff))

        manageInsulinDeliveryCommandControlPointResponse(response)
    }

    func sendInsulinDeliveryStatusReaderResponseError(requestOpcode: IDStatusReaderOpcode) {
        var response = Data(IDStatusReaderOpcode.responseCode.rawValue)
        response.append(requestOpcode.rawValue)
        response.append(UInt8(0xff))

        manageInsulinDeliveryStatusReaderResponse(response)
    }

    func sendRecordAccessControlPointResponseError(requestOpcode: IDRACPOpcode) {
        var response = Data(IDRACPOpcode.responseCode.rawValue)
        response.append(IDRACPOperator.nullOperator.rawValue)
        response.append(requestOpcode.rawValue)
        response.append(UInt8(0xff))

        manageRecordAccessControlPointResponse(response)
    }

    func sendInsulinDeliveryStatusDataError() {
        manageInsulinDeliveryStatusData(Data([0x01, 0x02, 0x03, 0x04]))
    }

    func sendInsulinDeliveryStatusChangedDataError() {
        manageInsulinDeliveryStatusChangedData(Data([0x01, 0x02, 0x03, 0x04]))
    }

    func sendInsulinDeliveryAnnunciationStatusDataError() {
        manageInsulinDeliveryAnnunciationStatusData(Data([0x01, 0x02, 0x03, 0x04]))
    }

    func sendInsulinDeliveryStatusData(therapyControlState: InsulinTherapyControlState = .run, pumpOperationalState: PumpOperationalState = .ready) {
        let reservoirLevel = 150.0
        var data = Data(therapyControlState.rawValue)
        data.append(pumpOperationalState.rawValue)
        data.append(reservoirLevel.sfloat)
        data.append(IDStatusFlag([.reservoirAttached]).rawValue)
        data.append(UInt8(0x01)) // E2E counter
        data = data.appendingCRC()

        manageInsulinDeliveryStatusData(data)
    }

    func sendInsulinDeliveryStatusChangedData() {
        var data = Data(IDStatusChangedFlag.allZeros.rawValue)
        data.append(UInt8(0x01)) // E2E counter
        data = data.appendingCRC()

        manageInsulinDeliveryStatusChangedData(data)
    }

    func sendInsulinDeliveryAnnunciationStatusDataNoAnnunciations() {
        var data = Data(AnnunciationStatusFlag.allZeros.rawValue)
        data.append(UInt8(0x01)) // E2E counter
        data = data.appendingCRC()

        manageInsulinDeliveryAnnunciationStatusData(data)
    }

    func sendInsulinDeliveryAnnunciationStatusData() {
        let annunciationID: AnnunciationIdentifier = 123

        var data = Data(AnnunciationStatusFlag([.presentAnnunciation]).rawValue)
        data.append(annunciationID)
        data.append(AnnunciationType.endOfPumpLifetime.rawValue)
        data.append(AnnunciationStatus.pending.rawValue)
        data.append(UInt8(0x01)) // E2E counter
        data = data.appendingCRC()

        manageInsulinDeliveryAnnunciationStatusData(data)
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

        bolusManager.sendingActiveBolusRequest(.delivered)
        manageInsulinDeliveryStatusReaderResponse(response)
    }
}
