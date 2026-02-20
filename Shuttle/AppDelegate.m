//
//  AppDelegate.m
//  Shuttle
//

#import "AppDelegate.h"
#import "AboutWindowController.h"
#import "ServerManagerWindowController.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <fcntl.h>
#include <netdb.h>

@interface AppDelegate () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property (nonatomic, strong) NSMutableArray *pendingServices; // NSNetService objects awaiting resolution
@end

@implementation AppDelegate

- (void) awakeFromNib {
    
    // The location for the JSON path file. This is a simple file that contains the hard path to the *.json settings file.
    shuttleJSONPathPref = [NSHomeDirectory() stringByAppendingPathComponent:@".shuttle.path"];
    shuttleJSONPathAlt = [NSHomeDirectory() stringByAppendingPathComponent:@".shuttle-alt.path"];
    
    //if file shuttle.path exists in ~/.shuttle.path then read this file as it should contain the custom path to *.json
    if( [[NSFileManager defaultManager] fileExistsAtPath:shuttleJSONPathPref] ) {
        
        //Read the shuttle.path file which contains the path to the json file
        NSString *jsonConfigPath = [NSString stringWithContentsOfFile:shuttleJSONPathPref encoding:NSUTF8StringEncoding error:NULL];
        
        //Remove the white space if any.
        jsonConfigPath = [ jsonConfigPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        shuttleConfigFile = jsonConfigPath;
    }else{
        // The path for the configuration file (by default: ~/.shuttle.json)
        shuttleConfigFile = [NSHomeDirectory() stringByAppendingPathComponent:@".shuttle.json"];
        
        // if the config file does not exist, create a default one
        if ( ![[NSFileManager defaultManager] fileExistsAtPath:shuttleConfigFile] ) {
            NSString *cgFileInResource = [[NSBundle mainBundle] pathForResource:@"shuttle.default" ofType:@"json"];
            [[NSFileManager defaultManager] copyItemAtPath:cgFileInResource toPath:shuttleConfigFile error:nil];
        }
    }
    
    // if the custom alternate json file exists then read the file and use set the output as the alt path.
    if ( [[NSFileManager defaultManager] fileExistsAtPath:shuttleJSONPathAlt] ) {
        
        //Read shuttle-alt.path file which contains the custom path to the alternate json file
        NSString *jsonConfigAltPath = [NSString stringWithContentsOfFile:shuttleJSONPathAlt encoding:NSUTF8StringEncoding error:NULL];
        
        //Remove whitespace if any
        jsonConfigAltPath = [ jsonConfigAltPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        //set the global var that contains the alternate path
        shuttleAltConfigFile = jsonConfigAltPath;
        
        //flag the bool for later parsing
        parseAltJSON = YES;
    }else{
        //the custom alt path does not exist. Assume the default for alt path; if existing flag for later parsing
        shuttleAltConfigFile = [NSHomeDirectory() stringByAppendingPathComponent:@".shuttle-alt.json"];
        
        if ( [[NSFileManager defaultManager] fileExistsAtPath:shuttleAltConfigFile] ){
            //the default path exists. Flag for later parsing
            parseAltJSON = YES;
        }else{
            //The user does not want to parse an additional json file.
            parseAltJSON = NO;
        }
    }
    
    // Define Icons
    //only regular icon is needed for 10.10 and higher. OS X changes the icon for us.
    regularIcon = [NSImage imageNamed:@"StatusIcon"];
    altIcon = [NSImage imageNamed:@"StatusIconAlt"];
    
    // Create the status bar item
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    [statusItem setMenu:menu];
    [statusItem setImage: regularIcon];
    
    // Check for AppKit Version, add support for darkmode if > 10.9
    BOOL oldAppKitVersion = (floor(NSAppKitVersionNumber) <= 1265);
    
    // 10.10 or higher, dont load the alt image let OS X style it.
    if (!oldAppKitVersion)
    {
        regularIcon.template = YES;
    }
    // Load the alt image for OS X < 10.10
    else{
        [statusItem setHighlightMode:YES];
        [statusItem setAlternateImage: altIcon];
    }
    
    launchAtLoginController = [[LaunchAtLoginController alloc] init];
    // Needed to trigger the menuWillOpen event
    [menu setDelegate:self];

    // Insert Manager... at top of Settings submenu
    for (NSMenuItem *item in [menu itemArray]) {
        if ([[item title] isEqualToString:@"Settings"] && [item hasSubmenu]) {
            NSMenuItem *managerItem = [[NSMenuItem alloc] initWithTitle:@"Manager..."
                                                                 action:@selector(showManager:)
                                                          keyEquivalent:@""];
            [managerItem setTarget:self];
            [[item submenu] insertItem:managerItem atIndex:0];
            [[item submenu] insertItem:[NSMenuItem separatorItem] atIndex:1];
            break;
        }
    }
}

- (BOOL) needUpdateFor: (NSString*) file with: (NSDate*) old {
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:[file stringByExpandingTildeInPath]])
        return false;
    
    if (old == NULL)
        return true;
    
    NSDate *date = [self getMTimeFor:file];
    return [date compare: old] == NSOrderedDescending;
}

- (NSDate*) getMTimeFor: (NSString*) file {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[file stringByExpandingTildeInPath]
                                                                                error:nil];
    return [attributes fileModificationDate];
}

