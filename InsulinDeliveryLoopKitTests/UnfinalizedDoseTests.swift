//
//  UnfinalizedDoseTests.swift
//  InsulinDeliveryLoopKitTests
//
//  Created by Nathaniel Hamming on 2020-05-29.
//  Copyright © 2020 Tidepool Project. All rights reserved.
//

import XCTest
import LoopKit
@testable import InsulinDeliveryLoopKit

class UnfinalizedDoseTests: XCTestCase {
    
    func testInitializationBolus() {
        let amount = 3.5
        let startTime = Date()
        let duration = TimeInterval(amount / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate)
        let unfinalizedBolus = UnfinalizedDose(decisionId: nil,
                                               bolusAmount: amount,
                                               startTime: startTime,
                                               scheduledCertainty: .certain)
        XCTAssertEqual(unfinalizedBolus.doseType, .bolus)
        XCTAssertEqual(unfinalizedBolus.units, amount)
        XCTAssertNil(unfinalizedBolus.programmedUnits)
        XCTAssertNil(unfinalizedBolus.programmedRate)
        XCTAssertEqual(unfinalizedBolus.startTime, startTime)
        XCTAssertEqual(unfinalizedBolus.duration, duration)
        XCTAssertEqual(unfinalizedBolus.scheduledCertainty, .certain)
        XCTAssertEqual(unfinalizedBolus.endTime, startTime.addingTimeInterval(duration))
        XCTAssertEqual(unfinalizedBolus.rate, amount/duration.hours)
    }
    
    func testInitializationTempBasal() {
        let amount = 0.5
        let startTime = Date()
        let duration = TimeInterval.minutes(30)
        let unfinalizedTempBasal = UnfinalizedDose(decisionId: nil,
                                                   tempBasalRate: amount,
                                                   startTime: startTime,
                                                   duration: duration,
                                                   scheduledCertainty: .certain)
        XCTAssertEqual(unfinalizedTempBasal.doseType, .tempBasal)
        XCTAssertEqual(unfinalizedTempBasal.units, amount*duration.hours)
        XCTAssertNil(unfinalizedTempBasal.programmedUnits)
        XCTAssertNil(unfinalizedTempBasal.programmedRate)
        XCTAssertEqual(unfinalizedTempBasal.startTime, startTime)
        XCTAssertEqual(unfinalizedTempBasal.duration, duration)
        XCTAssertEqual(unfinalizedTempBasal.scheduledCertainty, .certain)
        XCTAssertEqual(unfinalizedTempBasal.endTime, startTime.addingTimeInterval(duration))
        XCTAssertEqual(unfinalizedTempBasal.rate, amount)
    }
    
    func testInitializatinSuspend() {
        let startTime = Date()
        let unfinalizedSuspend = UnfinalizedDose(suspendStartTime: startTime,
                                                 scheduledCertainty: .certain)
        XCTAssertEqual(unfinalizedSuspend.doseType, .suspend)
        XCTAssertEqual(unfinalizedSuspend.units, 0)
        XCTAssertNil(unfinalizedSuspend.programmedUnits)
        XCTAssertNil(unfinalizedSuspend.programmedRate)
        XCTAssertEqual(unfinalizedSuspend.startTime, startTime)
        XCTAssertNil(unfinalizedSuspend.duration)
        XCTAssertEqual(unfinalizedSuspend.scheduledCertainty, .certain)
        XCTAssertNil(unfinalizedSuspend.endTime)
        XCTAssertEqual(unfinalizedSuspend.rate, 0)
    }
    
    func testInitializationResume() {
        let startTime = Date()
        let unfinalizedResume = UnfinalizedDose(resumeStartTime: startTime,
                                                scheduledCertainty: .certain)
        XCTAssertEqual(unfinalizedResume.doseType, .resume)
        XCTAssertEqual(unfinalizedResume.units, 0)
        XCTAssertNil(unfinalizedResume.programmedUnits)
        XCTAssertNil(unfinalizedResume.programmedRate)
        XCTAssertEqual(unfinalizedResume.startTime, startTime)
        XCTAssertNil(unfinalizedResume.duration)
        XCTAssertEqual(unfinalizedResume.scheduledCertainty, .certain)
        XCTAssertNil(unfinalizedResume.endTime)
        XCTAssertEqual(unfinalizedResume.rate, 0)
    }
    
