//
//  SWWebImageManager.swift
//  SWWebImage
//
//  Created by GoldRatio on 8/14/14.
//  Copyright (c) 2014 GoldRatio. All rights reserved.
//

import Foundation
import UIKit
import ImageIO

public enum SWImageCacheType: Int {
    case None, Disk, Memory
}

//var kPNGSignatureData: NSData?
//let kPNGSignatureBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

public typealias SWWebImageCompletionWithFinishedHandler = (UIImage?, NSError?, SWImageCacheType , Bool , NSURL? ) -> Void

public typealias SDWebImageQueryCompletedHandler = (UIImage?, SWImageCacheType ) -> Void

extension Dictionary {
    
    func sortedKeys(isOrderedBefore: (Key, Key) -> Bool) -> [Key] {
        var array = Array(self.keys)
        sort(&array, isOrderedBefore)
        return array
    }
    
    func keysSortedByValue(isOrderedBefore:(Value, Value) -> Bool) -> [Key] {
        var array = Array(self)
        sort(&array) {
            let (lk, lv) = $0
            let (rk, rv) = $1
            return isOrderedBefore(lv, rv)
        }
        return array.map {
            let (k, v) = $0
            return k
        }
    }
    
}



public class SWImageCache
{
    var maxMemoryCost: UInt = 0
    var maxCacheSize: UInt = 0
    var maxCacheAge: Double = 60 * 60 * 24 * 7 // 1 week
    
    let ioQueue: dispatch_queue_t
    let memCache: NSCache
    let diskCachePath: String
    
    var fileManager: NSFileManager?
    
    let kPNGSignatureData: NSData
    
    var customPaths: Array<String>?
    
    
    public class var sharedImageCache: SWImageCache {
        struct Singleton {
            static let instance = SWImageCache()
        }
        return Singleton.instance
    }
    
    init(namespace: String = "default") {
        let fullNamespace = "org.goldratio.SWWebImageCache.\(namespace)"
        ioQueue = dispatch_queue_create("org.goldratio.SWWebImageCache", nil)
        memCache = NSCache()
        memCache.name = fullNamespace
        let paths = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.CachesDirectory, NSSearchPathDomainMask.UserDomainMask, true)
        
        diskCachePath = paths[0].stringByAppendingPathComponent(fullNamespace)
        