- (void)menuWillOpen:(NSMenu *)menu {
    // Check when the config was last modified
    if ( [self needUpdateFor:shuttleConfigFile with:configModified] ||
        [self needUpdateFor:shuttleAltConfigFile with:configModified2] ||
        [self needUpdateFor: @"/etc/ssh/ssh_config" with:sshConfigSystem] ||
        [self needUpdateFor: @"~/.ssh/config" with:sshConfigUser]) {

        configModified = [self getMTimeFor:shuttleConfigFile];
        configModified2 = [self getMTimeFor:shuttleAltConfigFile];
        sshConfigSystem = [self getMTimeFor: @"/etc/ssh/ssh_config"];
        sshConfigUser = [self getMTimeFor: @"~/.ssh/config"];

        [self loadMenu];
    }

    // Trigger LAN scan on first open
    if (!lastLanScan && !isLanScanning) {
        [self scanLAN];
    }
}

// Parsing of the SSH Config File
// Courtesy of https://gist.github.com/geeksunny/3376694
- (NSDictionary<NSString *, NSDictionary *> *)parseSSHConfigFile {
    
    NSString *configFile = nil;
    NSFileManager *fileMgr = [[NSFileManager alloc] init];
    
    // First check the system level configuration
    if ([fileMgr fileExistsAtPath: @"/etc/ssh_config"]) {
        configFile = @"/etc/ssh_config";
    }
    
    // Fallback to check if actually someone used /etc/ssh/ssh_config
    if ([fileMgr fileExistsAtPath: [@"~/.ssh/config" stringByExpandingTildeInPath]]) {
        configFile = [@"~/.ssh/config" stringByExpandingTildeInPath];
    }
    
    if (configFile == nil) {
        // We did not find any config file so we gracefully die
        return nil;
    }
    return [self parseSSHConfig:configFile];
}

