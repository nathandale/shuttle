//
//  AppDelegate.h
//  Shuttle
//

#import <Cocoa/Cocoa.h>
#import "LaunchAtLoginController.h"

@class ServerManagerWindowController;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>{
    IBOutlet NSMenu *menu;
    IBOutlet NSArrayController *arrayController;

    NSImage *regularIcon;
    NSImage *altIcon;
    
    NSStatusItem *statusItem;
    NSString *shuttleConfigFile;
    
    //This is for the JSON File
    NSDate *configModified;
    NSDate *configModified2;
    NSDate *sshConfigUser;
    NSDate *sshConfigSystem;
    
    //Global settings Pref in the JSON file.
    NSString *shuttleJSONPathPref; //Alternate path the JSON file
    NSString *shuttleJSONPathAlt; //alternate path to the second JSON file
    NSString *shuttleAltConfigFile; //second shuttle JSON file
    NSString *terminalPref; //Which terminal will we be using iTerm or Terminal.app
    NSString *editorPref; //What app opens the JSON file vi, nano...
    NSString *iTermVersionPref; //Which version of iTerm nightly or stable
    NSString *openInPref; //By default are commands opened in tabs or new windows.
    NSString *themePref; //The global theme.
    
    BOOL parseAltJSON; //Are we parsing a second JSON file
    
    //Sort and separator
    NSString *menuName; //Menu name after removing the sort [aaa] and separator [---] syntax.
    BOOL addSeparator; //Are we adding a separator in the menu.
    
    //Used to gather ssh config settings
    NSMutableArray* shuttleHosts;
    NSMutableArray* shuttleHostsAlt;
    NSMutableArray* ignoreHosts;
    NSMutableArray* ignoreKeywords;
    
    LaunchAtLoginController *launchAtLoginController;

    // LAN SSH scanner
    NSMenu *lanSubMenu;
    NSMutableArray *lanHosts;      // array of {ip, hostname} dicts from port-22 scan
    NSMutableArray *bonjourHosts;  // array of {hostname, ip} dicts from mDNS/_ssh._tcp.
    NSNetServiceBrowser *sshBrowser;
    NSDate *lastLanScan;
    BOOL isLanScanning;

    // Address book (new schema)
    NSMutableArray *servers;
    NSMutableArray *categories;
    ServerManagerWindowController *managerWindowController;

}

// Public accessors for ServerManagerWindowController
- (NSMutableArray *)servers;
- (NSMutableArray *)categories;
- (NSString *)configFilePath;
- (void)loadMenu;
- (IBAction)showManager:(id)sender;

// Returns array of {name, identifier, bundleID} dicts for installed terminal apps
- (NSArray<NSDictionary *> *)installedTerminals;

- (void)menuWillOpen:(NSMenu *)menu;

@end
