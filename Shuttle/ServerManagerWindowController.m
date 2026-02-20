//
//  ServerManagerWindowController.m
//  Shuttle
//

#import "ServerManagerWindowController.h"
#import "AppDelegate.h"

// MARK: - Private interface

@interface ServerManagerWindowController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate>

@property (nonatomic, weak)   AppDelegate     *appDelegate;

// Split layout
@property (nonatomic, strong) NSSplitView     *splitView;

// Left pane
@property (nonatomic, strong) NSScrollView    *sidebarScroll;
@property (nonatomic, strong) NSOutlineView   *outlineView;
@property (nonatomic, strong) NSButton        *addServerBtn;
@property (nonatomic, strong) NSButton        *removeServerBtn;
@property (nonatomic, strong) NSButton        *addCategoryBtn;

// Right pane — detail form
@property (nonatomic, strong) NSView          *detailView;
@property (nonatomic, strong) NSTextField     *placeholderLabel;

@property (nonatomic, strong) NSTextField     *nameField;
@property (nonatomic, strong) NSTextField     *hostnameField;
@property (nonatomic, strong) NSTextField     *userField;
@property (nonatomic, strong) NSTextField     *portField;
@property (nonatomic, strong) NSPopUpButton   *keyPopup;
@property (nonatomic, strong) NSPopUpButton   *categoryPopup;
@property (nonatomic, strong) NSPopUpButton   *terminalPopup;
@property (nonatomic, strong) NSButton        *saveBtn;
@property (nonatomic, strong) NSButton        *deleteBtn;

// State
@property (nonatomic, strong) NSMutableDictionary *selectedServer;

@end

// MARK: - Implementation

@implementation ServerManagerWindowController

- (instancetype)initWithAppDelegate:(AppDelegate *)delegate {
    self = [super initWithWindow:nil];
    if (self) {
        _appDelegate = delegate;
        [self buildWindow];
    }
    return self;
}

// MARK: - Window construction

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 720, 500);
    NSUInteger style = NSWindowStyleMaskTitled
                     | NSWindowStyleMaskClosable
                     | NSWindowStyleMaskResizable
                     | NSWindowStyleMaskMiniaturizable;

    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [win setTitle:@"SSH Manager"];
    [win center];
    [self setWindow:win];

    // ---- Split view ----
    _splitView = [[NSSplitView alloc] initWithFrame:win.contentView.bounds];
    [_splitView setDividerStyle:NSSplitViewDividerStyleThin];
    [_splitView setVertical:YES];
    [_splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [win.contentView addSubview:_splitView];

    // ---- Left pane ----
    NSView *leftPane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 500)];

    // Outline view
    _outlineView = [[NSOutlineView alloc] init];
    [_outlineView setDataSource:self];
    [_outlineView setDelegate:self];
    [_outlineView setHeaderView:nil];
    [_outlineView setRowSizeStyle:NSTableViewRowSizeStyleMedium];
    [_outlineView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
    [_outlineView setFloatsGroupRows:NO];

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    [col setMinWidth:100];
    [_outlineView addTableColumn:col];
    [_outlineView setOutlineTableColumn:col];

    _sidebarScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 32, 220, 468)];
    [_sidebarScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_sidebarScroll setHasVerticalScroller:YES];
    [_sidebarScroll setDocumentView:_outlineView];
    [leftPane addSubview:_sidebarScroll];

    // Bottom bar buttons
    NSView *bottomBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 32)];
    [bottomBar setAutoresizingMask:NSViewWidthSizable];

    _addServerBtn = [NSButton buttonWithTitle:@"+" target:self action:@selector(addServer:)];
    [_addServerBtn setFrame:NSMakeRect(4, 4, 26, 24)];
    [_addServerBtn setBezelStyle:NSBezelStyleRounded];
    [_addServerBtn setFont:[NSFont systemFontOfSize:16]];
    [bottomBar addSubview:_addServerBtn];

    _removeServerBtn = [NSButton buttonWithTitle:@"−" target:self action:@selector(removeServer:)];
    [_removeServerBtn setFrame:NSMakeRect(32, 4, 26, 24)];
    [_removeServerBtn setBezelStyle:NSBezelStyleRounded];
    [_removeServerBtn setFont:[NSFont systemFontOfSize:16]];
    [bottomBar addSubview:_removeServerBtn];

    _addCategoryBtn = [NSButton buttonWithTitle:@"+ Category" target:self action:@selector(addCategory:)];
    [_addCategoryBtn setFrame:NSMakeRect(62, 4, 90, 24)];
    [_addCategoryBtn setBezelStyle:NSBezelStyleRounded];
    [_addCategoryBtn setFont:[NSFont systemFontOfSize:11]];
    [bottomBar addSubview:_addCategoryBtn];

    [leftPane addSubview:bottomBar];
    [_splitView addSubview:leftPane];

    // ---- Right pane (detail) ----
    _detailView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 500)];
    [_detailView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // Placeholder
    _placeholderLabel = [NSTextField labelWithString:@"Select a server or add a new one."];
    [_placeholderLabel setAlignment:NSTextAlignmentCenter];
    [_placeholderLabel setTextColor:[NSColor secondaryLabelColor]];
    [_placeholderLabel setFont:[NSFont systemFontOfSize:14]];
    [_placeholderLabel setFrame:NSMakeRect(0, 200, 500, 30)];
    [_placeholderLabel setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin | NSViewMinYMargin];
    [_detailView addSubview:_placeholderLabel];

    // Form fields — built inside a container view
    NSView *form = [self buildForm];
    [form setHidden:YES];
    [_detailView addSubview:form];

    [_splitView addSubview:_detailView];

    // Set initial divider position after window is shown
    [_splitView setPosition:220 ofDividerAtIndex:0];
}