- (NSDictionary<NSString *, NSDictionary *> *)parseSSHConfig:(NSString *)filepath {
    // Get file contents into fh.
    NSString *fh = [NSString stringWithContentsOfFile:filepath encoding:NSUTF8StringEncoding error:nil];
    
    // build the regex for matching
    NSError* error = NULL;
    NSRegularExpression* rx = [NSRegularExpression regularExpressionWithPattern:@"^(#?)[ \\t]*([^ \\t=]+)[ \\t=]+(.*)$"
                                                                        options:0
                                                                          error:&error];
    
    // create data store
    NSMutableDictionary* servers = [[NSMutableDictionary alloc] init];
    NSString* key = nil;
    
    // Loop through each line and parse the file.
    for (NSString *line in [fh componentsSeparatedByString:@"\n"]) {
        
        // Strip line
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[ NSCharacterSet whitespaceCharacterSet]];
        
        // run the regex against the line
        NSTextCheckingResult* matches = [rx firstMatchInString:trimmed
                                                       options:0
                                                         range:NSMakeRange(0, [trimmed length])];
        if ([matches numberOfRanges] != 4) {
            continue;
        }
        
        BOOL isComment = [[trimmed substringWithRange:[matches rangeAtIndex:1]] isEqualToString:@"#"];
        NSString* first = [trimmed substringWithRange:[matches rangeAtIndex:2]];
        NSString* second = [trimmed substringWithRange:[matches rangeAtIndex:3]];
        
        // check for special comment key/value pairs
        if (isComment && key && [first hasPrefix:@"shuttle."]) {
            servers[key][[first substringFromIndex:8]] = second;
        }
        
        // other comments must be skipped
        if (isComment) {
            continue;
        }
        
        if ([first isEqualToString:@"Include"]) {
            // Support for ssh_config Include directive.
            NSString *includePath = ([second isAbsolutePath])
                ? [second stringByExpandingTildeInPath]
                : [[filepath stringByDeletingLastPathComponent] stringByAppendingPathComponent:second];
            
            [servers addEntriesFromDictionary:[self parseSSHConfig:includePath]];
        }
        
        if ([first isEqualToString:@"Host"]) {
            // a new host section
            
            // split multiple aliases on space and only save the first
            NSArray* hostAliases = [second componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            hostAliases = [hostAliases filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF != ''"]];
            key = [hostAliases firstObject];
            servers[key] = [[NSMutableDictionary alloc] init];
        }
    }
    
    return servers;
}


- (void) loadMenu {
    // Clear out the hosts so we can start over
    NSUInteger n = [[menu itemArray] count];
    for (int i=0;i<n-4;i++) {
        [menu removeItemAtIndex:0];
    }
    
    // Parse the config file
    NSData *data = [NSData dataWithContentsOfFile:shuttleConfigFile];
    id json = [NSJSONSerialization JSONObjectWithData:data
                                              options:NSJSONReadingMutableContainers
                                                error:nil];
    // Check valid JSON syntax
    if ( !json ) {
        NSMenuItem *menuItem = [menu insertItemWithTitle:NSLocalizedString(@"Error parsing config",nil)
                                                  action:false
                                           keyEquivalent:@""
                                                 atIndex:0
                                ];
        [menuItem setEnabled:false];
        return;
    }
    
    terminalPref = [json[@"terminal"] lowercaseString];
    editorPref = [json[@"editor"] lowercaseString];
    launchAtLoginController.launchAtLogin = [json[@"launch_at_login"] boolValue];

    if (json[@"servers"] != nil) {
        // New address book format
        NSArray *rawCats = json[@"categories"] ?: @[];
        categories = [rawCats mutableCopy];
        NSArray *rawServers = json[@"servers"] ?: @[];
        NSMutableArray *mutableServers = [NSMutableArray arrayWithCapacity:rawServers.count];
        for (id s in rawServers) {
            [mutableServers addObject:[s mutableCopy]];
        }
        servers = mutableServers;
        [self buildMenuFromServers];
    } else {
        // Legacy hosts format
        iTermVersionPref = [json[@"iTerm_version"] lowercaseString];
        openInPref = [json[@"open_in"] lowercaseString];
        themePref = json[@"default_theme"];
        shuttleHosts = json[@"hosts"];
        ignoreHosts = json[@"ssh_config_ignore_hosts"];
        ignoreKeywords = json[@"ssh_config_ignore_keywords"];

        if (parseAltJSON) {
            NSData *dataAlt = [NSData dataWithContentsOfFile:shuttleAltConfigFile];
            id jsonAlt = [NSJSONSerialization JSONObjectWithData:dataAlt options:NSJSONReadingMutableContainers error:nil];
            shuttleHostsAlt = jsonAlt[@"hosts"];
            [shuttleHosts addObjectsFromArray:shuttleHostsAlt];
        }

        BOOL showSshConfigHosts = YES;
        if ([[json allKeys] containsObject:@"show_ssh_config_hosts"] && [json[@"show_ssh_config_hosts"] boolValue] == NO)
            showSshConfigHosts = NO;

        if (showSshConfigHosts) {
            NSDictionary *sshCfgHosts = [self parseSSHConfigFile];
            for (NSString *key in sshCfgHosts) {
                BOOL skipCurrent = NO;
                NSDictionary *cfg = sshCfgHosts[key];
                NSString *name = cfg[@"name"] ?: key;

                if ([name rangeOfString:@"*"].length != 0) skipCurrent = YES;
                if ([name hasPrefix:@"."]) skipCurrent = YES;
                for (NSString *ignore in ignoreHosts)
                    if ([name isEqualToString:ignore]) skipCurrent = YES;
                for (NSString *ignore in ignoreKeywords)
                    if ([name rangeOfString:ignore].location != NSNotFound) skipCurrent = YES;
                if (skipCurrent) continue;

                NSMutableArray *path = [NSMutableArray arrayWithArray:[name componentsSeparatedByString:@"/"]];
                NSString *leaf = [path lastObject];
                if (!leaf) continue;
                [path removeLastObject];

                NSMutableArray *itemList = shuttleHosts;
                for (NSString *part in path) {
                    BOOL createList = YES;
                    for (NSDictionary *item in itemList) {
                        if (item[@"cmd"] || item[@"name"]) continue;
                        if (item[part]) {
                            itemList = [item[part] isKindOfClass:[NSArray class]] ? item[part] : nil;
                            createList = NO;
                            break;
                        }
                    }
                    if (!itemList) break;
                    if (createList) {
                        NSMutableArray *newList = [[NSMutableArray alloc] init];
                        [itemList addObject:@{part: newList}];
                        itemList = newList;
                    }
                }
                if (itemList)
                    [itemList addObject:@{@"name": leaf, @"cmd": [NSString stringWithFormat:@"ssh %@", key]}];
            }
        }
        [self buildMenu:shuttleHosts addToMenu:menu];
    }

    // LAN SSH scanner section — inserted before the 4 static XIB items
    NSInteger lanInsertAt = (NSInteger)[[menu itemArray] count] - 4;
    [menu insertItem:[NSMenuItem separatorItem] atIndex:lanInsertAt++];
    NSMenuItem *lanItem = [[NSMenuItem alloc] initWithTitle:@"Local Network" action:nil keyEquivalent:@""];
    if (!lanSubMenu) lanSubMenu = [[NSMenu alloc] init];
    [lanItem setSubmenu:lanSubMenu];
    [menu insertItem:lanItem atIndex:lanInsertAt];
    [self rebuildLanSubmenu];
}

- (void) buildMenu:(NSArray*)data addToMenu:(NSMenu *)m {
    // go through the array and sort out the menus and the leafs into
    // separate bucks so we can sort them independently.
    NSMutableDictionary* menus = [[NSMutableDictionary alloc] init];
    NSMutableDictionary* leafs = [[NSMutableDictionary alloc] init];
    
    for (NSDictionary* item in data) {
        if (item[@"cmd"] && item[@"name"]) {
            // this is a leaf
            [leafs setObject:item forKey:item[@"name"]];
        } else {
            // must be a menu - add all instances
            for (NSString* key in item) {
                [menus setObject:item[key] forKey:key];
            }
        }
    }
    
    NSArray* menuKeys = [[menus allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSArray* leafKeys = [[leafs allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    
    NSInteger pos = 0;
    
    // create menus first
    for (NSString* key in menuKeys) {
        NSMenu* subMenu = [[NSMenu alloc] init];
        NSMenuItem* menuItem = [[NSMenuItem alloc] init];
        [self separatorSortRemoval:key];
        [menuItem setTitle:menuName];
        [menuItem setSubmenu:subMenu];
        [m insertItem:menuItem atIndex:pos++];
        if (addSeparator) {
            [m insertItem:[NSMenuItem separatorItem] atIndex:pos++];
        }
        // build submenu
        [self buildMenu:menus[key] addToMenu:subMenu];
    }
    
    // now create leafs
    for (NSString *key in leafKeys) {
        NSDictionary* cfg = leafs[key];
        NSMenuItem* menuItem = [[NSMenuItem alloc] init];
        
        //Get the command we are going to run in termainal
        NSString *menuCmd = cfg[@"cmd"];
        //Get the theme for this terminal session
        NSString *termTheme = cfg[@"theme"];
        //Get the name for the terminal session
        NSString *termTitle = cfg[@"title"];
        //Get the value of setting inTerminal
        NSString *termWindow = cfg[@"inTerminal"];
        //Get the menu name will will use this as the title if title is null.
        [self separatorSortRemoval:cfg[@"name"]];
        
        //Place the terminal command, theme, and title into an comma delimited string
        NSString *menuRepObj = [NSString stringWithFormat:@"%@¬_¬%@¬_¬%@¬_¬%@¬_¬%@", menuCmd, termTheme, termTitle, termWindow, menuName];
        
        [menuItem setTitle:menuName];
        [menuItem setRepresentedObject:menuRepObj];
        [menuItem setAction:@selector(openHost:)];
        [m insertItem:menuItem atIndex:pos++];
        if (addSeparator) {
            [m insertItem:[NSMenuItem separatorItem] atIndex:pos++];
        }
    }
}

// MARK: - Terminal Detection

- (NSArray<NSDictionary *> *)installedTerminals {
    // Ordered list of known terminal apps: {display name, JSON identifier, bundle ID}
    NSArray *candidates = @[
        @{@"name": @"Terminal",   @"id": @"terminal",   @"bundle": @"com.apple.Terminal"},
        @{@"name": @"iTerm2",     @"id": @"iterm",      @"bundle": @"com.googlecode.iterm2"},
        @{@"name": @"Ghostty",    @"id": @"ghostty",    @"bundle": @"com.mitchellh.ghostty"},
        @{@"name": @"Alacritty",  @"id": @"alacritty",  @"bundle": @"io.alacritty"},
        @{@"name": @"kitty",      @"id": @"kitty",      @"bundle": @"net.kovidgoyal.kitty"},
        @{@"name": @"Warp",       @"id": @"warp",       @"bundle": @"dev.warp.Warp-Stable"},
        @{@"name": @"Hyper",      @"id": @"hyper",      @"bundle": @"co.zeit.hyper"},
        @{@"name": @"Rio",        @"id": @"rio",         @"bundle": @"com.raphaelamorim.rio"},
    ];

    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSMutableArray *found = [NSMutableArray array];
    for (NSDictionary *t in candidates) {
        NSURL *url = [ws URLForApplicationWithBundleIdentifier:t[@"bundle"]];
        if (url) [found addObject:t];
    }
    return found;
}

// Returns the main executable path for a terminal given its bundle ID
- (NSString *)executableForBundleID:(NSString *)bundleID {
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleID];
    if (!appURL) return nil;
    NSBundle *bundle = [NSBundle bundleWithURL:appURL];
    return bundle.executablePath;
}

// MARK: - Public Accessors

- (NSMutableArray *)servers        { return servers; }
- (NSMutableArray *)categories     { return categories; }
- (NSString *)configFilePath       { return shuttleConfigFile; }

// MARK: - Address Book Menu

- (void)buildMenuFromServers {
    NSInteger insertAt = 0;
    for (NSString *category in categories) {
        NSArray *catServers = [servers filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"category == %@", category]];
        if (catServers.count == 0) continue;

        NSMenu *subMenu = [[NSMenu alloc] init];
        for (NSDictionary *server in catServers) {
            NSString *name         = server[@"name"] ?: server[@"hostname"] ?: @"Unnamed";
            NSString *cmd          = [self sshCommandForServer:server];
            NSString *termOverride = server[@"terminal"] ?: @"";
            // Format: cmd¬_¬theme¬_¬title¬_¬window¬_¬name¬_¬terminalOverride
            NSString *rep = [NSString stringWithFormat:@"%@¬_¬(null)¬_¬(null)¬_¬(null)¬_¬%@¬_¬%@",
                             cmd, name, termOverride];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name action:@selector(openHost:) keyEquivalent:@""];
            [item setRepresentedObject:rep];
            [subMenu addItem:item];
        }
        NSMenuItem *catItem = [[NSMenuItem alloc] initWithTitle:category action:nil keyEquivalent:@""];
        [catItem setSubmenu:subMenu];
        [menu insertItem:catItem atIndex:insertAt++];
    }
    if (insertAt > 0)
        [menu insertItem:[NSMenuItem separatorItem] atIndex:insertAt];
}

- (NSString *)sshCommandForServer:(NSDictionary *)server {
    NSMutableString *cmd = [NSMutableString stringWithString:@"ssh"];
    NSString *key  = server[@"identity_file"];
    NSInteger port = [server[@"port"] integerValue];
    NSString *user = server[@"user"];
    NSString *host = server[@"hostname"];
    if (key.length > 0)          [cmd appendFormat:@" -i %@", key];
    if (port > 0 && port != 22)  [cmd appendFormat:@" -p %ld", (long)port];
    if (user.length > 0)         [cmd appendFormat:@" %@@%@", user, host];
    else                         [cmd appendFormat:@" %@", host];
    return cmd;
}

// MARK: - Manager Window

- (IBAction)showManager:(id)sender {
    if (!managerWindowController)
        managerWindowController = [[ServerManagerWindowController alloc] initWithAppDelegate:self];
    [managerWindowController.window makeKeyAndOrderFront:nil];
    [managerWindowController reload];
}

// MARK: - LAN SSH Scanner

- (NSString *)localIPAddress {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return nil;

    NSString *result = nil;
    for (struct ifaddrs *c = interfaces; c; c = c->ifa_next) {
        if (!c->ifa_addr || c->ifa_addr->sa_family != AF_INET) continue;
        NSString *name = [NSString stringWithUTF8String:c->ifa_name];
        if (![name hasPrefix:@"en"]) continue;
        char buf[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &((struct sockaddr_in *)c->ifa_addr)->sin_addr, buf, sizeof(buf));
        NSString *ip = [NSString stringWithUTF8String:buf];
        if (![ip isEqualToString:@"127.0.0.1"]) { result = ip; break; }
    }
    freeifaddrs(interfaces);
    return result;
}

- (NSArray *)subnetAddresses:(NSString *)localIP {
    NSArray *parts = [localIP componentsSeparatedByString:@"."];
    if (parts.count != 4) return @[];
    NSString *prefix = [NSString stringWithFormat:@"%@.%@.%@", parts[0], parts[1], parts[2]];
    NSMutableArray *addresses = [NSMutableArray array];
    for (int i = 1; i <= 254; i++) {
        NSString *ip = [NSString stringWithFormat:@"%@.%d", prefix, i];
        if (![ip isEqualToString:localIP]) [addresses addObject:ip];
    }
    return addresses;
}

- (BOOL)isPort22OpenAt:(NSString *)ip {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return NO;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(22);
    if (inet_pton(AF_INET, [ip UTF8String], &addr.sin_addr) <= 0) { close(sock); return NO; }

    fcntl(sock, F_SETFL, fcntl(sock, F_GETFL, 0) | O_NONBLOCK);
    connect(sock, (struct sockaddr *)&addr, sizeof(addr));

    struct timeval tv = {0, 300000}; // 300ms timeout
    fd_set writefds;
    FD_ZERO(&writefds);
    FD_SET(sock, &writefds);

    BOOL open = NO;
    if (select(sock + 1, NULL, &writefds, NULL, &tv) > 0) {
        int error = 0; socklen_t len = sizeof(error);
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &error, &len);
        open = (error == 0);
    }
    close(sock);
    return open;
}

// Reverse-DNS lookup. Returns hostname string or nil if unresolvable. Safe to call off main thread.
- (NSString *)reverseResolve:(NSString *)ip {
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    if (inet_pton(AF_INET, [ip UTF8String], &sa.sin_addr) <= 0) return nil;
    char host[NI_MAXHOST];
    if (getnameinfo((struct sockaddr *)&sa, sizeof(sa), host, sizeof(host),
                    NULL, 0, NI_NAMEREQD) != 0) return nil;
    NSString *resolved = [NSString stringWithUTF8String:host];
    // Strip trailing dot if present (DNS FQDN artefact)
    if ([resolved hasSuffix:@"."]) resolved = [resolved substringToIndex:resolved.length - 1];
    return resolved;
}

- (void)scanLAN {
    if (isLanScanning) return;
    isLanScanning = YES;
    lanHosts = [NSMutableArray array];
    bonjourHosts = [NSMutableArray array];
    [self rebuildLanSubmenu];

    // ---- Bonjour / mDNS: find _ssh._tcp. services on local. ----
    [sshBrowser stop];
    self.pendingServices = [NSMutableArray array];
    sshBrowser = [[NSNetServiceBrowser alloc] init];
    sshBrowser.delegate = self;
    [sshBrowser searchForServicesOfType:@"_ssh._tcp." inDomain:@"local."];

    // ---- Port-22 sweep with reverse-DNS ----
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *localIP = [self localIPAddress];
        if (!localIP) {
            dispatch_async(dispatch_get_main_queue(), ^{ isLanScanning = NO; [self rebuildLanSubmenu]; });
            return;
        }

        NSArray *addresses = [self subnetAddresses:localIP];
        NSMutableArray *found = [NSMutableArray array];
        NSObject *lock = [[NSObject alloc] init];

        dispatch_group_t group = dispatch_group_create();
        dispatch_semaphore_t sem = dispatch_semaphore_create(50);
        dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

        for (NSString *ip in addresses) {
            dispatch_group_async(group, q, ^{
                dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
                if ([self isPort22OpenAt:ip]) {
                    NSString *hostname = [self reverseResolve:ip] ?: ip;
                    NSDictionary *entry = @{@"ip": ip, @"hostname": hostname};
                    @synchronized(lock) { [found addObject:entry]; }
                }
                dispatch_semaphore_signal(sem);
            });
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            lanHosts = found;
            lastLanScan = [NSDate date];
            isLanScanning = NO;
            [self rebuildLanSubmenu];
        });
    });
}

