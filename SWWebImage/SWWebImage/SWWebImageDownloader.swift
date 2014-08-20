//
//  SWWebImageDownloader.swift
//  SWWebImage
//
//  Created by GoldRatio on 8/15/14.
//  Copyright (c) 2014 GoldRatio. All rights reserved.
//

import Foundation
import UIKit


let SWWebImageDownloadStartNotification = "SWWebImageDownloadStartNotification"
let SWWebImageDownloadStopNotification = "SWWebImageDownloadStopNotification"

enum SWWebImageDownloaderExecutionOrder : Int {
    /**
    * Default value. All download operations will execute in queue style (first-in-first-out).
    */
    case SWWebImageDownloaderFIFOExecutionOrder,
    
    /**
    * All download operations will execute in stack style (last-in-first-out).
    */
    SWWebImageDownloaderLIFOExecutionOrder
}


struct SWWebImageDownloaderOptions : RawOptionSetType {
    private var value: UInt = 0
    init(_ value: UInt) { self.value = value }
    var boolValue: Bool { return self.value != 0 }
    func toRaw() -> UInt { return self.value }
    static func fromRaw(raw: UInt) -> SWWebImageDownloaderOptions? { return self(raw) }
    static func fromMask(raw: UInt) -> SWWebImageDownloaderOptions { return self(raw) }
    static func convertFromNilLiteral() -> SWWebImageDownloaderOptions { return self(0) }
    
    static var allZeros: SWWebImageDownloaderOptions { return self(0) }
    static var None: SWWebImageDownloaderOptions          { return self(0) }
    static var LowPriority: SWWebImageDownloaderOptions   { return self(1 << 0) }
    static var ProgressiveDownload: SWWebImageDownloaderOptions  { return self(1 << 1) }
    static var UseNSURLCache: SWWebImageDownloaderOptions   { return self(1 << 2) }
    static var IgnoreCachedResponse: SWWebImageDownloaderOptions   { return self(1 << 3) }
    static var ContinueInBackground: SWWebImageDownloaderOptions   { return self(1 << 4) }
    static var HandleCookies: SWWebImageDownloaderOptions   { return self(1 << 5) }
    static var AllowInvalidSSLCertificates: SWWebImageDownloaderOptions   { return self(1 << 6) }
    static var HighPriority: SWWebImageDownloaderOptions   { return self(1 << 7) }
}
func == (lhs: SWWebImageDownloaderOptions, rhs: SWWebImageDownloaderOptions) -> Bool     { return lhs.value == rhs.value }

//enum SWWebImageDownloaderOptions: Int {
//    case LowPriority = 1
//    case ProgressiveDownload = 2
//    case UseNSURLCache = 4
//    case IgnoreCachedResponse = 8
//    case ContinueInBackground = 16
//    case HandleCookies = 32
//    case AllowInvalidSSLCertificates = 64
//    case HighPriority = 128
//}

public typealias SWWebImageDownloaderProgressHandler = (Int, Int) -> Void
public typealias SWWebImageDownloaderCompletedHandler = (UIImage?, NSData?, NSError?, Bool) -> Void
public typealias SWWebImageNoParamsHandler = () -> Void


class URLCallback
{
    var progressCallback: SWWebImageDownloaderProgressHandler?
    var completeCallback: SWWebImageDownloaderCompletedHandler?
    
    init(progressCallback: SWWebImageDownloaderProgressHandler?, completeCallback: SWWebImageDownloaderCompletedHandler?) {
        self.progressCallback = progressCallback
        self.completeCallback = completeCallback
    }
}

class SWWebImageDownloader
{
    var maxConcurrentDownloads: Int = 10
    var downloadTimeout: NSTimeInterval = 3
    var currentDownloadCount: Int = 0
    
    let executionOrder: SWWebImageDownloaderExecutionOrder
    let downloadQueue: NSOperationQueue
    var URLCallbacks = [NSURL: Array<URLCallback>]()
    let HTTPHeaders: [String: String]
    let barrierQueue: dispatch_queue_t
    
    var lastAddedOperation: NSOperation?
    
    var username: String?
    var password: String?
    
    
    init() {
        executionOrder = .SWWebImageDownloaderFIFOExecutionOrder
        downloadQueue = NSOperationQueue()
        downloadQueue.maxConcurrentOperationCount = 2
        HTTPHeaders = ["Accept":"image/webp,image/*;q=0.8"]
        
        barrierQueue = dispatch_queue_create("org.goldratio.SWWebImageDownloaderBarrierQueue", DISPATCH_QUEUE_CONCURRENT);
        downloadTimeout = 15.0;
    }
    