        //TODO
        //self.fileManager = NSFileManager()
        
//        dispatch_sync(ioQueue, {
//            self.fileManager = NSFileManager()
//        })
        let pngPrefix = UnsafePointer<UInt8>([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        kPNGSignatureData = NSData(bytes: pngPrefix, length: 8)

        dispatch_sync(self.ioQueue) {
            self.fileManager = NSFileManager.defaultManager()
        }
        
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: "clearMemory",
            name: UIApplicationDidReceiveMemoryWarningNotification,
            object: nil)

        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: "cleanDisk",
            name: UIApplicationWillTerminateNotification,
            object: nil)

        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: "backgroundCleanDisk",
            name: UIApplicationDidEnterBackgroundNotification,
            object: nil)
    }
    
    
    func ImageDataHasPNGPreffix(data: NSData) -> Bool {
        let pngSignatureLength = kPNGSignatureData.length
        if data.length >= pngSignatureLength {
            if data.subdataWithRange(NSMakeRange(0, pngSignatureLength)).isEqualToData(kPNGSignatureData) {
                return true
            }
        }
        return false
    }
    
    func addReadOnlyCachePath(path: String) {
        if var customs = self.customPaths? {
            customs.append(path)
        }
        else {
            self.customPaths = [path]
        }
    }
    
    func clearMemory() {
        self.memCache.removeAllObjects()
    }
    
    func cleanDisk() {
        self.cleanDiskWithCompletionBlock(nil)
    }
    
    func backgroundCleanDisk() {
        let application = UIApplication.sharedApplication()
        
        var bgTask:UIBackgroundTaskIdentifier = application.beginBackgroundTaskWithExpirationHandler() {}
        bgTask = application.beginBackgroundTaskWithExpirationHandler() {
            application.endBackgroundTask(bgTask)
            bgTask = UIBackgroundTaskInvalid
        }
        
        self.cleanDiskWithCompletionBlock { () -> Void in
            application.endBackgroundTask(bgTask)
            bgTask = UIBackgroundTaskInvalid
        }
    }
    
    func cleanDiskWithCompletionBlock(completeHandler: (() -> Void)?) {
        dispatch_async(self.ioQueue, {
            if let fileManager = self.fileManager? {
                if let diskCacheURL = NSURL.fileURLWithPath(self.diskCachePath, isDirectory: true)? {
                    let resourceKeys = [NSURLIsDirectoryKey, NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey]
                    let fileEnumerator = fileManager.enumeratorAtURL(diskCacheURL, includingPropertiesForKeys: resourceKeys,
                        options: NSDirectoryEnumerationOptions.SkipsHiddenFiles, errorHandler: nil)
                    let expirationDate = NSDate(timeIntervalSinceNow: -self.maxCacheAge)
                    var cacheFiles = [NSURL: AnyObject]()
                    var currentCacheSize: UInt = 0
                    var urlsToDelete = [NSURL]()
                
                    for fileURL in fileEnumerator.allObjects {
                        if let fileURL = fileURL as? NSURL {
                            if var resourceValues = fileURL.resourceValuesForKeys(resourceKeys, error: nil)? {
                                let isDir = (resourceValues[NSURLIsDirectoryKey] as NSNumber).boolValue
                                if isDir {
                                    continue
                                }
                                let modificationDate = resourceValues[NSURLContentModificationDateKey] as NSDate
                                if modificationDate.laterDate(expirationDate).isEqualToDate(expirationDate) {
                                    urlsToDelete.append(fileURL)
                                    continue
                                }
                                let totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey] as NSNumber
                                currentCacheSize += totalAllocatedSize
                                cacheFiles[fileURL] = resourceValues
                            }
                        }
                    }
                
                    for fileUrl in urlsToDelete {
                        fileManager.removeItemAtURL(fileUrl, error: nil)
                    }
                    if (currentCacheSize > self.maxCacheSize) {
                        let desiredCacheSize = self.maxCacheSize / 2
                        let sortedFiles = cacheFiles.keysSortedByValue({ (value1, value2) -> Bool in
                            let startDate: NSDate = value1[NSURLContentModificationDateKey] as NSDate
                            let endDate:NSDate = value2[NSURLContentModificationDateKey] as NSDate
                        
                            return startDate.compare(endDate).toRaw() < 0
                        })
                    
                        for fileUrl in sortedFiles {
                            if fileManager.removeItemAtURL(fileUrl, error: nil) {
                                let resourceValues = cacheFiles[fileUrl] as NSDictionary
                                let totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey] as NSNumber
                                currentCacheSize -= totalAllocatedSize
                                if (currentCacheSize < desiredCacheSize) {
                                    break
                                }
                            }
                        }
                    }
                    if let complete = completeHandler? {
                        dispatch_async(dispatch_get_main_queue(), complete)
                    }
                }
                
            }
        })
    }
    
    func queryDiskCache(key: String?, doneHandler: SDWebImageQueryCompletedHandler?) -> NSOperation? {
        if let done = doneHandler? {
            if let key = key? {
                if let image = self.imageFromMemoryCache(key) {
                    done(image, SWImageCacheType.Memory)
                    return nil
                }
                else {
                    let operation = NSOperation()
                    dispatch_async(self.ioQueue, {
                        if operation.cancelled {
                            return
                        }
                        autoreleasepool {
                            let diskImage = self.diskImage(key)
                            if let image = diskImage? {
                                let cost: Int = Int(image.size.height * image.size.width * image.scale)
                                self.memCache.setObject(image, forKey: key, cost: cost)
                            }
                            dispatch_async(dispatch_get_main_queue(), {
                                done(diskImage, SWImageCacheType.Disk)
                            })
                        }
                    })
                    return operation
                }
                
            }
            else {
                done(nil, SWImageCacheType.None)
                return nil
            }
        }
        else {
            return nil
        }
    }
    
    func imageFromMemoryCache(key: String )-> UIImage? {
        return self.memCache.objectForKey(key) as? UIImage
    }
    
    
    
    func diskImage(key: String) -> UIImage? {
        if let data = self.diskImageDataBySearchingAllPaths(key)? {
            var image = imageWithData(data)
            image = self.scaledImage(key, image: image)
            image = decodedImageWithImage(image!)
            return image
        }
        return nil
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
    
    func diskImageDataBySearchingAllPaths(key: String) -> NSData? {
        let defaultPath = self.defaultCachePath(key)

        if let data = NSData.dataWithContentsOfFile(defaultPath, options: NSDataReadingOptions.DataReadingUncached, error: nil)? {
            return data
        }
        if let customs = self.customPaths? {
            for path in customs {
                let filePath = self.cachePath(key, path: path)
                if let imageData = NSData.dataWithContentsOfFile(defaultPath, options: NSDataReadingOptions.DataReadingUncached, error: nil)? {
                //let imageData = NSData(contentsOfFile: filePath)
                //if imageData != nil {
                    return imageData
                }
            }
        }
        return nil
    }
    
    func cachePath(key: String, path: String) -> String {
        let fileName = self.cachedFileName(key)
        return path.stringByAppendingPathComponent(fileName)
    }
    
    func cachedFileName(key: String) -> String {
        var hashValue = key.hashValue
        return hashValue.description
    }
    
    
    //- (void)storeImage:(UIImage *)image recalculateFromImage:(BOOL)recalculate imageData:(NSData *)imageData forKey:(NSString *)key toDisk:(BOOL)toDisk {
    func store(image: UIImage?, recalculate: Bool, imageData: NSData?, key: NSString?, toDisk: Bool) {
        if (image == nil || key == nil) {
            return
        }
        
        let cost: Int = Int(image!.size.height * image!.size.width * image!.scale)
        self.memCache.setObject(image!, forKey: key!, cost: cost)
        if toDisk {
            dispatch_async(self.ioQueue, {
                var data: NSData? = imageData
                if (recalculate || imageData == nil) {
                    var imageIsPng = true
                    if let imageData = imageData? {
                        if (imageData.length >= self.kPNGSignatureData.length) {
                            imageIsPng = self.ImageDataHasPNGPreffix(imageData)
                        }
                    }
                    
                    if (imageIsPng) {
                        data = UIImagePNGRepresentation(image)
                    }
                    else {
                        data = UIImageJPEGRepresentation(image, 1.0)
                    }
                }
                if let data = data? {
                    if let fileManager = self.fileManager? {
                        if !fileManager.fileExistsAtPath(self.diskCachePath) {
                            fileManager.createDirectoryAtPath(self.diskCachePath, withIntermediateDirectories: true, attributes: nil, error: nil)
                        }
                        fileManager.createFileAtPath(self.defaultCachePath(key!), contents: data, attributes: nil)
                    }
                }
            })
        }
    }
    
    func defaultCachePath(key: String ) -> String {
        return self.cachePath(key, path: self.diskCachePath)
    }
    
    func getSize() -> UInt {
        var size: UInt = 0
        if let fileManager = self.fileManager? {
            
            dispatch_sync(self.ioQueue, {
                if fileManager.fileExistsAtPath(self.diskCachePath) {
                    let fileEnumerator = fileManager.enumeratorAtPath(self.diskCachePath)
                    for fileName in fileEnumerator.allObjects {
                        let filePath = self.diskCachePath.stringByAppendingPathComponent(fileName as String)
                        if let attrs = NSFileManager.defaultManager().attributesOfItemAtPath(filePath, error: nil) {
                            let fileSize: AnyObject? = attrs[NSFileSize]
                            if let fileSize = (fileSize as? UInt)? {
                                size += fileSize
                            }
                        }
                    }
                }
            })
        }
        return size
    }
}

