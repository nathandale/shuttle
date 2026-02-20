//
//  ServerManagerWindowController.m
//  Shuttle
//

#import "ServerManagerWindowController.h"
#import "AppDelegate.h"

@interface ServerManagerWindowController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate>

@property (nonatomic, weak)   AppDelegate           *appDelegate;

// Layout
@property (nonatomic, strong) NSSplitView           *splitView;

// Left pane
@property (nonatomic, strong) NSVisualEffectView    *sidebar;
@property (nonatomic, strong) NSOutlineView         *outlineView;
@property (nonatomic, strong) NSSegmentedControl    *addRemoveControl;

// Right pane
@property (nonatomic, strong) NSView                *detailPane;
@property (nonatomic, strong) NSTextField           *placeholderLabel;

// Form — built once, shown/hidden
@property (nonatomic, strong) NSView                *formContainer;
@property (nonatomic, strong) NSTextField           *nameField;
@property (nonatomic, strong) NSTextField           *hostnameField;
@property (nonatomic, strong) NSTextField           *userField;
@property (nonatomic, strong) NSTextField           *portField;
@property (nonatomic, strong) NSPopUpButton         *keyPopup;
@property (nonatomic, strong) NSPopUpButton         *categoryPopup;
@property (nonatomic, strong) NSPopUpButton         *terminalPopup;
@property (nonatomic, strong) NSTextField           *initialDirField;
@property (nonatomic, strong) NSButton              *saveBtn;
@property (nonatomic, strong) NSButton              *deleteBtn;

// State
@property (nonatomic, strong) NSMutableDictionary   *selectedServer;

@end

@implementation ServerManagerWindowController

static const CGFloat kSidebarWidth  = 200.0;
static const CGFloat kBottomBarH    = 34.0;
static const CGFloat kLabelColW     = 78.0;
static const CGFloat kFieldColW     = 270.0;
static const CGFloat kRowSpacing    = 10.0;
static const CGFloat kColSpacing    = 8.0;

// MARK: - Init

- (instancetype)initWithAppDelegate:(AppDelegate *)delegate {
    self = [super initWithWindow:nil];
    if (self) {
        _appDelegate = delegate;
        [self buildWindow];
    }
    return self;
}

// MARK: - Window

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 700, 480);
    NSWindowStyleMask style = NSWindowStyleMaskTitled
                            | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskMiniaturizable
                            | NSWindowStyleMaskResizable;
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = @"SSH Manager";
    win.minSize = NSMakeSize(580, 380);
    [win center];
    [self setWindow:win];

    _splitView = [[NSSplitView alloc] initWithFrame:win.contentView.bounds];
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.vertical = YES;
    _splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [win.contentView addSubview:_splitView];

    [self buildSidebar];
    [self buildDetailPane];

    [_splitView setPosition:kSidebarWidth ofDividerAtIndex:0];
}

// MARK: - Sidebar