- (NSView *)buildForm {
    NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 500)];
    [form setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    form.identifier = @"formContainer";

    CGFloat x = 130, w = 300, lx = 20, lw = 105, row = 420, rowH = 30, gap = 36;

    // Helper blocks
    NSTextField *(^makeLabel)(NSString *) = ^NSTextField *(NSString *text) {
        NSTextField *lbl = [NSTextField labelWithString:text];
        [lbl setAlignment:NSTextAlignmentRight];
        [lbl setFont:[NSFont systemFontOfSize:12]];
        return lbl;
    };

    NSTextField *(^makeField)(void) = ^NSTextField *(void) {
        NSTextField *f = [[NSTextField alloc] init];
        [f setBezelStyle:NSTextFieldSquareBezel];
        [f setBordered:YES];
        [f setEditable:YES];
        return f;
    };

    // Name (larger)
    NSTextField *nameLbl = makeLabel(@"Name:");
    [nameLbl setFrame:NSMakeRect(lx, row, lw, rowH)];
    [form addSubview:nameLbl];

    _nameField = makeField();
    [_nameField setFont:[NSFont boldSystemFontOfSize:14]];
    [_nameField setFrame:NSMakeRect(x, row, w, rowH)];
    [_nameField setDelegate:self];
    [form addSubview:_nameField];
    row -= gap;

    // Hostname
    NSTextField *hostLbl = makeLabel(@"Hostname:");
    [hostLbl setFrame:NSMakeRect(lx, row, lw, rowH)];
    [form addSubview:hostLbl];

    _hostnameField = makeField();
    [_hostnameField setFrame:NSMakeRect(x, row, w, rowH)];
    [_hostnameField setDelegate:self];
    [form addSubview:_hostnameField];
    row -= gap;

    // Username + Port side by side
    NSTextField *userLbl = makeLabel(@"User:");
    [userLbl setFrame:NSMakeRect(lx, row, lw, rowH)];
    [form addSubview:userLbl];

    _userField = makeField();
    [_userField setFrame:NSMakeRect(x, row, 140, rowH)];
    [_userField setDelegate:self];
    [form addSubview:_userField];

    NSTextField *portLbl = makeLabel(@"Port:");
    [portLbl setAlignment:NSTextAlignmentLeft];
    [portLbl setFrame:NSMakeRect(x + 148, row, 38, rowH)];
    [form addSubview:portLbl];

    _portField = makeField();
    [_portField setFrame:NSMakeRect(x + 190, row, 110, rowH)];
    [_portField setPlaceholderString:@"22"];
    [_portField setDelegate:self];
    [form addSubview:_portField];
    row -= gap;

    // SSH Key
    NSTextField *keyLbl = makeLabel(@"SSH Key:");
    [keyLbl setFrame:NSMakeRect(lx, row, lw, rowH)];
    [form addSubview:keyLbl];

    _keyPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, row, w, rowH) pullsDown:NO];
    [form addSubview:_keyPopup];
    row -= gap;

    // Category
    NSTextField *catLbl = makeLabel(@"Category:");
    [catLbl setFrame:NSMakeRect(lx, row, lw, rowH)];
    [form addSubview:catLbl];

    _categoryPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, row, w, rowH) pullsDown:NO];
    [form addSubview:_categoryPopup];
    row -= gap;

    // Terminal
    NSTextField *termLbl = makeLabel(@"Terminal:");
    [termLbl setFrame:NSMakeRect(lx, row, lw, rowH)];
    [form addSubview:termLbl];

    _terminalPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, row, w, rowH) pullsDown:NO];
    [_terminalPopup addItemsWithTitles:@[@"Default (from settings)", @"terminal", @"iterm", @"ghostty"]];
    [form addSubview:_terminalPopup];
    row -= gap;

    row -= 10; // spacer

    // Save + Delete buttons
    _saveBtn = [NSButton buttonWithTitle:@"Save" target:self action:@selector(saveServer:)];
    [_saveBtn setFrame:NSMakeRect(x, row, 90, 28)];
    [_saveBtn setBezelStyle:NSBezelStyleRounded];
    [_saveBtn setKeyEquivalent:@"\r"];
    [form addSubview:_saveBtn];

    _deleteBtn = [NSButton buttonWithTitle:@"Delete Server" target:self action:@selector(deleteServer:)];
    [_deleteBtn setFrame:NSMakeRect(x + 100, row, 120, 28)];
    [_deleteBtn setBezelStyle:NSBezelStyleRounded];
    [form addSubview:_deleteBtn];

    return form;
}