func ==(lhs: SWWebImageCombinedOperation, rhs: SWWebImageCombinedOperation) -> Bool
{
   return lhs.cancelled == rhs.cancelled && lhs.cacheOperation == rhs.cacheOperation
}
class SWWebImageCombinedOperation: SWWebImageOperation, Equatable
{
    var cancelled: Bool
    var cancelHandler: SWWebImageNoParamsHandler?
    
    var canceler: SWWebImageNoParamsHandler? {
        get {
            return cancelHandler
        }
        set {
            if (self.cancelled) {
                if let canceler = newValue? {
                    canceler()
                }
                cancelHandler = nil // don't forget to nil the cancelBlock, otherwise we will get crashes
            }
            else {
                cancelHandler = newValue
            }
        }
    }
    
    var cacheOperation: NSOperation?
    
    init() {
        cancelled = false
    }
    
    func cancel() {
        self.cancelled = true
        if let cacheOp = cacheOperation? {
            cacheOp.cancel()
            self.cacheOperation = nil
        }
        if let cancel = cancelHandler? {
            cancel()
            self.cancelHandler = nil
        }
    }
    
}

func synced(lock: AnyObject, closure: () -> ()) {
    objc_sync_enter(lock)
    closure()
    objc_sync_exit(lock)
}

func dispatch_main_sync_safe(closure: () -> ()) {
    if NSThread.isMainThread() {
        closure()
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), closure)
    }
}

