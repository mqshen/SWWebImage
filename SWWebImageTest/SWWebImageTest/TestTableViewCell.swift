//
//  TestTableViewCell.swift
//  SWWebImage
//
//  Created by GoldRatio on 8/18/14.
//  Copyright (c) 2014 GoldRatio. All rights reserved.
//


import Foundation
import UIKit
import SWWebImage

class TestTableViewCell: UITableViewCell
{
    var swImageView: SWWebImageView
    
    required init(coder aDecoder: NSCoder) {
        swImageView = SWWebImageView(frame: CGRectMake(150, 5, 50, 50))
        super.init(coder: aDecoder)
        self.addSubview(swImageView)
    }
    
    override init(style: UITableViewCellStyle, reuseIdentifier: String!) {
        swImageView = SWWebImageView(frame: CGRectMake(150, 5, 50, 50))
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.addSubview(swImageView)
    }
    
}