- (void)buildSidebar {
    NSRect r = NSMakeRect(0, 0, kSidebarWidth, 480);

    _sidebar = [[NSVisualEffectView alloc] initWithFrame:r];
    _sidebar.material    = NSVisualEffectMaterialSidebar;
    _sidebar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _sidebar.state       = NSVisualEffectStateActive;

    // ---- Outline scroll view ----
    NSRect scrollFrame = NSMakeRect(0, kBottomBarH, kSidebarWidth, 480 - kBottomBarH);
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:scrollFrame];
    scroll.autoresizingMask   = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground    = NO;

    _outlineView = [[NSOutlineView alloc] init];
    _outlineView.dataSource               = self;
    _outlineView.delegate                 = self;
    _outlineView.headerView               = nil;
    _outlineView.rowSizeStyle             = NSTableViewRowSizeStyleDefault;
    _outlineView.selectionHighlightStyle  = NSTableViewSelectionHighlightStyleSourceList;
    _outlineView.floatsGroupRows          = NO;
    _outlineView.backgroundColor          = [NSColor clearColor];
    _outlineView.intercellSpacing         = NSMakeSize(0, 2);

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"col"];
    col.minWidth = 80;
    [_outlineView addTableColumn:col];
    _outlineView.outlineTableColumn = col;

    scroll.documentView = _outlineView;
    [_sidebar addSubview:scroll];

    // ---- Bottom action bar ----
    NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarWidth, kBottomBarH)];
    bar.autoresizingMask = NSViewWidthSizable;

    // Hairline separator at top of bar
    NSBox *sep = [[NSBox alloc] initWithFrame:NSMakeRect(0, kBottomBarH - 1, kSidebarWidth, 1)];
    sep.boxType = NSBoxSeparator;
    sep.autoresizingMask = NSViewWidthSizable;
    [bar addSubview:sep];

    // +/− segmented control
    _addRemoveControl = [NSSegmentedControl
        segmentedControlWithLabels:@[@"+", @"−"]
                      trackingMode:NSSegmentSwitchTrackingMomentary
                            target:self
                            action:@selector(addRemoveAction:)];
    _addRemoveControl.frame = NSMakeRect(7, 5, 54, 24);
    _addRemoveControl.font  = [NSFont systemFontOfSize:16 weight:NSFontWeightLight];
    [bar addSubview:_addRemoveControl];

    // New Category button
    NSButton *catBtn = [NSButton buttonWithTitle:@"New Category"
                                          target:self
                                          action:@selector(addCategory:)];
    catBtn.bezelStyle = NSBezelStyleRounded;
    catBtn.font       = [NSFont systemFontOfSize:11];
    catBtn.frame      = NSMakeRect(66, 5, 110, 24);
    [bar addSubview:catBtn];

    [_sidebar addSubview:bar];
    [_splitView addSubview:_sidebar];
}

// MARK: - Detail pane

- (void)buildDetailPane {
    _detailPane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 480)];
    _detailPane.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Placeholder shown when nothing is selected
    _placeholderLabel = [NSTextField labelWithString:@"Select a server or press + to add one."];
    _placeholderLabel.alignment  = NSTextAlignmentCenter;
    _placeholderLabel.textColor  = [NSColor tertiaryLabelColor];
    _placeholderLabel.font       = [NSFont systemFontOfSize:13];
    _placeholderLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    [_detailPane addSubview:_placeholderLabel];

    // Form container
    _formContainer = [[NSView alloc] init];
    _formContainer.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    _formContainer.hidden = YES;

    [self buildFormFields];
    [_detailPane addSubview:_formContainer];
    [_splitView addSubview:_detailPane];
}

// MARK: - Form fields (NSGridView)

- (void)buildFormFields {
    // Label factory: right-aligned, small, secondary color
    NSTextField *(^lbl)(NSString *) = ^(NSString *t) {
        NSTextField *f = [NSTextField labelWithString:t];
        f.alignment  = NSTextAlignmentRight;
        f.font       = [NSFont systemFontOfSize:12];
        f.textColor  = [NSColor secondaryLabelColor];
        return f;
    };

    // Text field factory
    NSTextField *(^fld)(NSString *) = ^(NSString *ph) {
        NSTextField *f = [[NSTextField alloc] init];
        f.bezeled          = YES;
        f.bezelStyle       = NSTextFieldSquareBezel;
        f.editable         = YES;
        f.font             = [NSFont systemFontOfSize:13];
        f.placeholderString = ph;
        f.delegate         = self;
        return f;
    };

    _nameField     = fld(@"Display name");
    _nameField.font = [NSFont systemFontOfSize:15];

    _hostnameField = fld(@"hostname, .local name, or IP address");
    _userField     = fld(@"username");
    _portField     = fld(@"22");

    _keyPopup      = [[NSPopUpButton alloc] init];
    _keyPopup.font = [NSFont systemFontOfSize:13];

    _categoryPopup      = [[NSPopUpButton alloc] init];
    _categoryPopup.font = [NSFont systemFontOfSize:13];

    _terminalPopup = [[NSPopUpButton alloc] init];
    _terminalPopup.font = [NSFont systemFontOfSize:13];
    [self rebuildTerminalPopup];

    _initialDirField = fld(@"e.g. ~/bin  (optional)");

    // Grid: two columns — label | control
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[lbl(@"Name"),        _nameField],
        @[lbl(@"Hostname"),    _hostnameField],
        @[lbl(@"User"),        _userField],
        @[lbl(@"Port"),        _portField],
        @[lbl(@"SSH Key"),     _keyPopup],
        @[lbl(@"Category"),    _categoryPopup],
        @[lbl(@"Terminal"),    _terminalPopup],
        @[lbl(@"Initial Dir"), _initialDirField],
    ]];
    grid.rowSpacing    = kRowSpacing;
    grid.columnSpacing = kColSpacing;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:0].width      = kLabelColW;
    [grid columnAtIndex:1].width      = kFieldColW;

    // Buttons below grid
    _saveBtn = [NSButton buttonWithTitle:@"Save Changes"
                                  target:self action:@selector(saveServer:)];
    _saveBtn.bezelStyle   = NSBezelStyleRounded;
    _saveBtn.keyEquivalent = @"\r";

    _deleteBtn = [NSButton buttonWithTitle:@"Delete Server"
                                    target:self action:@selector(deleteServer:)];
    _deleteBtn.bezelStyle = NSBezelStyleRounded;

    // Size everything, place in formContainer
    CGSize gs = grid.fittingSize;
    CGFloat totalW = gs.width;
    CGFloat btnH   = 28.0;
    CGFloat gap    = 14.0;
    CGFloat totalH = gs.height + gap + btnH;

    _formContainer.frame = NSMakeRect(0, 0, totalW, totalH);

    grid.frame = NSMakeRect(0, btnH + gap, gs.width, gs.height);
    [_formContainer addSubview:grid];

    _saveBtn.frame   = NSMakeRect(kLabelColW + kColSpacing, 0, 120, btnH);
    _deleteBtn.frame = NSMakeRect(kLabelColW + kColSpacing + 128, 0, 120, btnH);
    [_formContainer addSubview:_saveBtn];
    [_formContainer addSubview:_deleteBtn];
}