protocol SWWebImageManagerDelegate
{
    func shouldDownlodImage(imageManager: SWWebImageManager, imageUrl: NSURL) -> Bool
    
    func transformDownloadedImage(imageManager: SWWebImageManager, image: UIImage?, imageUrl: NSURL) -> UIImage
}

public class SWWebImageManager
{
    let imageCache: SWImageCache
    let imageDownloader: SWWebImageDownloader
    var failedURLs: Array<NSURL>
    var runningOperations: Array<SWWebImageCombinedOperation>
    var delegate: SWWebImageManagerDelegate?
    
    public class var sharedManager: SWWebImageManager {
        struct Singleton {
            static let instance = SWWebImageManager()
        }
        return Singleton.instance
    }
    
    init() {
        imageCache = SWImageCache.sharedImageCache
        imageDownloader = SWWebImageDownloader.sharedDownloader
        failedURLs = [NSURL]()
        runningOperations = [SWWebImageCombinedOperation]()
    }
    
    
    public func downloadImage(url: NSURL,
        options: SWWebImageOptions,
        progress: SWWebImageDownloaderProgressHandler?,
        completeHandler: SWWebImageCompletionWithFinishedHandler!) -> SWWebImageOperation {
            let operation = SWWebImageCombinedOperation()
            var isFailedUrl = false
            synced(self.failedURLs) {
                isFailedUrl = contains(self.failedURLs, url)
            }
            
            if(isFailedUrl && options.toRaw() & SWWebImageOptions.RetryFailed.toRaw() == 0) {
                let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: nil)
                completeHandler(nil, error, SWImageCacheType.None, true, url)
                return operation
            }
            synced(self.runningOperations) {
                self.runningOperations.append(operation)
            }
            