    deinit {
        self.downloadQueue.cancelAllOperations()
        dispatch_release(barrierQueue)
    }
    
    class var sharedDownloader: SWWebImageDownloader {
        struct Singleton {
            static let instance = SWWebImageDownloader()
        }
        return Singleton.instance
    }
    
    func downloadImage(url: NSURL, options: SWWebImageDownloaderOptions, progressHandler: SWWebImageDownloaderProgressHandler?,
        completeHandler: SWWebImageDownloaderCompletedHandler?) -> SWWebImageOperation? {
            var imageOperation: SWWebImageOperation?
        self.addProgressCallback(progressHandler, completeHandler: completeHandler, url: url) { () -> Void in
            
            let policy = options.toRaw() & SWWebImageDownloaderOptions.UseNSURLCache.toRaw() != 0 ? NSURLRequestCachePolicy.UseProtocolCachePolicy :
                NSURLRequestCachePolicy.ReloadIgnoringLocalAndRemoteCacheData
            let request = NSMutableURLRequest(URL: url, cachePolicy: policy, timeoutInterval: self.downloadTimeout)
            request.HTTPShouldHandleCookies = options.toRaw() & SWWebImageDownloaderOptions.HandleCookies.toRaw() != 0
            request.HTTPShouldUsePipelining = true
            
            let operation = SWWebImageDownloaderOperation(request: request,
                options: options,
                progressHandler: { (receivedSize: Int, expectedSize: Int) -> Void in
                if let callbacksForURL = self.callbacksForURL(url)? {
                    for callback in callbacksForURL {
                        if let progressCallback = callback.progressCallback? {
                            progressCallback(receivedSize, expectedSize)
                        }
                    }
                }
                
            }, completeHandler: { (image: UIImage?, data: NSData?, error: NSError?, finished: Bool) -> Void in
                let callbacks = self.callbacksForURL(url)
                if(finished) {
                    self.removeCallbacksForURL(url)
                }
                if let callbacksForURL = callbacks? {
                    for callback in callbacksForURL {
                        if let completeCallback = callback.completeCallback? {
                            completeCallback(image, data, error, finished)
                        }
                    }
                }
                
            }, cancelHandler: { () -> Void in
                self.removeCallbacksForURL(url)
            })
            if let name = self.username? {
                operation.credential = NSURLCredential(user: name, password: self.password!, persistence: NSURLCredentialPersistence.ForSession)
            }
            if options.toRaw() & SWWebImageDownloaderOptions.HighPriority.toRaw() != 0 {
                operation.queuePriority = NSOperationQueuePriority.High
            }
            else if options.toRaw() & SWWebImageDownloaderOptions.LowPriority.toRaw() != 0 {
                operation.queuePriority = NSOperationQueuePriority.Low
            }
            self.downloadQueue.addOperation(operation)
            
            if self.executionOrder == SWWebImageDownloaderExecutionOrder.SWWebImageDownloaderLIFOExecutionOrder {
                self.lastAddedOperation?.addDependency(operation)
                self.lastAddedOperation = operation
            }
            imageOperation = operation
        }
        return imageOperation
    }
    
    func addProgressCallback(progressHandler: ((Int, Int) -> Void)?,
        completeHandler: ((UIImage?, NSData?, NSError?, Bool) -> Void)?,
        url: NSURL,
        createCallback: (() -> Void)? ) {
            
            let this = self
            dispatch_barrier_sync(self.barrierQueue, {() -> Void in
                var first = false
                if self.URLCallbacks[url] == nil {
                    self.URLCallbacks[url] = [URLCallback]()
                    first = true
                }
                
                var callbacks =  URLCallback(progressCallback: progressHandler, completeCallback: completeHandler)
               self.URLCallbacks[url]?.append(callbacks)
                
                
                if (first) {
                    createCallback?()
                }
            })
    }
    
    func callbacksForURL(url: NSURL) -> Array<URLCallback>? {
        var callbacksForURL: Array<URLCallback>? = nil
        dispatch_sync(self.barrierQueue, {
            callbacksForURL = self.URLCallbacks[url]
        })
        return callbacksForURL
    }
    
    func removeCallbacksForURL(url: NSURL) {
        dispatch_barrier_async(self.barrierQueue, {
            let test = self.URLCallbacks.removeValueForKey(url)
        })
    }
}