// MARK: - Public

- (void)reload {
    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];
    [self clearDetail];
}

// MARK: - Outline data source

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
    if (item == nil) {
        return (NSInteger)[_appDelegate.categories count];
    }
    if ([item isKindOfClass:[NSString class]]) {
        NSString *cat = item;
        return (NSInteger)[[_appDelegate.servers filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"category == %@", cat]] count];
    }
    return 0;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item {
    if (item == nil) {
        return _appDelegate.categories[(NSUInteger)index];
    }
    if ([item isKindOfClass:[NSString class]]) {
        NSString *cat = item;
        NSArray *catServers = [_appDelegate.servers filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"category == %@", cat]];
        return catServers[(NSUInteger)index];
    }
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
    return [item isKindOfClass:[NSString class]];
}

// MARK: - Outline delegate

- (BOOL)outlineView:(NSOutlineView *)ov isGroupItem:(id)item {
    return [item isKindOfClass:[NSString class]];
}

- (BOOL)outlineView:(NSOutlineView *)ov shouldSelectItem:(id)item {
    return [item isKindOfClass:[NSDictionary class]];
}

- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)col item:(id)item {
    if ([item isKindOfClass:[NSString class]]) {
        NSString *cat = item;
        NSTableCellView *cell = [ov makeViewWithIdentifier:@"groupCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
            cell.identifier = @"groupCell";
            NSTextField *tf = [NSTextField labelWithString:@""];
            tf.identifier = @"text";
            tf.font = [NSFont boldSystemFontOfSize:11];
            [cell addSubview:tf];
            cell.textField = tf;
        }
        cell.textField.stringValue = cat;
        return cell;
    }

    // Server row
    NSDictionary *server = item;
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"serverCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"serverCell";
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.identifier = @"text";
        tf.font = [NSFont systemFontOfSize:13];
        [cell addSubview:tf];
        cell.textField = tf;
    }
    NSString *displayName = server[@"name"] ?: server[@"hostname"] ?: @"Unnamed";
    cell.textField.stringValue = displayName;
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    id item = [_outlineView itemAtRow:[_outlineView selectedRow]];
    if ([item isKindOfClass:[NSDictionary class]]) {
        _selectedServer = (NSMutableDictionary *)item;
        [self populateForm];
    } else {
        [self clearDetail];
    }
}

