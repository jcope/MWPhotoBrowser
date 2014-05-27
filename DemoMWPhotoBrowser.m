//
//  DemoMWPhotoBrowser.m
//  iOS8
//
//  Created by Jeremy Cope on 5/14/14.
//  Copyright (c) 2014 Emma Technologies, L.L.C. All rights reserved.
//

#import "DemoMWPhotoBrowser.h"
#import "Menu.h"

@interface DemoMWPhotoBrowser ()
@property UIViewController* homeVC;
@property Menu* app;
@end

@implementation DemoMWPhotoBrowser

- (id)init{
    if (self = [super init]) {
        _app = [self createDemoApp];
    }
    return self;
}

-(Menu*)createDemoApp{
    return [[Menu alloc] initWithStyle:UITableViewStylePlain];
}

#pragma mark - DemmoApp Delegate
-(NSString*)appName{
    return @"MW Photo Browser";
}
-(NSString*)appDetail{
    return @"A simple iOS photo browser with optional grid view, captions and selections.";
}
-(UIImage*)appImage{
    return [UIImage imageNamed:@"MWPhotoBrowserScreenShot.png"];
}
-(UIViewController*)mainViewController{
    return _app;
}
@end