//
//  SDImageCacheTests.swift
//  SWWebImage
//
//  Created by GoldRatio on 8/20/14.
//  Copyright (c) 2014 GoldRatio. All rights reserved.
//

import Foundation
import XCTest
import SWWebImage


class SWImageCacheTests : XCTestCase
{
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        XCTAssert(true, "Pass")
    }
    
    func testSharedImageCache() {
        // This is an example of a performance test case.
        let sharedImageCache = SWImageCache.sharedImageCache
        XCTAssertNotNil(sharedImageCache)
    }
}