// MARK: - NSNetServiceBrowser delegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    service.delegate = self;
    [self.pendingServices addObject:service]; // retain during resolution
    [service resolveWithTimeout:5.0];
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    NSString *host = service.hostName ?: service.name;
    // Strip trailing dot
    if ([host hasSuffix:@"."]) host = [host substringToIndex:host.length - 1];

    // Try to extract an IPv4 address from the resolved addresses
    NSString *resolvedIP = @"";
    for (NSData *addrData in service.addresses) {
        const struct sockaddr *sa = (const struct sockaddr *)addrData.bytes;
        if (sa->sa_family == AF_INET) {
            char buf[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &((const struct sockaddr_in *)sa)->sin_addr, buf, sizeof(buf));
            resolvedIP = [NSString stringWithUTF8String:buf];
            break;
        }
    }

    NSDictionary *entry = @{@"hostname": host, @"ip": resolvedIP};
    dispatch_async(dispatch_get_main_queue(), ^{
        [bonjourHosts addObject:entry];
        [self.pendingServices removeObject:service];
        [self rebuildLanSubmenu];
    });
}

- (void)netService:(NSNetService *)service didNotResolve:(NSDictionary *)errorDict {
    [self.pendingServices removeObject:service];
}

// MARK: - Build LAN submenu

