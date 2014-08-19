//
//  SWWebImageView.swift
//  SWWebImage
//
//  Created by GoldRatio on 8/14/14.
//  Copyright (c) 2014 GoldRatio. All rights reserved.
//

import Foundation
import UIKit

protocol SWWebImageOperation {
    func cancel()
}

struct SWWebImageOptions : RawOptionSetType {
    private var value: UInt = 0
    init(_ value: UInt) { self.value = value }
    var boolValue: Bool { return self.value != 0 }
    func toRaw() -> UInt { return self.value }
    static func fromRaw(raw: UInt) -> SWWebImageOptions? { return self(raw) }
    static func fromMask(raw: UInt) -> SWWebImageOptions { return self(raw) }
    static func convertFromNilLiteral() -> SWWebImageOptions { return self(0) }
    
    static var allZeros: SWWebImageOptions { return self(0) }
    static var None: SWWebImageOptions          { return self(0) }
    static var RetryFailed: SWWebImageOptions   { return self(1 << 0) }
    static var LowPriority: SWWebImageOptions  { return self(1 << 1) }
    static var CacheMemoryOnly: SWWebImageOptions   { return self(1 << 2) }
    static var ProgressiveDownload: SWWebImageOptions   { return self(1 << 3) }
    static var RefreshCached: SWWebImageOptions   { return self(1 << 4) }
    static var ContinueInBackground: SWWebImageOptions   { return self(1 << 5) }
    static var HandleCookies: SWWebImageOptions   { return self(1 << 6) }
    static var AllowInvalidSSLCertificates: SWWebImageOptions   { return self(1 << 7) }
    static var HighPriority: SWWebImageOptions   { return self(1 << 8) }
    static var DelayPlaceholder: SWWebImageOptions   { return self(1 << 9) }
    static var TransformAnimatedImage: SWWebImageOptions   { return self(1 << 10) }
}
func == (lhs: SWWebImageOptions, rhs: SWWebImageOptions) -> Bool     { return lhs.value == rhs.value }

//func &(lhs: SWWebImageOptions, rhs: SWWebImageOptions) -> SWWebImageOptions {
//    return SWWebImageOptions.fromRaw( lhs.value & rhs.value)!
//}
//func |(lhs: SWWebImageOptions, rhs: SWWebImageOptions) -> SWWebImageOptions {
//    return SWWebImageOptions.fromRaw( lhs.value | rhs.value)!
//}
//func ^(lhs: SWWebImageOptions, rhs: SWWebImageOptions) -> SWWebImageOptions {
//    return SWWebImageOptions.fromRaw( lhs.value ^ rhs.value)!
//}
//prefix func ~(lhs: SWWebImageOptions) -> SWWebImageOptions
//{
//    return SWWebImageOptions.fromRaw( ~lhs.value )!
//}

//enum SWWebImageOptions: Int {
//    case RetryFailed = 1
//    case LowPriority = 2
//    case CacheMemoryOnly = 4
//    case ProgressiveDownload = 8
//    case RefreshCached = 16
//    case ContinueInBackground = 32
//    case HandleCookies = 64
//    case AllowInvalidSSLCertificates = 128
//    case HighPriority = 256
//    case DelayPlaceholder = 512
//    case TransformAnimatedImage = 1024
//}

class SWWebImageView : UIImageView
{
    let operations = Dictionary<String, Array<SWWebImageOperation>>()
    
    var url: NSURL?
    
    //func setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder
    func setImage(url: NSURL, placeholderImage: UIImage, options: SWWebImageOptions = SWWebImageOptions.None, progress: SWWebImageDownloaderProgressHandler? = nil) {
        self.cancelCurrentImageLoad()
        self.url = url
        if !(options & SWWebImageOptions.DelayPlaceholder).boolValue {
            self.image = placeholderImage
        }
        if let url = self.url? {
            SWWebImageManager.sharedManager.downloadImage(url, options: options,
                progress: progress,
                completeHandler: {(image: UIImage?, error: NSError?, cacheType: SWImageCacheType , finished: Bool , imageUrl: NSURL? ) -> Void in
                    dispatch_main_sync_safe({ () -> () in
                        if let image = image? {
                            self.image = image
                            self.setNeedsLayout()
                        }
                        else {
                            if (options & SWWebImageOptions.DelayPlaceholder ).boolValue {
                                self.image = placeholderImage;
                                self.setNeedsLayout()
                            }
                        }
                    })
                })
        }
        else {
            println("url must not be nil")
        }
        
    }
    
    func cancelCurrentImageLoad() {
        self.cancelImageLoadOperationWithKey("UIImageViewImageLoad")
    }
    
    func cancelImageLoadOperationWithKey(key: String) {
        let operations = self.operations[key]
        if let operations = operations? {
            for operation in operations {
                operation.cancel()
            }
        }
    }
}