    func testProgress() {
        let amount = 3.5
        let startTime = Date()
        let duration = TimeInterval(amount / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate)
        let unfinalizedBolus = UnfinalizedDose(decisionId: nil,
                                               bolusAmount: amount,
                                               startTime: startTime,
                                               scheduledCertainty: .certain)
        XCTAssertEqual(unfinalizedBolus.progress(at: startTime + .seconds(30)), .seconds(30) / duration)
        XCTAssertEqual(unfinalizedBolus.progress(at: startTime + .seconds(300)), 1)
    }
    
    func testIsFinished() {
        let amount = 0.5
        let startTime = Date()
        let duration = TimeInterval.minutes(30)
        let unfinalizedTempBasal = UnfinalizedDose(decisionId: nil,
                                                   tempBasalRate: amount,
                                                   startTime: startTime,
                                                   duration: duration,
                                                   scheduledCertainty: .certain)
        XCTAssertFalse(unfinalizedTempBasal.isFinished(at: startTime + .minutes(25)))
        XCTAssertTrue(unfinalizedTempBasal.isFinished(at: startTime + .minutes(31)))
    }
    
    func testFinalizedUnits() {
        let amount = 3.5
        let startTime = Date()
        let unfinalizedBolus = UnfinalizedDose(decisionId: nil,
                                               bolusAmount: amount,
                                               startTime: startTime,
                                               scheduledCertainty: .certain)
        XCTAssertNil(unfinalizedBolus.finalizedUnits(at: startTime + .seconds(30)))
        XCTAssertEqual(unfinalizedBolus.finalizedUnits(at: startTime + .seconds(300)), amount)
    }
        
    func testBolusCancelLongAfterFinishTime() {
        let start = Date()
        var dose = UnfinalizedDose(decisionId: nil, bolusAmount: 1, startTime: start, scheduledCertainty: .certain)
        dose.cancel(at: start + .hours(2))
        
        XCTAssertEqual(1.0, dose.units)
    }
    
    func testRawValue() {
        let amount = 3.5
        let startTime = Date()
        let duration = TimeInterval(amount / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate)
        let unfinalizedBolus = UnfinalizedDose(decisionId: nil,
                                               bolusAmount: amount,
                                               startTime: startTime,
                                               scheduledCertainty: .certain)
        let rawValue = unfinalizedBolus.rawValue
        XCTAssertEqual(UnfinalizedDose.DoseType(rawValue: rawValue["rawDoseType"] as! UnfinalizedDose.DoseType.RawValue), .bolus)
        XCTAssertEqual(rawValue["units"] as! Double, amount)
        XCTAssertEqual(rawValue["startTime"] as! Date, startTime)
        XCTAssertEqual(UnfinalizedDose.ScheduledCertainty(rawValue: rawValue["rawScheduledCertainty"] as! UnfinalizedDose.ScheduledCertainty.RawValue), .certain)
        XCTAssertNil(rawValue["programmedUnits"])
        XCTAssertNil(rawValue["programmedRate"])
        XCTAssertEqual(rawValue["duration"] as! Double, duration)
    }

    func testRawValueBolusWithProgrammedUnits() {
        let amount = 3.5
        let startTime = Date()
        let duration = TimeInterval(amount / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate)
        var unfinalizedBolus = UnfinalizedDose(decisionId: nil,
                                               bolusAmount: amount,
                                               startTime: startTime,
                                               scheduledCertainty: .certain)
        unfinalizedBolus.programmedUnits = amount
        let rawValue = unfinalizedBolus.rawValue
        XCTAssertEqual(UnfinalizedDose.DoseType(rawValue: rawValue["rawDoseType"] as! UnfinalizedDose.DoseType.RawValue), .bolus)
        XCTAssertEqual(rawValue["units"] as! Double, amount)
        XCTAssertEqual(rawValue["startTime"] as! Date, startTime)
        XCTAssertEqual(UnfinalizedDose.ScheduledCertainty(rawValue: rawValue["rawScheduledCertainty"] as! UnfinalizedDose.ScheduledCertainty.RawValue), .certain)
        XCTAssertEqual(rawValue["programmedUnits"] as! Double, amount)
        XCTAssertNil(rawValue["programmedRate"])
        XCTAssertEqual(rawValue["duration"] as! Double, duration)
        
        let restoredUnfinalizedBolus = UnfinalizedDose(rawValue: rawValue)!
        XCTAssertEqual(restoredUnfinalizedBolus.doseType, unfinalizedBolus.doseType)
        XCTAssertEqual(restoredUnfinalizedBolus.units, unfinalizedBolus.units)
        XCTAssertEqual(restoredUnfinalizedBolus.programmedUnits, unfinalizedBolus.programmedUnits)
        XCTAssertEqual(restoredUnfinalizedBolus.programmedRate, unfinalizedBolus.programmedRate)
        XCTAssertEqual(restoredUnfinalizedBolus.startTime, unfinalizedBolus.startTime)
        XCTAssertEqual(restoredUnfinalizedBolus.duration, unfinalizedBolus.duration)
        XCTAssertEqual(restoredUnfinalizedBolus.scheduledCertainty, unfinalizedBolus.scheduledCertainty)
        XCTAssertEqual(restoredUnfinalizedBolus.endTime, unfinalizedBolus.endTime)
        XCTAssertEqual(restoredUnfinalizedBolus.rate, unfinalizedBolus.rate)
    }
    