// MARK: - Detail form helpers

- (void)clearDetail {
    _selectedServer = nil;
    _placeholderLabel.hidden = NO;
    [self formView].hidden = YES;
}

- (NSView *)formView {
    for (NSView *v in _detailView.subviews) {
        if ([v.identifier isEqualToString:@"formContainer"]) return v;
    }
    return nil;
}

- (void)populateForm {
    // Populate SSH key popup from ~/.ssh/
    [_keyPopup removeAllItems];
    [_keyPopup addItemWithTitle:@"None"];
    NSString *sshDir = [NSHomeDirectory() stringByAppendingPathComponent:@".ssh"];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:sshDir error:nil];
    for (NSString *f in files) {
        // Private keys: no .pub extension, not known_hosts/config/authorized_keys
        if ([f hasSuffix:@".pub"]) continue;
        if ([f isEqualToString:@"known_hosts"] || [f isEqualToString:@"config"]
            || [f isEqualToString:@"authorized_keys"] || [f hasPrefix:@"."]) continue;
        [_keyPopup addItemWithTitle:f];
    }

    // Populate category popup
    [_categoryPopup removeAllItems];
    [_categoryPopup addItemsWithTitles:_appDelegate.categories];

    // Fill in current server values
    NSString *name = _selectedServer[@"name"] ?: @"";
    NSString *host = _selectedServer[@"hostname"] ?: @"";
    NSString *user = _selectedServer[@"user"] ?: @"";
    NSString *port = _selectedServer[@"port"] ? [_selectedServer[@"port"] stringValue] : @"";
    NSString *key  = _selectedServer[@"identity_file"] ?: @"";
    NSString *cat  = _selectedServer[@"category"] ?: @"";
    NSString *term = _selectedServer[@"terminal"] ?: @"";

    _nameField.stringValue     = name;
    _hostnameField.stringValue = host;
    _userField.stringValue     = user;
    _portField.stringValue     = port;

    if (key.length > 0 && [_keyPopup itemWithTitle:key])
        [_keyPopup selectItemWithTitle:key];
    else
        [_keyPopup selectItemAtIndex:0];

    if (cat.length > 0 && [_categoryPopup itemWithTitle:cat])
        [_categoryPopup selectItemWithTitle:cat];

    if (term.length > 0 && [_terminalPopup itemWithTitle:term])
        [_terminalPopup selectItemWithTitle:term];
    else
        [_terminalPopup selectItemAtIndex:0];

    NSView *form = [self formView];
    form.hidden = NO;
    _placeholderLabel.hidden = YES;
}

// MARK: - Add / Remove actions

- (IBAction)addServer:(id)sender {
    // Find the first category (or create one)
    NSMutableArray *cats = _appDelegate.categories;
    if (cats.count == 0) {
        [cats addObject:@"SERVERS"];
    }
    NSString *defaultCat = cats.firstObject;

    NSMutableDictionary *newServer = [@{
        @"name":     @"New Server",
        @"hostname": @"",
        @"category": defaultCat
    } mutableCopy];

    [_appDelegate.servers addObject:newServer];
    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];

    // Select the new row
    NSInteger row = [_outlineView rowForItem:newServer];
    if (row >= 0) {
        [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                  byExtendingSelection:NO];
        [_outlineView scrollRowToVisible:row];
    }
}