- (void)rebuildLanSubmenu {
    if (!lanSubMenu) return;
    [lanSubMenu removeAllItems];

    if (isLanScanning) {
        NSMenuItem *item = [lanSubMenu addItemWithTitle:@"Scanning..." action:nil keyEquivalent:@""];
        [item setEnabled:NO];
    } else {
        // Merge IP-scan results and Bonjour results, deduplicating by hostname.
        // Bonjour names are preferred (they're the canonical mDNS name).
        NSMutableArray *combined = [NSMutableArray array];
        NSMutableSet *seenHostnames = [NSMutableSet set];

        for (NSDictionary *h in bonjourHosts) {
            NSString *hn = h[@"hostname"];
            if (hn.length > 0 && ![seenHostnames containsObject:hn]) {
                [combined addObject:h];
                [seenHostnames addObject:hn];
            }
        }
        for (NSDictionary *h in lanHosts) {
            NSString *hn = h[@"hostname"];
            if (hn.length > 0 && ![seenHostnames containsObject:hn]) {
                [combined addObject:h];
                [seenHostnames addObject:hn];
            }
        }

        if (combined.count == 0) {
            NSMenuItem *item = [lanSubMenu addItemWithTitle:@"No SSH hosts found" action:nil keyEquivalent:@""];
            [item setEnabled:NO];
        } else {
            NSArray *sorted = [combined sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                NSString *ipA = a[@"ip"], *ipB = b[@"ip"];
                // Entries with no IP (Bonjour-only) sort to the end
                if (!ipA.length && !ipB.length) return NSOrderedSame;
                if (!ipA.length) return NSOrderedDescending;
                if (!ipB.length) return NSOrderedAscending;
                NSInteger lastA = [[[ipA componentsSeparatedByString:@"."] lastObject] integerValue];
                NSInteger lastB = [[[ipB componentsSeparatedByString:@"."] lastObject] integerValue];
                return lastA < lastB ? NSOrderedAscending : lastA > lastB ? NSOrderedDescending : NSOrderedSame;
            }];
            for (NSDictionary *host in sorted) {
                NSString *hostname  = host[@"hostname"];
                NSString *ip        = host[@"ip"];
                NSString *sshTarget = (hostname.length > 0) ? hostname : ip;
                NSString *label     = sshTarget;
                if (ip.length > 0 && ![hostname isEqualToString:ip])
                    label = [NSString stringWithFormat:@"%@ (%@)", hostname, ip];

                // Top-level item is the host label; it gets a submenu
                NSMenuItem *hostItem = [[NSMenuItem alloc] initWithTitle:label action:nil keyEquivalent:@""];
                NSMenu *hostMenu = [[NSMenu alloc] init];

                // Connect
                NSString *cmd    = [NSString stringWithFormat:@"ssh %@", sshTarget];
                NSString *repObj = [NSString stringWithFormat:@"%@¬_¬(null)¬_¬(null)¬_¬(null)¬_¬%@", cmd, label];
                NSMenuItem *connectItem = [[NSMenuItem alloc] initWithTitle:@"Connect" action:@selector(openHost:) keyEquivalent:@""];
                [connectItem setRepresentedObject:repObj];
                [hostMenu addItem:connectItem];

                // Save to Address Book
                NSMenuItem *saveItem = [[NSMenuItem alloc] initWithTitle:@"Save to Address Book…"
                                                                  action:@selector(saveLanHostToAddressBook:)
                                                           keyEquivalent:@""];
                [saveItem setRepresentedObject:@{@"hostname": sshTarget, @"ip": ip ?: @""}];
                [saveItem setTarget:self];
                [hostMenu addItem:saveItem];

                [hostItem setSubmenu:hostMenu];
                [lanSubMenu addItem:hostItem];
            }
        }
    }

    [lanSubMenu addItem:[NSMenuItem separatorItem]];

    if (lastLanScan && !isLanScanning) {
        NSInteger elapsed = (NSInteger)[[NSDate date] timeIntervalSinceDate:lastLanScan];
        NSString *age = elapsed < 60
            ? [NSString stringWithFormat:@"Scanned %lds ago", (long)elapsed]
            : [NSString stringWithFormat:@"Scanned %ldm ago", (long)(elapsed / 60)];
        NSMenuItem *timeItem = [lanSubMenu addItemWithTitle:age action:nil keyEquivalent:@""];
        [timeItem setEnabled:NO];
        [lanSubMenu addItem:[NSMenuItem separatorItem]];
    }

    [lanSubMenu addItemWithTitle:@"Scan Now" action:@selector(scanNow:) keyEquivalent:@""];
}

