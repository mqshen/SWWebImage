//
//  SWWebImageDownloaderOperation.swift
//  SWWebImage
//
//  Created by GoldRatio on 8/15/14.
//  Copyright (c) 2014 GoldRatio. All rights reserved.
//

import Foundation
import UIKit
import ImageIO


class SWWebImageDownloaderOperation : NSOperation, SWWebImageOperation, NSURLConnectionDataDelegate
{
    let request: NSURLRequest
    let shouldUseCredentialStorage: Bool
    var credential: NSURLCredential?
    let options: SWWebImageDownloaderOptions
    
    var backgroundTaskId: UIBackgroundTaskIdentifier?
    var connection: NSURLConnection?
    var thread: NSThread?
    
    
    var progressHandler: SWWebImageDownloaderProgressHandler?
    var completeHandler: SWWebImageDownloaderCompletedHandler?
    var cancelHandler: SWWebImageNoParamsHandler?
    
    var imageData: NSMutableData?
    
    //var executing: Bool
    var _isExecuting: Bool = false
    var _isFinished: Bool = false
    
    override var executing: Bool {
        get {
            return _isExecuting
        }
        set {
            if executing == newValue {
                return
            }
            willChangeValueForKey("isExecuting")
            self._isExecuting = newValue
            didChangeValueForKey("isExecuting")
        }
    }
    
    override var finished: Bool {
        get {
            return _isFinished
        }
        set {
            if self._isFinished == newValue {
                return
            }
            willChangeValueForKey("isFinished")
            self._isFinished = newValue
            didChangeValueForKey("isFinished")
        }
    }
    
//    func setExecuting(setExecuting: Bool) {
//        if executing == setExecuting {return}
//        willChangeValueForKey("isExecuting")
//        _isExecuting = setExecuting
//        didChangeValueForKey("isExecuting")
//    }
//    
//    func setFinished(setFinished: Bool) {
//        if finished == setFinished {return}
//        willChangeValueForKey("isFinished")
//        _isFinished = setFinished
//        didChangeValueForKey("isFinished")
//    }
    
    var expectedSize: Int
    var responseFromCached: Bool
    
    
    var width: UInt
    var height: UInt
    var orientation: UIImageOrientation
    
    
    init(request: NSURLRequest,
        options: SWWebImageDownloaderOptions,
        progressHandler: SWWebImageDownloaderProgressHandler?,
        completeHandler: SWWebImageDownloaderCompletedHandler?,
        cancelHandler: SWWebImageNoParamsHandler?) {
            self.request = request
            self.shouldUseCredentialStorage = true
            self.progressHandler = progressHandler
            self.completeHandler = completeHandler
            self.cancelHandler = cancelHandler
            self.expectedSize = 0
            self.responseFromCached = true
            self.options = SWWebImageDownloaderOptions.ContinueInBackground
            self.width = 0
            self.height = 0
            self.orientation = UIImageOrientation.Up
            
            super.init()
    }
    
    
    override func start() {
        synced(self) {
            if self.cancelled {
                self.finished = true
                self.reset()
                return
            }
            if self.shouldContinueWhenAppEntersBackground() {
                self.backgroundTaskId = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler({ () -> Void in
                    self.cancel()
                    if let backgroundTaskId = self.backgroundTaskId? {
                        UIApplication.sharedApplication().endBackgroundTask(backgroundTaskId)
                    }
                    self.backgroundTaskId = UIBackgroundTaskInvalid
                })
            }
            
            self.executing = true
            self.connection = NSURLConnection(request: self.request, delegate: self, startImmediately: false)
            self.thread = NSThread.currentThread()
        }
        if let connection = self.connection? {
            connection.start()
            
            if let progressHandler = self.progressHandler? {
                progressHandler(0, -1)
            }
            NSNotificationCenter.defaultCenter().postNotificationName(SWWebImageDownloadStartNotification, object: self)
            
            if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_5_1) {
                // Make sure to run the runloop in our background thread so it can process downloaded data
                // Note: we use a timeout to work around an issue with NSURLConnection cancel under iOS 5
                //       not waking up the runloop, leading to dead threads (see https://github.com/rs/SDWebImage/issues/466)
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 10.0, Boolean(0))
            }
            else {
                CFRunLoopRun()
            }
            
