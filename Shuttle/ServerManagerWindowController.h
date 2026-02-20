//
//  ServerManagerWindowController.h
//  Shuttle
//

#import <Cocoa/Cocoa.h>

@class AppDelegate;

@interface ServerManagerWindowController : NSWindowController

- (instancetype)initWithAppDelegate:(AppDelegate *)delegate;
- (void)reload;

@end