- (IBAction)scanNow:(id)sender {
    [self scanLAN];
}

- (IBAction)saveLanHostToAddressBook:(NSMenuItem *)sender {
    NSDictionary *host = sender.representedObject;
    NSString *detectedHost = host[@"hostname"] ?: host[@"ip"] ?: @"";

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText     = @"Save to Address Book";
    alert.informativeText = [NSString stringWithFormat:@"Host: %@", detectedHost];
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    // Accessory view: name field + category popup stacked vertically
    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 260, 56)];

    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 30, 260, 22)];
    nameField.placeholderString = @"Display name (optional)";
    nameField.stringValue       = detectedHost;
    nameField.font              = [NSFont systemFontOfSize:13];
    [accessory addSubview:nameField];

    NSPopUpButton *catPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 260, 26) pullsDown:NO];
    if (categories.count > 0)
        [catPopup addItemsWithTitles:categories];
    else
        [catPopup addItemWithTitle:@"LOCAL SERVERS"];
    [accessory addSubview:catPopup];

    alert.accessoryView = accessory;
    [alert.window makeFirstResponder:nameField];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *name = [nameField.stringValue stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length) name = detectedHost;
    NSString *category = [catPopup titleOfSelectedItem] ?: @"LOCAL SERVERS";

    // Ensure category exists
    if (![categories containsObject:category])
        [categories addObject:category];

    NSMutableDictionary *newServer = [@{
        @"name":     name,
        @"hostname": detectedHost,
        @"category": category
    } mutableCopy];
    [servers addObject:newServer];

    // Persist and refresh
    NSData *existing = [NSData dataWithContentsOfFile:shuttleConfigFile];
    id parsed = existing ? [NSJSONSerialization JSONObjectWithData:existing
                                                           options:NSJSONReadingMutableContainers
                                                             error:nil] : nil;
    NSMutableDictionary *root = parsed ? [parsed mutableCopy] : [NSMutableDictionary dictionary];
    root[@"categories"] = categories;
    root[@"servers"]    = servers;
    [root removeObjectForKey:@"hosts"];
    NSData *out = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    [out writeToFile:shuttleConfigFile atomically:YES];
    [self loadMenu];
}