    func testRawValueTempBasalWithProgrammedRate() {
        let rate = 0.5
        let startTime = Date()
        let duration = TimeInterval.minutes(30)
        var unfinalizedTempBasal = UnfinalizedDose(decisionId: nil,
                                                   tempBasalRate: rate,
                                                   startTime: startTime,
                                                   duration: duration,
                                                   scheduledCertainty: .certain)
        unfinalizedTempBasal.programmedRate = rate
        let rawValue = unfinalizedTempBasal.rawValue
        XCTAssertEqual(UnfinalizedDose.DoseType(rawValue: rawValue["rawDoseType"] as! UnfinalizedDose.DoseType.RawValue), .tempBasal)
        XCTAssertEqual(rawValue["units"] as! Double, rate*duration.hours)
        XCTAssertEqual(rawValue["startTime"] as! Date, startTime)
        XCTAssertEqual(UnfinalizedDose.ScheduledCertainty(rawValue: rawValue["rawScheduledCertainty"] as! UnfinalizedDose.ScheduledCertainty.RawValue), .certain)
        XCTAssertNil(rawValue["programmedUnits"])
        XCTAssertEqual(rawValue["programmedRate"] as! Double, rate)
        XCTAssertEqual(rawValue["duration"] as! Double, duration)
        
        let restoredUnfinalizedTempBasal = UnfinalizedDose(rawValue: rawValue)!
        XCTAssertEqual(restoredUnfinalizedTempBasal.doseType, unfinalizedTempBasal.doseType)
        XCTAssertEqual(restoredUnfinalizedTempBasal.units, unfinalizedTempBasal.units)
        XCTAssertEqual(restoredUnfinalizedTempBasal.programmedUnits, unfinalizedTempBasal.programmedUnits)
        XCTAssertEqual(restoredUnfinalizedTempBasal.programmedRate, unfinalizedTempBasal.programmedRate)
        XCTAssertEqual(restoredUnfinalizedTempBasal.startTime, unfinalizedTempBasal.startTime)
        XCTAssertEqual(restoredUnfinalizedTempBasal.duration, unfinalizedTempBasal.duration)
        XCTAssertEqual(restoredUnfinalizedTempBasal.scheduledCertainty, unfinalizedTempBasal.scheduledCertainty)
        XCTAssertEqual(restoredUnfinalizedTempBasal.endTime, unfinalizedTempBasal.endTime)
        XCTAssertEqual(restoredUnfinalizedTempBasal.rate, unfinalizedTempBasal.rate)
    }
    
    func testRestoreFromRawValue() {
        let rate = 0.5
        let startTime = Date()
        let duration = TimeInterval.minutes(30)
        let expectedUnfinalizedTempBasal = UnfinalizedDose(decisionId: nil,
                                                           tempBasalRate: rate,
                                                           startTime: startTime,
                                                           duration: duration,
                                                           scheduledCertainty: .certain)
        let rawValue = expectedUnfinalizedTempBasal.rawValue
        let unfinalizedTempBasal = UnfinalizedDose(rawValue: rawValue)!
        XCTAssertEqual(unfinalizedTempBasal.doseType, .tempBasal)
        XCTAssertEqual(unfinalizedTempBasal.units, rate*duration.hours)
        XCTAssertNil(unfinalizedTempBasal.programmedUnits)
        XCTAssertNil(unfinalizedTempBasal.programmedRate)
        XCTAssertEqual(unfinalizedTempBasal.startTime, startTime)
        XCTAssertEqual(unfinalizedTempBasal.duration, duration)
        XCTAssertEqual(unfinalizedTempBasal.scheduledCertainty, .certain)
        XCTAssertEqual(unfinalizedTempBasal.endTime, startTime.addingTimeInterval(duration))
        XCTAssertEqual(unfinalizedTempBasal.rate, rate)
    }