// Centers formContainer inside detailPane
- (void)layoutFormInPane {
    CGFloat pw = _detailPane.bounds.size.width  ?: 500;
    CGFloat ph = _detailPane.bounds.size.height ?: 480;
    CGFloat fw = _formContainer.bounds.size.width;
    CGFloat fh = _formContainer.bounds.size.height;
    CGFloat x  = floor((pw - fw) / 2.0);
    CGFloat y  = floor((ph - fh) / 2.0) + 20; // slightly above center
    _formContainer.frame = NSMakeRect(x, y, fw, fh);

    _placeholderLabel.frame = NSMakeRect(0, floor(ph / 2.0) - 10, pw, 20);
}

// MARK: - Public

- (void)reload {
    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];
    [self showPlaceholder];
}

// MARK: - NSOutlineView data source

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
    if (!item)
        return (NSInteger)_appDelegate.categories.count;
    if ([item isKindOfClass:[NSString class]])
        return (NSInteger)[[_appDelegate.servers filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"category == %@", item]] count];
    return 0;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)idx ofItem:(id)item {
    if (!item)
        return _appDelegate.categories[(NSUInteger)idx];
    if ([item isKindOfClass:[NSString class]]) {
        NSArray *cs = [_appDelegate.servers filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"category == %@", item]];
        return cs[(NSUInteger)idx];
    }
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
    return [item isKindOfClass:[NSString class]];
}

// MARK: - NSOutlineView delegate

- (BOOL)outlineView:(NSOutlineView *)ov isGroupItem:(id)item {
    return [item isKindOfClass:[NSString class]];
}

- (BOOL)outlineView:(NSOutlineView *)ov shouldSelectItem:(id)item {
    return [item isKindOfClass:[NSDictionary class]];
}

- (NSTableRowView *)outlineView:(NSOutlineView *)ov rowViewForItem:(id)item {
    return nil; // use default
}

- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)tc item:(id)item {
    if ([item isKindOfClass:[NSString class]]) {
        NSTableCellView *cell = [ov makeViewWithIdentifier:@"group" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = @"group";
            NSTextField *tf = [NSTextField labelWithString:@""];
            tf.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
            tf.textColor = [NSColor secondaryLabelColor];
            tf.identifier = @"text";
            [cell addSubview:tf];
            cell.textField = tf;
        }
        cell.textField.stringValue = [(NSString *)item uppercaseString];
        return cell;
    }

    NSDictionary *server = item;
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"server" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = @"server";
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.font = [NSFont systemFontOfSize:13];
        tf.identifier = @"text";
        [cell addSubview:tf];
        cell.textField = tf;
    }
    NSString *name = server[@"name"] ?: server[@"hostname"] ?: @"Unnamed";
    cell.textField.stringValue = name;
    return cell;
}