            if !self.finished {
                
            }
            if !self.finished {
                connection.cancel()
                self.connect(self.connection, error: NSError(domain: NSURLErrorDomain , code: NSURLErrorTimedOut, userInfo: [NSURLErrorFailingURLErrorKey: self.request.URL]))
                
            }
        }
        else {
            if let completeHandler = self.completeHandler? {
                completeHandler(nil, nil, NSError(domain: NSURLErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey : "Connection can't be initialized"]), true)
            }
            
        }
        
        
        if let backgroundTaskId = self.backgroundTaskId? {
            if (backgroundTaskId != UIBackgroundTaskInvalid) {
                UIApplication.sharedApplication().endBackgroundTask(backgroundTaskId)
                self.backgroundTaskId = UIBackgroundTaskInvalid
            }
        }
    }
    
    func connect(connection: NSURLConnection?, error: NSError) {
        NSNotificationCenter.defaultCenter().postNotificationName(SWWebImageDownloadStopNotification, object: nil)
        
        if let completeHandler = self.completeHandler? {
            completeHandler(nil, nil, error, true)
        }
        
        self.done()
    }
    
    func done() {
        self.finished = true
        self.executing = false
        self.reset()
    }
    
    
    func shouldContinueWhenAppEntersBackground() -> Bool {
        if (self.options & SWWebImageDownloaderOptions.ContinueInBackground).boolValue {
            return true
        }
        else {
            return false
        }
    }
    
    override func cancel() {
        synced(self) {
            if let thread = self.thread? {
                dispatch_async(dispatch_get_main_queue(), {
                    self.cancelInternalAndStop()
                })
            }
            else {
                self.cancelInternal()
            }
            
        }
    }
    
    func cancelInternalAndStop() {
        if self.finished {
            return
        }
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
    
    func cancelInternal() {
        if self.finished {
            return
        }
        super.cancel()
        if let cancelHandler = self.cancelHandler? {
            cancelHandler()
        }
        
        if let connection = self.connection? {
            connection.cancel()
            NSNotificationCenter.defaultCenter().postNotificationName(SWWebImageDownloadStopNotification, object: self)
            if self.executing {
                self.executing = false
            }
            if !self.finished {
                self.finished = true
            }
        }
        self.reset()
    }
    
    func reset() {
        self.cancelHandler = nil;
        self.completeHandler = nil;
        self.progressHandler = nil;
        self.connection = nil;
        self.imageData = nil;
        self.thread = nil;
    }
    
    func connection(connection: NSURLConnection!, didReceiveResponse response: NSURLResponse!) {
        var statue = 0
        if let httpResponse = response as? NSHTTPURLResponse {
            if httpResponse.statusCode < 400 {
                let expected = response.expectedContentLength > 0 ? response.expectedContentLength : 0
                self.expectedSize = Int(expected)
                if let progressHandler = self.progressHandler? {
                    progressHandler(0, self.expectedSize)
                }
                self.imageData = NSMutableData(capacity: self.expectedSize)
                return
            }
            statue = httpResponse.statusCode
        }
        
        //println(self.request.URL.absoluteURL)
        
        self.connection?.cancel()
        NSNotificationCenter.defaultCenter().postNotificationName(SWWebImageDownloadStopNotification, object: nil)
        
        if let completeHander = self.completeHandler? {
            completeHander(nil, nil, NSError(domain: NSURLErrorDomain, code: statue, userInfo: nil), true)
        }
        CFRunLoopStop(CFRunLoopGetCurrent())
        self.done()
        
    }
    
    
    func connection(connection: NSURLConnection!, didReceiveData data: NSData!) {
        if let imageData = self.imageData? {
            imageData.appendData(data)
            if (self.options & SWWebImageDownloaderOptions.ProgressiveDownload).boolValue && self.expectedSize > 0 {
                if let completeHandler = self.completeHandler? {
                    let totalSize = imageData.length
                    let imageSource = CGImageSourceCreateIncremental(nil)
                    CGImageSourceUpdateData(imageSource, imageData, totalSize == self.expectedSize)
                    if (width + height == 0) {
                        if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)? {
                            var orientationValue: Int = -1
                            let property = properties.__conversion()
                            if let val: AnyObject = property[kCGImagePropertyPixelHeight]? {
                                CFNumberGetValue(val as CFNumber, CFNumberType.LongType, &height)
                            }
                            if let val: AnyObject = property[kCGImagePropertyPixelWidth]? {
                                CFNumberGetValue(val as CFNumber, CFNumberType.LongType, &width)
                            }
                            if let val: AnyObject = property[kCGImagePropertyOrientation]? {
                                CFNumberGetValue(val as CFNumber, CFNumberType.IntType, &orientationValue)
                            }
                            orientation = self.orientationFromPropertyValue(orientationValue == -1 ? 1 : orientationValue)
                        }
                    }
                    
                    if (width + height > 0 && totalSize < self.expectedSize) {
                        if var partialImageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)? {
                            let partialHeight = CGImageGetHeight(partialImageRef)
                            let colorSpace = CGColorSpaceCreateDeviceRGB()
                            
                            let temp: UInt = 8
                            let temp2: UInt = 4
                            if let bmContext = CGBitmapContextCreate(nil, width, height, temp, width * temp2, colorSpace, CGBitmapInfo.fromRaw(CGBitmapInfo.ByteOrderDefault.toRaw() | CGImageAlphaInfo.PremultipliedFirst.toRaw())!)? {
                                
                                CGContextDrawImage(bmContext, CGRectMake(0, 0, CGFloat(width), CGFloat(partialHeight)), partialImageRef);
                                partialImageRef = CGBitmapContextCreateImage(bmContext);
                                
                                var image = UIImage(CGImage: partialImageRef, scale: 1, orientation: orientation)
                                if let key = SWWebImageManager.sharedManager.cacheKeyForURL(self.request.URL)? {
                                    let scaledImage = self.scaledImage(key, image: image)
                                    image = decodedImageWithImage(scaledImage)
                                    if let completeHandler = self.completeHandler? {
                                        dispatch_main_sync_safe {
                                            completeHandler(image, nil, nil, false)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if let progressHandler = self.progressHandler {
                progressHandler(imageData.length, self.expectedSize)
            }
        }
        
        
        
    }
    
    func scaledImage(key: String, image: UIImage!) -> UIImage {
        if image.images != nil && image.images.count > 0 {
            var scaledImages = [UIImage]()
            for tempImage in image.images {
                scaledImages.append(self.scaledImage(key, image: tempImage as? UIImage))
            }
            return UIImage.animatedImageWithImages(scaledImages, duration: image.duration)
        }
        else {
            return image
        }
    }
    
    
    func connectionDidFinishLoading(connection: NSURLConnection!) {
        synced(self) {
            CFRunLoopStop(CFRunLoopGetCurrent())
            self.thread = nil
            self.connection = nil
            NSNotificationCenter.defaultCenter().postNotificationName(SWWebImageDownloadStopNotification, object: nil)
        }
        
        if !((NSURLCache.sharedURLCache().cachedResponseForRequest(self.request)) != nil) {
            self.responseFromCached = false
        }
        
        if let completeHandler = self.completeHandler? {
            if (self.options & SWWebImageDownloaderOptions.IgnoreCachedResponse).boolValue && self.responseFromCached {
                completeHandler(nil, nil, nil, false)
            }
            else {
                var image = imageWithData(self.imageData!)
                if let key = SWWebImageManager.sharedManager.cacheKeyForURL(self.request.URL)? {
                    image = scaledImage(key, image: image)
                    if image?.images == nil {
                        image = decodedImageWithImage(image!)
                    }
                    if (CGSizeEqualToSize(image!.size, CGSizeZero)) {
                        completeHandler(nil, nil, NSError(domain: "SWWebImageErrorDomain", code: 0,
                            userInfo: [NSLocalizedDescriptionKey : "Downloaded image has 0 pixels"]), true)
                    }
                    else {
                        completeHandler(image, self.imageData, nil, true)
                    }
                }
            }
        }
        self.completeHandler = nil
        self.done()
    }
    
    func connection(connection: NSURLConnection!, didFailWithError error: NSError!) {
        CFRunLoopStop(CFRunLoopGetCurrent())
        NSNotificationCenter.defaultCenter().postNotificationName(SWWebImageDownloadStopNotification, object: nil)
        
        if let completeHandler = self.completeHandler? {
            completeHandler(nil, nil, error, true)
        }
        
        self.done()
    }
    
    func connection(connection: NSURLConnection!, willCacheResponse cachedResponse: NSCachedURLResponse!) -> NSCachedURLResponse! {
        responseFromCached = false
        if self.request.cachePolicy == NSURLRequestCachePolicy.ReloadIgnoringLocalCacheData {
            return nil
        }
        return cachedResponse
    }
    
    func connection(connection: NSURLConnection!, willSendRequestForAuthenticationChallenge challenge: NSURLAuthenticationChallenge!) {
        
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            let credential = NSURLCredential(trust: challenge.protectionSpace.serverTrust)
            challenge.sender.useCredential(credential, forAuthenticationChallenge: challenge)
        }
        else {
            if challenge.previousFailureCount == 0 {
                if let credential = self.credential? {
                    challenge.sender.useCredential(credential, forAuthenticationChallenge: challenge)
                }
                else {
                    challenge.sender.continueWithoutCredentialForAuthenticationChallenge(challenge)
                }
            }
            else {
                challenge.sender.continueWithoutCredentialForAuthenticationChallenge(challenge)
            }
        }
    }
    
    
    func orientationFromPropertyValue(value: Int)-> UIImageOrientation{
        switch (value) {
        case 1:
            return UIImageOrientation.Up
        case 3:
            return UIImageOrientation.Down
        case 8:
            return UIImageOrientation.Left
        case 6:
            return UIImageOrientation.Right
        case 2:
            return UIImageOrientation.UpMirrored
        case 4:
            return UIImageOrientation.DownMirrored
        case 5:
            return UIImageOrientation.LeftMirrored
        case 7:
            return UIImageOrientation.RightMirrored
        default:
            return UIImageOrientation.Up
        }
    }
    
}