            let key = self.cacheKeyForURL(url)
            operation.cacheOperation = self.imageCache.queryDiskCache(key, doneHandler: { (image: UIImage?, cacheType: SWImageCacheType) -> Void in
                if operation.cancelled {
                    synced(self.runningOperations) {
                        if let index = find(self.runningOperations, operation)? {
                            self.runningOperations.removeAtIndex(index)
                        }
                    }
                    return
                }
                if (options & SWWebImageOptions.RefreshCached).boolValue {

                }
                if (image == nil || (options & SWWebImageOptions.RefreshCached).boolValue ) &&
                    (self.delegate == nil || self.delegate!.shouldDownlodImage(self, imageUrl: url)) {
                        
                        if image != nil && options.toRaw() &  SWWebImageOptions.RefreshCached.toRaw() != 0 {
                            dispatch_main_sync_safe {
                                completeHandler(image, nil, cacheType, true, nil)
                            }
                        }
                        
                        var downloaderOptions = SWWebImageDownloaderOptions.None
                        if (options & SWWebImageOptions.LowPriority).boolValue {
                            downloaderOptions = downloaderOptions | SWWebImageDownloaderOptions.LowPriority
                        }
                        if (options & SWWebImageOptions.ProgressiveDownload).boolValue {
                            downloaderOptions = downloaderOptions | SWWebImageDownloaderOptions.ProgressiveDownload
                        }
                        if (options & SWWebImageOptions.RefreshCached).boolValue {
                            downloaderOptions = downloaderOptions | SWWebImageDownloaderOptions.UseNSURLCache
                        }
                        if (options & SWWebImageOptions.ContinueInBackground).boolValue {
                            downloaderOptions = downloaderOptions | SWWebImageDownloaderOptions.ContinueInBackground
                        }
                        if (options & SWWebImageOptions.HandleCookies).boolValue {
                            downloaderOptions = downloaderOptions | SWWebImageDownloaderOptions.HandleCookies
                        }
                        if (options & SWWebImageOptions.AllowInvalidSSLCertificates).boolValue {
                            downloaderOptions = downloaderOptions | SWWebImageDownloaderOptions.AllowInvalidSSLCertificates
                        }
                        if (options & SWWebImageOptions.HighPriority).boolValue {
                            downloaderOptions = downloaderOptions | SWWebImageDownloaderOptions.HighPriority
                        }
                        
                        if image != nil && (options & SWWebImageOptions.RefreshCached).boolValue {
                            downloaderOptions = downloaderOptions & ~SWWebImageDownloaderOptions.ProgressiveDownload
                            downloaderOptions = downloaderOptions | SWWebImageDownloaderOptions.IgnoreCachedResponse
                        }
                        
                        let subOperation = self.imageDownloader.downloadImage(url,
                            options: downloaderOptions,
                            progressHandler: progress,
                            completeHandler: { (downloadedImage: UIImage?, data: NSData?, error: NSError?, finished: Bool) -> Void in
                            
                            if operation.cancelled {
                                
                            }
                            else if error != nil {
                                dispatch_main_sync_safe({ () -> () in
                                    if !operation.cancelled {
                                        completeHandler(nil, error, SWImageCacheType.None, finished, url)
                                    }
                                })
                                
                                if (error!.code != NSURLErrorNotConnectedToInternet &&
                                    error!.code != NSURLErrorCancelled &&
                                    error!.code != NSURLErrorTimedOut) {
                                        synced(self.failedURLs) {
                                            self.failedURLs.append(url)
                                        }
                                }
                            }
                            else {
                                var cacheOnDisk = options.toRaw() & SWWebImageOptions.CacheMemoryOnly.toRaw() == 0
                                
                                if options.toRaw() & SWWebImageOptions.RefreshCached.toRaw() != 0 && image != nil && downloadedImage == nil {
                                    
                                }
                                else if downloadedImage != nil && (downloadedImage?.images == nil || options.toRaw() & SWWebImageOptions.TransformAnimatedImage.toRaw() != 0) && self.delegate != nil {
                                    
                                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), {
                                        let transformedImage = self.delegate?.transformDownloadedImage(self, image: downloadedImage, imageUrl: url)
                                        
                                        if transformedImage != nil && finished {
                                            let imageWasTransformed = transformedImage == downloadedImage
                                            self.imageCache.store(transformedImage!,
                                                recalculate: imageWasTransformed,
                                                imageData: data!,
                                                key: key,
                                                toDisk: cacheOnDisk)
                                        }
                                        
                                        dispatch_main_sync_safe{
                                            if !operation.cancelled {
                                                completeHandler(transformedImage, nil, SWImageCacheType.None, finished, url)
                                            }
                                        }
                                    })
                                    
                                }
                                else {
                                    if (downloadedImage != nil && finished) {
                                        self.imageCache.store(downloadedImage, recalculate: false, imageData: data!, key: key, toDisk: cacheOnDisk)
                                    }
                                    
                                    dispatch_main_sync_safe({
                                        if !operation.cancelled {
                                            completeHandler(downloadedImage, nil, SWImageCacheType.None, finished, url)
                                        }
                                    })
                                }
                            
                            }
                            if (finished) {
                                synced(self.runningOperations) {
                                    if let index = find(self.runningOperations, operation)? {
                                        self.runningOperations.removeAtIndex(index)
                                    }
                                }
                            }
                        })
                        
                        operation.canceler = {
                            subOperation?.cancel()
                            
                            synced(self.runningOperations) {
                                if let index = find(self.runningOperations, operation)? {
                                    self.runningOperations.removeAtIndex(index)
                                }
                            }
                        }
                }
                else if image != nil {
                    dispatch_main_sync_safe {
                        
                        if !operation.cancelled {
                            completeHandler(image, nil, cacheType, true, url)
                        }
                    }
                    synced(self.runningOperations) {
                        if let index = find(self.runningOperations, operation)? {
                            self.runningOperations.removeAtIndex(index)
                        }
                    }
                }
            })
            return operation
    }
    
    func cacheKeyForURL(url: NSURL) -> String? {
        return url.absoluteString
    }
}