- (CGFloat)outlineView:(NSOutlineView *)ov heightOfRowByItem:(id)item {
    return [item isKindOfClass:[NSString class]] ? 22.0 : 28.0;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note {
    id item = [_outlineView itemAtRow:_outlineView.selectedRow];
    if ([item isKindOfClass:[NSDictionary class]]) {
        _selectedServer = (NSMutableDictionary *)item;
        [self populateForm];
    } else {
        [self showPlaceholder];
    }
}

// MARK: - Show / hide form

- (void)rebuildTerminalPopup {
    NSString *current = [_terminalPopup titleOfSelectedItem];
    [_terminalPopup removeAllItems];
    [_terminalPopup addItemWithTitle:@"Default (from settings)"];
    for (NSDictionary *t in [_appDelegate installedTerminals]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:t[@"name"] action:nil keyEquivalent:@""];
        item.representedObject = t[@"id"]; // store the JSON identifier
        [_terminalPopup.menu addItem:item];
    }
    // Restore previous selection if still available
    if (current && [_terminalPopup itemWithTitle:current])
        [_terminalPopup selectItemWithTitle:current];
    else
        [_terminalPopup selectItemAtIndex:0];
}

- (void)showPlaceholder {
    _selectedServer = nil;
    [self layoutFormInPane];
    _formContainer.hidden    = YES;
    _placeholderLabel.hidden = NO;
}

- (void)populateForm {
    // SSH keys from ~/.ssh/
    [_keyPopup removeAllItems];
    [_keyPopup addItemWithTitle:@"None"];
    NSString *sshDir = [NSHomeDirectory() stringByAppendingPathComponent:@".ssh"];
    NSArray *sshFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:sshDir error:nil];
    for (NSString *f in sshFiles) {
        if ([f hasSuffix:@".pub"])    continue;
        if ([f isEqualToString:@"known_hosts"]    ||
            [f isEqualToString:@"config"]          ||
            [f isEqualToString:@"authorized_keys"] ||
            [f hasPrefix:@"."])                    continue;
        [_keyPopup addItemWithTitle:f];
    }

    // Categories
    [_categoryPopup removeAllItems];
    [_categoryPopup addItemsWithTitles:_appDelegate.categories];

    // Fill values
    _nameField.stringValue     = _selectedServer[@"name"]     ?: @"";
    _hostnameField.stringValue = _selectedServer[@"hostname"] ?: @"";
    _userField.stringValue     = _selectedServer[@"user"]     ?: @"";
    _portField.stringValue     = _selectedServer[@"port"] ? [_selectedServer[@"port"] stringValue] : @"";

    NSString *key  = _selectedServer[@"identity_file"] ?: @"";
    NSString *keyName = [key lastPathComponent];
    if (keyName.length && [_keyPopup itemWithTitle:keyName])
        [_keyPopup selectItemWithTitle:keyName];
    else
        [_keyPopup selectItemAtIndex:0];

    NSString *cat = _selectedServer[@"category"] ?: @"";
    if ([_categoryPopup itemWithTitle:cat]) [_categoryPopup selectItemWithTitle:cat];

    [self rebuildTerminalPopup];
    NSString *term = _selectedServer[@"terminal"] ?: @"";
    // Match by stored identifier (representedObject on each item)
    BOOL matched = NO;
    if (term.length) {
        for (NSMenuItem *item in _terminalPopup.itemArray) {
            if ([item.representedObject isEqualToString:term]) {
                [_terminalPopup selectItem:item];
                matched = YES;
                break;
            }
        }
    }
    if (!matched) [_terminalPopup selectItemAtIndex:0];

    _initialDirField.stringValue = _selectedServer[@"initial_directory"] ?: @"";

    [self layoutFormInPane];
    _placeholderLabel.hidden = YES;
    _formContainer.hidden    = NO;
}

// MARK: - Add / Remove server

- (IBAction)addRemoveAction:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == 0)
        [self addServer];
    else
        [self removeServer];
}

