//
//  ArrayTests.swift
//  RocheSoloKitTests
//
//  Created by Nathaniel Hamming on 2021-09-14.
//  Copyright © 2021 Tidepool Project. All rights reserved.
//

import XCTest
@testable import RocheSoloKit

class ArrayTests: XCTestCase {
    func testChunked() {
        let array = [1,2,3,4,5,6,7,8,9,10]
        let chunkedArrays = array.chunked(into: 2)
        XCTAssertEqual(chunkedArrays.count, 5)
        var counter = 0
        for chunkedArray in chunkedArrays {
            XCTAssertEqual(chunkedArray.count, 2)
            for i in 0...1 {
                XCTAssertEqual(chunkedArray[i], array[counter+i])
            }
            counter+=2
        }
    }

    func testSafeIndex() {
        let array = [0,1,2,3,4,5,6,7,8,9]
        XCTAssertEqual(array[safe: 1], 1)
        XCTAssertNil(array[safe: 11])
    }

    func testMakeInfiniteLoopIterator() {
        let array = [1,2,3,4,5,6,7,8,9,10]
        let infiniteIterator = array.makeInfiniteLoopIterator()
        for _ in 1...25 {
            _ = infiniteIterator.next()
        }
        XCTAssertEqual(infiniteIterator.next(), 6)
    }
}
