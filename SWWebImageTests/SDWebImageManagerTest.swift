//
//  SDWebImageManagerTest.swift
//  SWWebImage
//
//  Created by GoldRatio on 8/20/14.
//  Copyright (c) 2014 GoldRatio. All rights reserved.
//

import Foundation
import UIKit
import XCTest
import SWWebImage

class SDWebImageManagerTest: XCTestCase
{
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testThatDownloadInvokesCompletionBlockWithCorrectParamsAsync() {
        let originalImageURL = NSURL(string: "http://static2.dmcdn.net/static/video/656/177/44771656:jpeg_preview_small.jpg?20120509154705")
        
        let readyExpectation = expectationWithDescription("ready")
        
        SWWebImageManager.sharedManager.downloadImage(originalImageURL, options: SWWebImageOptions.None, progress: nil,
            completeHandler: { (downloadedImage: UIImage?, error: NSError?, options: SWImageCacheType, finished: Bool, url: NSURL?) -> Void in
                XCTAssertNotNil(downloadedImage)
                XCTAssertNil(error)
                XCTAssertNotNil(url)
                XCTAssertEqual(url!, originalImageURL)
                
                readyExpectation.fulfill()
        })
        
        self.waitForExpectationsWithTimeout(5.0, handler: { error in
            XCTAssertNil(error, "Error")
        })
    }
}