- (void)addServer {
    if (_appDelegate.categories.count == 0)
        [_appDelegate.categories addObject:@"SERVERS"];

    NSMutableDictionary *s = [@{
        @"name":     @"New Server",
        @"hostname": @"",
        @"category": _appDelegate.categories.firstObject
    } mutableCopy];
    [_appDelegate.servers addObject:s];

    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];

    NSInteger row = [_outlineView rowForItem:s];
    if (row >= 0) {
        [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                  byExtendingSelection:NO];
        [_outlineView scrollRowToVisible:row];
    }
}

- (void)removeServer {
    if (!_selectedServer) return;
    [_appDelegate.servers removeObject:_selectedServer];
    [self showPlaceholder];
    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];
    [self saveToFile];
}

// MARK: - Add category

- (IBAction)addCategory:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"New Category";
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 22)];
    input.placeholderString = @"e.g. PRODUCTION";
    input.font = [NSFont systemFontOfSize:13];
    alert.accessoryView = input;
    [alert.window makeFirstResponder:input];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *name = [input.stringValue stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length || [_appDelegate.categories containsObject:name.uppercaseString]) return;

    [_appDelegate.categories addObject:name.uppercaseString];
    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];
    [self saveToFile];
}

// MARK: - Save server

- (IBAction)saveServer:(id)sender {
    if (!_selectedServer) return;

    _selectedServer[@"name"]     = _nameField.stringValue;
    _selectedServer[@"hostname"] = _hostnameField.stringValue;
    _selectedServer[@"user"]     = _userField.stringValue;

    NSInteger port = _portField.stringValue.integerValue;
    if (port > 0 && port != 22)
        _selectedServer[@"port"] = @(port);
    else
        [_selectedServer removeObjectForKey:@"port"];

    NSString *selKey = [_keyPopup titleOfSelectedItem];
    if (!selKey || [selKey isEqualToString:@"None"])
        [_selectedServer removeObjectForKey:@"identity_file"];
    else
        _selectedServer[@"identity_file"] = [@"~/.ssh/" stringByAppendingString:selKey];

    _selectedServer[@"category"] = [_categoryPopup titleOfSelectedItem] ?: @"";

    NSMenuItem *termItem = [_terminalPopup selectedItem];
    NSString *termID = termItem.representedObject; // the JSON identifier e.g. "ghostty"
    if (!termID || termID.length == 0)
        [_selectedServer removeObjectForKey:@"terminal"];
    else
        _selectedServer[@"terminal"] = termID;

    NSString *initialDir = [_initialDirField.stringValue stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (initialDir.length > 0)
        _selectedServer[@"initial_directory"] = initialDir;
    else
        [_selectedServer removeObjectForKey:@"initial_directory"];

    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];

    NSInteger row = [_outlineView rowForItem:_selectedServer];
    if (row >= 0)
        [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                  byExtendingSelection:NO];
    [self saveToFile];
}

// MARK: - Delete server

- (IBAction)deleteServer:(id)sender {
    if (!_selectedServer) return;

    NSAlert *a = [[NSAlert alloc] init];
    a.messageText     = @"Delete this server?";
    a.informativeText = [NSString stringWithFormat:@"\"%@\" will be permanently removed.",
                         _selectedServer[@"name"] ?: _selectedServer[@"hostname"] ?: @"This server"];
    [a addButtonWithTitle:@"Delete"];
    [a addButtonWithTitle:@"Cancel"];
    a.buttons.firstObject.hasDestructiveAction = YES;

    if ([a runModal] != NSAlertFirstButtonReturn) return;

    [_appDelegate.servers removeObject:_selectedServer];
    [self showPlaceholder];
    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];
    [self saveToFile];
}

// MARK: - Persist

- (void)saveToFile {
    NSString *path = _appDelegate.configFilePath;
    NSData *existing = [NSData dataWithContentsOfFile:path];
    id parsed = existing ? [NSJSONSerialization JSONObjectWithData:existing
                                                           options:NSJSONReadingMutableContainers
                                                             error:nil] : nil;
    NSMutableDictionary *root = parsed ? [parsed mutableCopy] : [NSMutableDictionary dictionary];
    root[@"categories"] = _appDelegate.categories;
    root[@"servers"]    = _appDelegate.servers;
    [root removeObjectForKey:@"hosts"];

    NSData *out = [NSJSONSerialization dataWithJSONObject:root
                                                  options:NSJSONWritingPrettyPrinted
                                                    error:nil];
    [out writeToFile:path atomically:YES];
    [_appDelegate loadMenu];
}

@end
