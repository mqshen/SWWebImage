//
//  ViewController.swift
//  SWWebImage
//
//  Created by GoldRatio on 8/14/14.
//  Copyright (c) 2014 GoldRatio. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
                            
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        
        let path = NSBundle.mainBundle().pathForResource("placeholder@2x", ofType: "png")
        println(path)
        
        let addButton = UIButton(frame: CGRectMake(100, 20, 50, 30))
        addButton.setTitle("添加", forState: UIControlState.Normal)
        addButton.addTarget(self, action: "addImage", forControlEvents: UIControlEvents.TouchUpInside)
        
        self.view.addSubview(addButton)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        
        
        // Dispose of any resources that can be recreated.
    }
    
    func addImage() {
        let image = SWWebImageView(frame: CGRectMake(100, 100, 100, 100))
        
        let placeholderImage = UIImage(named: "placeholder@2x.png")
        image.setImage( NSURL(string: "http://m.tiebaimg.com/timg?wapp&quality=80&size=b150_150&subsize=20480&cut_x=0&cut_w=0&cut_y=0&cut_h=0&sec=1369815402&srctrace&di=73d9bc73c14c5210ec2d614140f520df&wh_rate=null&src=http%3A%2F%2Fimgsrc.baidu.com%2Fforum%2Fpic%2Fitem%2Fe1fe9925bc315c60a24d5d138fb1cb1348547775.jpg"),
            placeholderImage: placeholderImage, options: SWWebImageOptions.ContinueInBackground, progress: nil)
        
        self.view.addSubview(image)
        
    }


}

