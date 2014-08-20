//
//  SWWebImageUtil.swift
//  SWWebImage
//
//  Created by GoldRatio on 8/17/14.
//  Copyright (c) 2014 GoldRatio. All rights reserved.
//

import Foundation
import UIKit
import ImageIO


func decodedImageWithImage(image: UIImage) -> UIImage {
    if image.images != nil {
        return image
    }
    let imageRef = image.CGImage
    let imageSize: CGSize = CGSizeMake(CGFloat(CGImageGetWidth(imageRef)), CGFloat(CGImageGetHeight(imageRef)))
    let imageRect = CGRectMake(0, 0, imageSize.width, imageSize.height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var bitmapInfo = CGImageGetBitmapInfo(imageRef)
    
    let infoMask: CGImageAlphaInfo = CGImageAlphaInfo.fromRaw(bitmapInfo.toRaw() & CGBitmapInfo.AlphaInfoMask.toRaw())!
    
    let anyNonAlpha = (infoMask == CGImageAlphaInfo.None ||
        infoMask == CGImageAlphaInfo.NoneSkipFirst ||
        infoMask == CGImageAlphaInfo.NoneSkipLast)
    
    if (infoMask == CGImageAlphaInfo.None && CGColorSpaceGetNumberOfComponents(colorSpace) > 1) {
        bitmapInfo = CGBitmapInfo.fromRaw(bitmapInfo.toRaw() & ~CGBitmapInfo.AlphaInfoMask.toRaw() | CGImageAlphaInfo.NoneSkipFirst.toRaw())!
    }
    else if (!anyNonAlpha && CGColorSpaceGetNumberOfComponents(colorSpace) == 3) {
        bitmapInfo = CGBitmapInfo.fromRaw(bitmapInfo.toRaw() & ~CGBitmapInfo.AlphaInfoMask.toRaw() | CGImageAlphaInfo.PremultipliedFirst.toRaw())!
    }
    if let context = CGBitmapContextCreate(nil, CGImageGetWidth(imageRef), CGImageGetHeight(imageRef), CGImageGetBitsPerComponent(imageRef), 0 , colorSpace, bitmapInfo)? {
        CGContextDrawImage(context, imageRect, imageRef)
        let decompressedImageRef = CGBitmapContextCreateImage(context)
        let decompressedImage = UIImage(CGImage: decompressedImageRef, scale: image.scale, orientation: image.imageOrientation)
        return decompressedImage
    }
    else {
        return image
    }
}

func imageOrientationFromImageData(imageData: NSData) -> UIImageOrientation {
    var result = UIImageOrientation.Up
    if let imageSource = CGImageSourceCreateWithData(imageData, nil)? {
        if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)? {
            let prop = properties.__conversion()
            var exifOrientation = 0
            if let value: AnyObject = prop[kCGImagePropertyOrientation]? {
                CFNumberGetValue(value as CFNumber, CFNumberType.IntType, &exifOrientation)
                result = exifOrientationToiOSOrientation(exifOrientation)
            }
        }
        else {
            println("no property")
        }
        
    }
    return result
}

func exifOrientationToiOSOrientation(exifOrientation: Int) -> UIImageOrientation {
    var orientation = UIImageOrientation.Up
    switch (exifOrientation) {
    case 1:
        orientation = UIImageOrientation.Up
        break
    case 3:
        orientation = UIImageOrientation.Down
        break
    case 8:
        orientation = UIImageOrientation.Left
        break
    case 6:
        orientation = UIImageOrientation.Right
        break
    case 2:
        orientation = UIImageOrientation.UpMirrored
        break
    case 4:
        orientation = UIImageOrientation.DownMirrored
        break
    case 5:
        orientation = UIImageOrientation.LeftMirrored
        break
    case 7:
        orientation = UIImageOrientation.RightMirrored
        break
    default:
        break
    }
    return orientation
}



func imageWithData(data: NSData) -> UIImage? {
    var image: UIImage?
    if let imageType = contentTypeForImageData(data)? {
        if imageType == "image/gif" {
            return  animatedGIFWithData(data)
        }
        else {
            image = UIImage(data: data)
            let orientation = imageOrientationFromImageData(data)
            if orientation != UIImageOrientation.Up {
                if let tempImage = image? {
                    image = UIImage(CGImage: tempImage.CGImage, scale: tempImage.scale, orientation: orientation)
                    
                }
            }
        }
    }
    return image
}


func contentTypeForImageData(data: NSData) -> String? {
    var value : Int16 = 0
    if data.length >= sizeof(Int16) {
        data.getBytes(&value, length:1)
        
        switch (value) {
        case 0xff:
            return "image/jpeg"
        case 0x89:
            return "image/png"
        case 0x47:
            return "image/gif"
        case 0x49:
            return "image/tiff"
        case 0x4D:
            return "image/tiff"
        case 0x52:
            // R as RIFF for WEBP
            if (data.length < 12) {
                return nil
            }
            
            let testString = NSString(data: data.subdataWithRange(NSMakeRange(0, 12)), encoding: NSASCIIStringEncoding)
            if (testString.hasPrefix("RIFF") && testString.hasSuffix("WEBP")) {
                return "image/webp"
            }
            return nil
        default:
            return nil
        }
    }
    else {
        return nil
    }
    
}

func frameDuration(index: UInt, imageSource: CGImageSourceRef) -> Double {
    var frameDuration: Double = 0.1
    let cfFrameProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil)
    var dictionary = cfFrameProperties.__conversion()
    let gifProperties: AnyObject! = dictionary[kCGImagePropertyGIFDictionary]
    if let delayTimeUnclampedProp: AnyObject = gifProperties[kCGImagePropertyGIFUnclampedDelayTime]? {
        frameDuration = delayTimeUnclampedProp as Double
    }
    else {
        if let delayTimeProp: AnyObject = gifProperties[kCGImagePropertyGIFDelayTime]? {
            frameDuration = delayTimeProp as Double
        }
    }
    if (frameDuration < 0.011) {
        frameDuration = 0.100
    }
    
    return frameDuration
}


func animatedGIFWithData(data: NSData!) -> UIImage? {
    let imageSouce = CGImageSourceCreateWithData(data , nil)
    let count = CGImageSourceGetCount(imageSouce)
    var animatedImage: UIImage?
    if count <= 1 {
        animatedImage = UIImage(data: data)
    }
    else {
        var images = [UIImage]()
        var duration: NSTimeInterval = 0.0
        for i in 0..<count {
            let image = CGImageSourceCreateImageAtIndex(imageSouce, i, nil)
            duration += frameDuration(i, imageSouce)
            
            images.append(UIImage(CGImage: image, scale: UIScreen.mainScreen().scale, orientation: UIImageOrientation.Up))
            //CGImageRelease(image)
        }
        
        if duration == 0 {
            duration = Double(count) * (1.0 / 10.0)
        }
        animatedImage = UIImage.animatedImageWithImages(images, duration: duration)
    }
    return animatedImage
}