// MARK: -

- (void) separatorSortRemoval:(NSString *)currentName {
    NSError *regexError = nil;
    addSeparator = NO;
    
    NSRegularExpression *regexSort = [NSRegularExpression regularExpressionWithPattern:@"([\\[][a-z]{3}[\\]])" options:0 error:&regexError];
    NSRegularExpression *regexSeparator = [NSRegularExpression regularExpressionWithPattern:@"([\\[][-]{3}[\\]])" options:0 error:&regexError];
    
    NSUInteger sortMatches = [regexSort numberOfMatchesInString:currentName options:0 range:NSMakeRange(0,[currentName length])];
    NSUInteger separatorMatches = [regexSeparator  numberOfMatchesInString:currentName options:0 range:NSMakeRange(0,[currentName length])];
    //NSUInteger *totalMatches = sortMatches + separatorMatches;
    
    
    
    if ( sortMatches == 1 || separatorMatches == 1 ) {
        if (sortMatches == 1 && separatorMatches == 1 ) {
            menuName = [regexSort stringByReplacingMatchesInString:currentName options:0 range:NSMakeRange(0, [currentName length]) withTemplate:@""];
            menuName = [regexSeparator stringByReplacingMatchesInString:menuName options:0 range:NSMakeRange(0, [menuName length]) withTemplate:@""];
            addSeparator = YES;
        } else {
            
            if( sortMatches == 1) {
                menuName = [regexSort stringByReplacingMatchesInString:currentName options:0 range:NSMakeRange(0, [currentName length]) withTemplate:@""];
                addSeparator = NO;
            }
            if ( separatorMatches == 1 ) {
                menuName = [regexSeparator stringByReplacingMatchesInString:currentName options:0 range:NSMakeRange(0, [currentName length]) withTemplate:@""];
                addSeparator = YES;
            }
        }
    } else {
        menuName = currentName;
        addSeparator = NO;
    }
}

- (void) openHost:(NSMenuItem *) sender {
    NSArray *objectsFromJSON = [[sender representedObject] componentsSeparatedByString:@"¬_¬"];
    NSString *sshCmd = [objectsFromJSON objectAtIndex:0];

    // If it looks like a URL, open it in the browser
    NSURL *url = [NSURL URLWithString:sshCmd];
    if (url && url.scheme && ![url.scheme isEqualToString:@"ssh"]) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    // Per-server terminal override (field 5) takes precedence over global pref
    NSString *termOverride = (objectsFromJSON.count > 5) ? objectsFromJSON[5] : @"";
    NSString *terminal = (termOverride.length > 0 && ![termOverride isEqualToString:@"(null)"])
                         ? termOverride
                         : (terminalPref.length > 0 ? terminalPref : @"terminal");

    NSTask *task = [[NSTask alloc] init];
    NSError *error = nil;

    if ([terminal isEqualToString:@"iterm"]) {
        NSString *script = [NSString stringWithFormat:
            @"tell application \"iTerm\" to create window with default profile command \"%@\"", sshCmd];
        [task setLaunchPath:@"/usr/bin/osascript"];
        [task setArguments:@[@"-e", script]];

    } else if ([terminal isEqualToString:@"terminal"]) {
        // Activate first so the startup window exists, then run inside it.
        NSString *script = [NSString stringWithFormat:
            @"tell application \"Terminal\"\n"
            @"    activate\n"
            @"    if (count windows) = 0 then\n"
            @"        do script \"%@\"\n"
            @"    else\n"
            @"        do script \"%@\" in front window\n"
            @"    end if\n"
            @"end tell",
            sshCmd, sshCmd];
        [task setLaunchPath:@"/usr/bin/osascript"];
        [task setArguments:@[@"-e", script]];

    } else {
        // For all other terminals, find the binary via Launch Services and
        // pass the command with -e (works for Ghostty, Alacritty, kitty, etc.)
        NSDictionary *bundleMap = @{
            @"ghostty":   @"com.mitchellh.ghostty",
            @"alacritty": @"io.alacritty",
            @"kitty":     @"net.kovidgoyal.kitty",
            @"warp":      @"dev.warp.Warp-Stable",
            @"hyper":     @"co.zeit.hyper",
            @"rio":       @"com.raphaelamorim.rio",
        };
        NSString *bundleID = bundleMap[terminal];
        NSString *binary   = bundleID ? [self executableForBundleID:bundleID] : nil;

        if (binary) {
            [task setLaunchPath:binary];
            // Warp uses a URL scheme; others accept -e <cmd>
            if ([terminal isEqualToString:@"warp"]) {
                NSString *encoded = [sshCmd stringByAddingPercentEncodingWithAllowedCharacters:
                                     [NSCharacterSet URLQueryAllowedCharacterSet]];
                NSURL *url = [NSURL URLWithString:
                              [NSString stringWithFormat:@"warp://action/new_tab?command=%@", encoded]];
                [[NSWorkspace sharedWorkspace] openURL:url];
                return;
            }
            [task setArguments:@[@"-e", sshCmd]];
        } else {
            // Unknown or not found — fall back to Terminal.app
            NSString *script = [NSString stringWithFormat:
                @"tell application \"Terminal\"\n"
                @"    activate\n"
                @"    if (count windows) = 0 then\n"
                @"        do script \"%@\"\n"
                @"    else\n"
                @"        do script \"%@\" in front window\n"
                @"    end if\n"
                @"end tell",
                sshCmd, sshCmd];
            [task setLaunchPath:@"/usr/bin/osascript"];
            [task setArguments:@[@"-e", script]];
        }
    }

    [task launchAndReturnError:&error];
    if (error) {
        [self throwError:[NSString stringWithFormat:@"Failed to launch terminal: %@", error.localizedDescription]
          additionalInfo:[NSString stringWithFormat:@"Could not open \"%@\". Check that it is installed.", terminal]
      continueOnErrorOption:NO];
    }
}