    func testDoseEntryInitFromUnfinalizedBolus() {
        let amount = 3.5
        let startTime = Date()
        let now = Date()
        let duration = TimeInterval(amount / InsulinDeliveryPumpManager.estimatedBolusDeliveryRate)
        let unfinalizedBolus = UnfinalizedDose(decisionId: nil,
                                               bolusAmount: amount,
                                               startTime: startTime,
                                               scheduledCertainty: .certain)
        let doseEntry = DoseEntry(unfinalizedBolus, at: now)
        XCTAssertEqual(doseEntry.type, .bolus)
        XCTAssertEqual(doseEntry.startDate, startTime)
        XCTAssertEqual(doseEntry.endDate, startTime.addingTimeInterval(duration))
        XCTAssertEqual(doseEntry.programmedUnits, amount)
        XCTAssertEqual(doseEntry.unit, .units)
        XCTAssertNil(doseEntry.deliveredUnits)
    }
    
    func testDoseEntryInitFromUnfinalizedTempBasal() {
        let amount = 0.5
        let startTime = Date()
        let now = Date()
        let duration = TimeInterval.minutes(30)
        let rate = amount*duration.hours
        let unfinalizedTempBasal = UnfinalizedDose(decisionId: nil,
                                                   tempBasalRate: amount,
                                                   startTime: startTime,
                                                   duration: duration,
                                                   scheduledCertainty: .certain)
        let doseEntry = DoseEntry(unfinalizedTempBasal, at: now)
        XCTAssertEqual(doseEntry.type, .tempBasal)
        XCTAssertEqual(doseEntry.startDate, startTime)
        XCTAssertEqual(doseEntry.endDate, startTime.addingTimeInterval(duration))
        XCTAssertEqual(doseEntry.programmedUnits, rate)
        XCTAssertEqual(doseEntry.unit, .unitsPerHour)
        XCTAssertNil(doseEntry.deliveredUnits)
    }
    
    func testDoseEntryInitFromUnfinalizedSuspend() {
        let startTime = Date()
        let now = Date()
        let unfinalizedSuspend = UnfinalizedDose(suspendStartTime: startTime,
                                                 scheduledCertainty: .certain)
        let doseEntry = DoseEntry(unfinalizedSuspend, at: now)
        XCTAssertEqual(doseEntry.type, .suspend)
        XCTAssertEqual(doseEntry.startDate, startTime)
        XCTAssertEqual(doseEntry.endDate, startTime)
        XCTAssertEqual(doseEntry.programmedUnits, 0)
        XCTAssertEqual(doseEntry.unit, .units)
        XCTAssertNil(doseEntry.deliveredUnits)
    }
    
    func testDoseEntryInitFromUnfinalizedResume() {
        let startTime = Date()
        let now = Date()
        let unfinalizedResume = UnfinalizedDose(resumeStartTime: startTime,
                                                 scheduledCertainty: .certain)
        let doseEntry = DoseEntry(unfinalizedResume, at: now)
        XCTAssertEqual(doseEntry.type, .resume)
        XCTAssertEqual(doseEntry.startDate, startTime)
        XCTAssertEqual(doseEntry.endDate, startTime)
        XCTAssertEqual(doseEntry.programmedUnits, 0)
        XCTAssertEqual(doseEntry.unit, .units)
        XCTAssertNil(doseEntry.deliveredUnits)
    }

    func testMultipleCancels() {
        let now = Date()
        let then = now.addingTimeInterval(.minutes(1))
        var dose = UnfinalizedDose(decisionId: nil, bolusAmount: 1, startTime: now, scheduledCertainty: .certain)
        dose.cancel(at: now)

        XCTAssertEqual(now, dose.endTime)
        XCTAssertEqual(1, dose.programmedUnits)
        XCTAssertEqual(0, dose.units)

        dose.cancel(at: then, insulinDelivered: 0.5)
        XCTAssertEqual(then, dose.endTime)
        XCTAssertEqual(1, dose.programmedUnits)
        XCTAssertEqual(0.5, dose.units)
    }
}