- (IBAction)removeServer:(id)sender {
    if (!_selectedServer) return;
    [_appDelegate.servers removeObject:_selectedServer];
    [self clearDetail];
    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];
    [self saveToFile];
}

- (IBAction)addCategory:(id)sender {
    // Sheet-style prompt
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"New Category Name:"];
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    [input setPlaceholderString:@"e.g. PRODUCTION"];
    [alert setAccessoryView:input];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *catName = [[input stringValue]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (catName.length == 0) return;
        if ([_appDelegate.categories containsObject:catName]) return;
        [_appDelegate.categories addObject:catName];
        [_categoryPopup addItemWithTitle:catName];
        [_outlineView reloadData];
        [_outlineView expandItem:nil expandChildren:YES];
        [self saveToFile];
    }
}

// MARK: - Save / Delete

- (IBAction)saveServer:(id)sender {
    if (!_selectedServer) return;

    _selectedServer[@"name"]     = _nameField.stringValue;
    _selectedServer[@"hostname"] = _hostnameField.stringValue;
    _selectedServer[@"user"]     = _userField.stringValue;

    NSInteger port = [_portField.stringValue integerValue];
    if (port > 0)
        _selectedServer[@"port"] = @(port);
    else
        [_selectedServer removeObjectForKey:@"port"];

    NSString *selectedKey = [_keyPopup titleOfSelectedItem];
    if ([selectedKey isEqualToString:@"None"] || selectedKey.length == 0)
        [_selectedServer removeObjectForKey:@"identity_file"];
    else
        _selectedServer[@"identity_file"] = [[@"~/.ssh/" stringByAppendingString:selectedKey]
                                              stringByExpandingTildeInPath];

    _selectedServer[@"category"] = [_categoryPopup titleOfSelectedItem] ?: @"";

    NSString *term = [_terminalPopup titleOfSelectedItem];
    if ([term isEqualToString:@"Default (from settings)"] || term.length == 0)
        [_selectedServer removeObjectForKey:@"terminal"];
    else
        _selectedServer[@"terminal"] = term;

    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];

    // Re-select the saved server
    NSInteger row = [_outlineView rowForItem:_selectedServer];
    if (row >= 0)
        [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                  byExtendingSelection:NO];

    [self saveToFile];
}

- (IBAction)deleteServer:(id)sender {
    if (!_selectedServer) return;
    NSAlert *confirm = [[NSAlert alloc] init];
    [confirm setMessageText:@"Delete this server?"];
    [confirm setInformativeText:[NSString stringWithFormat:@"\"%@\" will be removed from your address book.",
                                  _selectedServer[@"name"] ?: _selectedServer[@"hostname"]]];
    [confirm addButtonWithTitle:@"Delete"];
    [confirm addButtonWithTitle:@"Cancel"];
    if ([confirm runModal] == NSAlertFirstButtonReturn) {
        [_appDelegate.servers removeObject:_selectedServer];
        [self clearDetail];
        [_outlineView reloadData];
        [_outlineView expandItem:nil expandChildren:YES];
        [self saveToFile];
    }
}

// MARK: - Persist to JSON

- (void)saveToFile {
    NSString *path = _appDelegate.configFilePath;
    NSData *existing = [NSData dataWithContentsOfFile:path];
    id json = existing ? [NSJSONSerialization JSONObjectWithData:existing
                                                         options:NSJSONReadingMutableContainers
                                                           error:nil] : nil;
    NSMutableDictionary *root = json ? [json mutableCopy] : [NSMutableDictionary dictionary];

    root[@"categories"] = _appDelegate.categories;
    root[@"servers"]    = _appDelegate.servers;
    [root removeObjectForKey:@"hosts"]; // remove legacy key if present

    NSData *out = [NSJSONSerialization dataWithJSONObject:root
                                                  options:NSJSONWritingPrettyPrinted
                                                    error:nil];
    [out writeToFile:path atomically:YES];
    [_appDelegate loadMenu];
}

@end
