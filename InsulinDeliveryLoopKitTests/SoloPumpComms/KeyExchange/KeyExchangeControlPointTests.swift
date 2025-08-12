//
//  KeyExchangeControlPointTests.swift
//  CoastalPumpKitTests
//
//  Created by Nathaniel Hamming on 2022-02-24.
//  Copyright © 2022 Tidepool Project. All rights reserved.
//

import XCTest
@testable import CoastalPumpKit

class KeyExchangeControlPointTests: XCTestCase {

    private var keyExchangeControlPoint: KeyExchangeControlPoint!

    override func setUp() {
        keyExchangeControlPoint = KeyExchangeControlPoint()
    }

    func testOpcode() {
        XCTAssertEqual(KEControlPointOpcode(rawValue: 0x40), KEControlPointOpcode.enableACS)
    }

    func testCreateEnableACSRequest() {
        let request = keyExchangeControlPoint.createEnableAuthorizationControlServiceRequest()
        XCTAssertEqual(request[request.startIndex...].to(KEControlPointOpcode.RawValue.self), KEControlPointOpcode.enableACS.rawValue)
    }

    func testHandleResponseSuccess() {
        var response = Data(KEControlPointOpcode.responseCode.rawValue)
        response.append(KEControlPointOpcode.enableACS.rawValue)
        response.append(KEControlPointResponseCode.success.rawValue)

        let (result, _) = keyExchangeControlPoint.handleResponse(response)
        switch result {
        case .success:
            XCTAssert(true)
        case.failure(_):
            XCTAssert(false)
        }
    }

    func testHandleResponseSuccessUnknownOpcode() {
        var response = Data(UInt8(1))
        response.append(KEControlPointOpcode.enableACS.rawValue)
        response.append(KEControlPointResponseCode.success.rawValue)

        let (result, _) = keyExchangeControlPoint.handleResponse(response)
        switch result {
        case .success:
            XCTAssert(false)
        case.failure(let error):
            XCTAssertEqual(error, .opcodeUnknown(response.hexadecimalString))
        }
    }

    func testHandleResponseSuccessParameterOutOfRange() {
        var response = Data(KEControlPointOpcode.responseCode.rawValue)
        response.append(KEControlPointOpcode.enableACS.rawValue)
        response.append(UInt8(1))

        let (result, _) = keyExchangeControlPoint.handleResponse(response)
        switch result {
        case .success:
            XCTAssert(false)
        case.failure(let error):
            XCTAssertEqual(error, .parameterOutOfRange)
        }
    }

    func testHandleResponseSuccessOpcodeNotImplemented() {
        var response = Data(KEControlPointOpcode.enableACS.rawValue)
        response.append(KEControlPointOpcode.enableACS.rawValue)
        response.append(KEControlPointResponseCode.success.rawValue)

        let (result, _) = keyExchangeControlPoint.handleResponse(response)
        switch result {
        case .success:
            XCTAssert(false)
        case.failure(let error):
            XCTAssertEqual(error, .opcodeNotImplemented)
        }
    }

    func testProcedureIDForResponse() {
        var response = Data(KEControlPointOpcode.responseCode.rawValue)
        response.append(KEControlPointOpcode.enableACS.rawValue)
        response.append(KEControlPointResponseCode.success.rawValue)

        let procedureID = keyExchangeControlPoint.procedureIDForResponse(response)
        XCTAssertEqual(procedureID, KEControlPointOpcode.enableACS.procedureID)
    }

    func testProcedureIDForRequest() {
        let request = Data(KEControlPointOpcode.enableACS.rawValue)
        let procedureID = keyExchangeControlPoint.procedureIDForRequest(request)
        XCTAssertEqual(procedureID, KEControlPointOpcode.enableACS.procedureID)
    }
}