- (IBAction)showImportPanel:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowedFileTypes:@[@"json"]];
    if ([panel runModal] != NSModalResponseOK) return;

    NSString *backup = [shuttleConfigFile stringByAppendingString:@".backup"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:backup error:nil];                          // clear any stale backup
    [fm copyItemAtPath:shuttleConfigFile toPath:backup error:nil];   // back up current config
    [fm removeItemAtPath:shuttleConfigFile error:nil];
    NSError *copyErr = nil;
    [fm copyItemAtPath:panel.URL.path toPath:shuttleConfigFile error:&copyErr];
    if (copyErr) {
        // Restore backup on failure
        [fm copyItemAtPath:backup toPath:shuttleConfigFile error:nil];
        [self throwError:@"Import failed" additionalInfo:copyErr.localizedDescription continueOnErrorOption:YES];
        return;
    }
    [self loadMenu];
}

-(void) throwError:(NSString*)errorMessage additionalInfo:(NSString*)errorInfo continueOnErrorOption:(BOOL)continueOption {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setInformativeText:errorInfo];
    [alert setMessageText:errorMessage];
    [alert setAlertStyle:NSWarningAlertStyle];
    
    if (continueOption) {
        [alert addButtonWithTitle:NSLocalizedString(@"Quit",nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Continue",nil)];
        
    }else{
        [alert addButtonWithTitle:NSLocalizedString(@"Quit",nil)];
    }
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [NSApp terminate:NSApp];
    }
}

- (IBAction)showExportPanel:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:@[@"json"]];
    [panel setNameFieldStringValue:@"shuttle.json"];
    if ([panel runModal] != NSModalResponseOK) return;

    NSString *dest = panel.URL.path;
    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil]; // overwrite if exists
    NSError *copyErr = nil;
    [[NSFileManager defaultManager] copyItemAtPath:shuttleConfigFile toPath:dest error:&copyErr];
    if (copyErr)
        [self throwError:@"Export failed" additionalInfo:copyErr.localizedDescription continueOnErrorOption:YES];
}

- (IBAction)configure:(id)sender {
    
    //if the editor setting is omitted or contains 'default' open using the default editor.
    if([editorPref rangeOfString:@"default"].location != NSNotFound) {
        
        [[NSWorkspace sharedWorkspace] openFile:shuttleConfigFile];
    }
    else{
        //build the editor command
        NSString *editorCommand = [NSString stringWithFormat:@"%@ %@", editorPref, shuttleConfigFile];
        
        //build the reprensented object. It's expecting menuCmd, termTheme, termTitle, termWindow, menuName
        NSString *editorRepObj = [NSString stringWithFormat:@"%@¬_¬%@¬_¬%@¬_¬%@¬_¬%@", editorCommand, nil, @"Editing shuttle JSON", nil, nil];
        
        //make a menu item for the command selector(openHost:) runs in a new terminal window.
        NSMenuItem *editorMenu = [[NSMenuItem alloc] initWithTitle:@"editJSONconfig" action:@selector(openHost:) keyEquivalent:(@"")];
        
        //set the command for the menu item
        [editorMenu setRepresentedObject:editorRepObj];
        
        //open the JSON file in the terminal editor.
        [self openHost:editorMenu];
    }
}

- (IBAction)showAbout:(id)sender {
    
    //Call the windows controller
    AboutWindowController *aboutWindow = [[AboutWindowController alloc] initWithWindowNibName:@"AboutWindowController"];
    
    //Set the window to stay on top
    [aboutWindow.window makeKeyAndOrderFront:nil];
    [aboutWindow.window setLevel:NSFloatingWindowLevel];
    
    //Show the window
    [aboutWindow showWindow:self];
}

- (IBAction)quit:(id)sender {
    [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
    [NSApp terminate:NSApp];
}

@end
