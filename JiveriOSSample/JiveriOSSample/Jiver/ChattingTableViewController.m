//
//  ChattingTableViewController.m
//  JiveriOSSample
//
//  Created by Jed Kyung on 2015. 7. 29..
//  Copyright (c) 2015년 JIVER.CO. All rights reserved.
//

#import "ChattingTableViewController.h"

#define kMessageCellIdentifier @"MessageReuseIdentifier"
#define kFileLinkCellIdentifier @"FileLinkReuseIdentifier"
#define kSystemMessageCellIdentifier @"SystemMessageReuseIdentifier"
#define kFileMessageCellIdentifier @"FileMessageReuseIdentifier"
#define kBroadcastMessageCellIdentifier @"BroadcastMessageReuseIdentifier"

#define kActionSheetTagUrl 0
#define kActionSheetTagImage 1

@interface ChattingTableViewController ()<UITableViewDataSource, UITableViewDelegate, ChatMessageInputViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate, FileLinkTableViewCellDelegate, UIActionSheetDelegate>
@end

@implementation ChattingTableViewController {
    NSLayoutConstraint *bottomMargin;
    NSMutableArray *messageArray;
    
    MessageTableViewCell *messageSizingTableViewCell;
    FileLinkTableViewCell *fileLinkSizingTableViewCell;
    SystemMessageTableViewCell *systemMessageSizingTableViewCell;
    FileMessageTableViewCell *fileMessageSizingTableViewCell;
    BroadcastMessageTableViewCell *broadcastMessageSizingTableViewCell;
    
    NSMutableArray *imageCache;
    NSMutableDictionary *cellHeight;
    
    BOOL scrolling;
    BOOL pastMessageLoading;
    
    BOOL endDragging;
    
    int viewMode;
    
    void (^updateMessageTs)(JiverMessageModel *model);
    
    long long mMaxMessageTs;
    long long mMinMessageTs;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (id) init
{
    self = [super init];
    if (self != nil) {
        viewMode = kChattingViewMode;
        [self clearMessageTss];
    }
    return self;
}

- (void) clearMessageTss
{
    mMaxMessageTs = LLONG_MIN;
    mMinMessageTs = LLONG_MAX;
}

- (void)viewWillAppear:(BOOL)animated
{
//    NSNumber *value = [NSNumber numberWithInt:UIInterfaceOrientationLandscapeLeft];
//    [[UIDevice currentDevice] setValue:value forKey:@"orientation"];
    
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
    [[self navigationController] setNavigationBarHidden:NO animated:NO];
    [[[self navigationController] navigationBar] setBarTintColor:UIColorFromRGB(0x824096)];
    [[[self navigationController] navigationBar] setTranslucent:NO];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"_btn_setting"] style:UIBarButtonItemStylePlain target:self action:@selector(aboutJiver:)];
    [self.navigationItem.rightBarButtonItem setTintColor:[UIColor whiteColor]];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"_btn_close"] style:UIBarButtonItemStylePlain target:self action:@selector(dismissModal:)];
    [self.navigationItem.leftBarButtonItem setTintColor:[UIColor whiteColor]];
}

- (void) dismissModal:(id)sender
{
    [self dismissViewControllerAnimated:NO completion:nil];
}

- (void) aboutJiver:(id)sender
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"JIVER" message:JIVER_IN_APP_VER delegate:nil cancelButtonTitle:@"Close" otherButtonTitles:nil];
    [alert show];
}

- (void) setViewMode:(int)mode
{
    viewMode = mode;
}

- (void) initChannelTitle
{
    [self.titleLabel setText:@"Loading"];
}

- (void) updateChannelTitle
{
    [self.titleLabel setText:[NSString stringWithFormat:@"#%@", [JiverUtils getChannelNameFromUrl:self.channelUrl]]];
}

- (void)viewDidLoad {
    updateMessageTs = ^(JiverMessageModel *model) {
        if (![model hasMessageId]) {
            return;
        }
        
        mMaxMessageTs = mMaxMessageTs < [model getMessageTimestamp] ? [model getMessageTimestamp] : mMaxMessageTs;
        mMinMessageTs = mMinMessageTs > [model getMessageTimestamp] ? [model getMessageTimestamp] : mMinMessageTs;
    };
    
    [super viewDidLoad];
    [ImageCache initImageCache];
    [[[Jiver sharedInstance] taskQueue] cancelAllOperations];
    
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
    [self.titleLabel setText:[self title]];
    [self.titleLabel sizeThatFits:CGSizeMake(200, 44)];
    [self.titleLabel setFont:[UIFont boldSystemFontOfSize:17.0]];
    [self.titleLabel setTextColor:[UIColor whiteColor]];
    [self.titleLabel setTextAlignment:NSTextAlignmentCenter];
    
    self.navigationItem.titleView = self.titleLabel;
    
    imageCache = [[NSMutableArray alloc] init];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    self.openImagePicker = NO;
    [self initViews];
    [self.channelListTableView viewDidLoad];
    
    if (viewMode == kChattingViewMode) {
        [self startChatting];
    }
    else if (viewMode == kChannelListViewMode) {
        [self clickChannelListButton];
    }
}

- (void)setIndicatorHidden:(BOOL)hidden
{
    [self.indicatorView setHidden:hidden];
}

- (void) startChatting
{
    NSLog(@"startChatting.");
    scrolling = NO;
    pastMessageLoading = YES;
    endDragging = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        pastMessageLoading = NO;
    });
    cellHeight = [[NSMutableDictionary alloc] init];
    [self initChannelTitle];
    if (messageArray != nil) {
        [messageArray removeAllObjects];
    }
    else {
        messageArray = [[NSMutableArray alloc] init];
    }
    [self.tableView reloadData];
    
    [Jiver loginWithUserId:self.userId andUserName:self.userName];
    if (viewMode == kChattingViewMode) {
        [Jiver joinChannel:self.channelUrl];
    }
    [Jiver setEventHandlerConnectBlock:^(JiverChannel *channel) {
        [self setIndicatorHidden:YES];
        [self.messageInputView setInputEnable:YES];
    } errorBlock:^(NSInteger code) {
        [self updateChannelTitle];
        [self setIndicatorHidden:YES];
    } channelLeftBlock:^(JiverChannel *channel) {
        
    } messageReceivedBlock:^(JiverMessage *message) {
        [self updateChannelTitle];
        [messageArray addJiverMessage:message updateMessageTsBlock:updateMessageTs];
        [self setIndicatorHidden:YES];
    } systemMessageReceivedBlock:^(JiverSystemMessage *message) {
        [self updateChannelTitle];
        [messageArray addJiverMessage:message updateMessageTsBlock:updateMessageTs];
        [self scrollToBottomWithReloading:YES force:NO animated:NO];
        [self setIndicatorHidden:YES];
    } broadcastMessageReceivedBlock:^(JiverBroadcastMessage *message) {
        [self updateChannelTitle];
        [messageArray addJiverMessage:message updateMessageTsBlock:updateMessageTs];
        [self scrollToBottomWithReloading:YES force:NO animated:NO];
        [self setIndicatorHidden:YES];
    } fileReceivedBlock:^(JiverFileLink *fileLink) {
        [self updateChannelTitle];
        [messageArray addJiverMessage:fileLink updateMessageTsBlock:updateMessageTs];
        [self scrollToBottomWithReloading:YES force:NO animated:NO];
        [self setIndicatorHidden:YES];
    } messagingStartedBlock:^(JiverMessagingChannel *channel) {
        
    } messagingUpdatedBlock:^(JiverMessagingChannel *channel) {
        
    } messagingEndedBlock:^(JiverMessagingChannel *channel) {
        
    } allMessagingEndedBlock:^ {
        
    } messagingHiddenBlock:^(JiverMessagingChannel *channel) {
        
    } allMessagingHiddenBlock:^ {
        
    } readReceivedBlock:^(JiverReadStatus *status) {
        
    } typeStartReceivedBlock:^(JiverTypeStatus *status) {
        
    } typeEndReceivedBlock:^(JiverTypeStatus *status) {
        
    } allDataReceivedBlock:^(NSUInteger jiverDataType, int count) {
        [self scrollToBottomWithReloading:YES force:NO animated:NO];
    } messageDeliveryBlock:^(BOOL send, NSString *message, NSString *data, NSString *messageId) {
        if (send == NO && [self.messageInputView isInputEnable]) {
            [[self.messageInputView messageTextField] setText:message];
            [self.messageInputView showSendButton];
        }
        else {
            [[self.messageInputView messageTextField] setText:@""];
            [self.messageInputView hideSendButton];
        }
    }];
    
    if (viewMode == kChattingViewMode) {
        [[Jiver queryMessageListInChannel:[Jiver getChannelUrl]] prevWithMessageTs:LLONG_MAX andLimit:50 resultBlock:^(NSMutableArray *queryResult) {
            mMaxMessageTs = LLONG_MIN;
            for (JiverMessageModel *model in queryResult) {
                [messageArray addJiverMessage:model updateMessageTsBlock:updateMessageTs];
                if (mMaxMessageTs < [model getMessageTimestamp]) {
                    mMaxMessageTs = [model getMessageTimestamp];
                }
            }
            [self.tableView reloadData];
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:([messageArray count] - 1) inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
            [Jiver connectWithMessageTs:mMaxMessageTs];
        } endBlock:^(NSError *error) {
            
        }];
    }
}

- (void)scrollToBottomWithReloading:(BOOL)reload force:(BOOL)force animated:(BOOL)animated
{
    if (reload) {
        [self.tableView reloadData];
    }
    
    if (scrolling) {
        return;
    }
    
    if (pastMessageLoading || [self isScrollBottom] || force) {
        unsigned long msgCount = [messageArray count];
        if (msgCount > 0) {
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(msgCount - 1) inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:animated];
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[self navigationController] setNavigationBarHidden:YES animated:NO];
    if (!self.openImagePicker) {
        [Jiver disconnect];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) initViews
{
    [self.view setBackgroundColor:[UIColor clearColor]];
    [self.view setOpaque:NO];
    
    self.tableView = [[UITableView alloc] init];
    [self.tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.tableView setDelegate:self];
    [self.tableView setDataSource:self];
    [self.tableView setSeparatorColor:[UIColor clearColor]];
    [self.tableView setBackgroundColor:UIColorFromRGB(0xf0f1f2)];
    [self.tableView setContentInset:UIEdgeInsetsMake(6,0,6,0)];
    [self.tableView setBounces:NO];
    
    [self.tableView registerClass:[MessageTableViewCell class] forCellReuseIdentifier:kMessageCellIdentifier];
    [self.tableView registerClass:[SystemMessageTableViewCell class] forCellReuseIdentifier:kSystemMessageCellIdentifier];
    [self.tableView registerClass:[FileLinkTableViewCell class] forCellReuseIdentifier:kFileLinkCellIdentifier];
    [self.tableView registerClass:[FileMessageTableViewCell class] forCellReuseIdentifier:kFileMessageCellIdentifier];
    [self.tableView registerClass:[BroadcastMessageTableViewCell class] forCellReuseIdentifier:kBroadcastMessageCellIdentifier];
    [self.view addSubview:self.tableView];
    
    messageSizingTableViewCell = [[MessageTableViewCell alloc] initWithFrame:self.view.frame];
    [messageSizingTableViewCell setTranslatesAutoresizingMaskIntoConstraints:NO];
    [messageSizingTableViewCell setHidden:YES];
    [self.view addSubview:messageSizingTableViewCell];
    
    fileLinkSizingTableViewCell = [[FileLinkTableViewCell alloc] initWithFrame:self.view.frame];
    [fileLinkSizingTableViewCell setTranslatesAutoresizingMaskIntoConstraints:NO];
    [fileLinkSizingTableViewCell setHidden:YES];
    [self.view addSubview:fileLinkSizingTableViewCell];
    
    fileMessageSizingTableViewCell = [[FileMessageTableViewCell alloc] initWithFrame:self.view.frame];
    [fileMessageSizingTableViewCell setTranslatesAutoresizingMaskIntoConstraints:NO];
    [fileMessageSizingTableViewCell setHidden:YES];
    [self.view addSubview:fileMessageSizingTableViewCell];
    
    broadcastMessageSizingTableViewCell = [[BroadcastMessageTableViewCell alloc] initWithFrame:self.view.frame];
    [broadcastMessageSizingTableViewCell setTranslatesAutoresizingMaskIntoConstraints:NO];
    [broadcastMessageSizingTableViewCell setHidden:YES];
    [self.view addSubview:broadcastMessageSizingTableViewCell];
    
    self.messageInputView = [[ChatMessageInputView alloc] init];
    [self.messageInputView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.messageInputView setDelegate:self];
    [self.view addSubview:self.messageInputView];
    
    self.channelListTableView = [[ChannelListTableView alloc] init];
    [self.channelListTableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.view addSubview:self.channelListTableView];
    [self.channelListTableView setHidden:YES];
    [self.channelListTableView setChattingTableViewController:self];
    
    self.indicatorView = [[IndicatorView alloc] init];
    [self.indicatorView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.view addSubview:self.indicatorView];
    [self.indicatorView setHidden:YES];
    
    [self applyConstraints];
}

- (void) applyConstraints
{
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.tableView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.tableView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.tableView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.tableView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.messageInputView attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.messageInputView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.messageInputView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    bottomMargin = [NSLayoutConstraint constraintWithItem:self.messageInputView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1 constant:0];
    [self.view addConstraint:bottomMargin];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.messageInputView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:44]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.channelListTableView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.channelListTableView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.messageInputView attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.channelListTableView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.channelListTableView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.indicatorView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.indicatorView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.indicatorView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.indicatorView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
}

- (void)keyboardWillShow:(NSNotification*)notif
{
    NSDictionary *keyboardInfo = [notif userInfo];
    NSValue *keyboardFrameEnd = [keyboardInfo valueForKey:UIKeyboardFrameEndUserInfoKey];
    CGRect keyboardFrameEndRect = [keyboardFrameEnd CGRectValue];
    [bottomMargin setConstant:-keyboardFrameEndRect.size.height];
    [self.view updateConstraints];
    
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self scrollToBottomWithReloading:NO force:NO animated:NO];
    });
}

- (void)keyboardWillHide:(NSNotification*)notification
{
    [bottomMargin setConstant:0];
    [self.view updateConstraints];
    [self scrollToBottomWithReloading:NO force:NO animated:NO];
}

- (void) clearPreviousChatting
{
    [messageArray removeAllObjects];
    [self.tableView reloadData];
    scrolling = NO;
    pastMessageLoading = YES;
    endDragging = NO;
}


#pragma mark - UIScrollViewDelegate
-(void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    scrolling = YES;
}

-(void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset
{
    scrolling = NO;
}

- (BOOL)isScrollBottom
{
    CGPoint offset = self.tableView.contentOffset;
    CGRect bounds = self.tableView.bounds;
    CGSize size = self.tableView.contentSize;
    UIEdgeInsets inset = self.tableView.contentInset;
    float y = offset.y + bounds.size.height - inset.bottom;
    float h = size.height;
    
    if (y >= (h-160)) {
        return YES;
    }
    return NO;
}

- (void) didTapOnTableView:(id)sender
{
    [self.messageInputView hideKeyboard];
}

- (void) scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (scrollView.contentOffset.y < 0 && endDragging == YES) {
        [[Jiver queryMessageListInChannel:[Jiver getChannelUrl]] prevWithMessageTs:mMinMessageTs andLimit:30 resultBlock:^(NSMutableArray *queryResult) {
            for (JiverMessageModel *model in queryResult) {
                [messageArray addJiverMessage:model updateMessageTsBlock:updateMessageTs];
            }
            [self.tableView reloadData];
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:([queryResult count] - 1) inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        } endBlock:^(NSError *error) {
            
        }];
        endDragging = NO;
    }
}

- (void) scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    endDragging = YES;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [messageArray count];
}

#pragma mark - UITableViewDelegate

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverMessage class]]) {
        cell = [tableView dequeueReusableCellWithIdentifier:kMessageCellIdentifier];
    }
    else if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverFileLink class]]) {
        cell = [tableView dequeueReusableCellWithIdentifier:kFileLinkCellIdentifier];
    }
    else if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverBroadcastMessage class]]) {
        cell = [tableView dequeueReusableCellWithIdentifier:kBroadcastMessageCellIdentifier];
    }
    else {
        cell = [tableView dequeueReusableCellWithIdentifier:kSystemMessageCellIdentifier];
    }
    
    if (cell == nil) {
        if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverMessage class]]) {
            cell = [[MessageTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kMessageCellIdentifier];
        }
        else if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverFileLink class]]) {
            JiverFileLink *fileLink = [messageArray objectAtIndex:indexPath.row];
            if ([[[fileLink fileInfo] type] hasPrefix:@"image"]) {
                cell = [[FileLinkTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kFileLinkCellIdentifier];
                
            }
            else {
                cell = [[FileMessageTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kFileMessageCellIdentifier];
            }
        }
        else if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverBroadcastMessage class]]){
            cell = [[BroadcastMessageTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kBroadcastMessageCellIdentifier];
        }
        else {
            cell = [[SystemMessageTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kSystemMessageCellIdentifier];
        }
    }
    else {
        if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverMessage class]]) {
            [(MessageTableViewCell *)cell setModel:[messageArray objectAtIndex:indexPath.row]];
        }
        else if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverFileLink class]]) {
            JiverFileLink *fileLink = [messageArray objectAtIndex:indexPath.row];
            if ([[[fileLink fileInfo] type] hasPrefix:@"image"]) {
                cell = [[FileLinkTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kFileLinkCellIdentifier];
            }
            else {
                cell = [[FileMessageTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kFileMessageCellIdentifier];
            }
            [(FileMessageTableViewCell *)cell setModel:fileLink];
        }
        else if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverBroadcastMessage class]]){
            [(BroadcastMessageTableViewCell *)cell setModel:[messageArray objectAtIndex:indexPath.row]];
        }
        else {
            [(SystemMessageTableViewCell *)cell setModel:[messageArray objectAtIndex:indexPath.row]];
        }
    }
    [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
    if ([cell isKindOfClass:[FileLinkTableViewCell class]]) {
        [(FileLinkTableViewCell *)cell setDelegate:self];
    }
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat calculatedHeight;
    if ([cellHeight objectForKey:[NSNumber numberWithFloat:indexPath.row]] != nil && [[cellHeight objectForKey:[NSNumber numberWithFloat:indexPath.row]] floatValue] > 0) {
        long long ts = 0;
        if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverMessage class]]) {
            ts = [(JiverMessage *)[messageArray objectAtIndex:indexPath.row] getMessageTimestamp];
        }
        else if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverBroadcastMessage class]]) {
            ts = [(JiverBroadcastMessage *)[messageArray objectAtIndex:indexPath.row] getMessageTimestamp];
        }
        else if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverFileLink class]]) {
            ts = [(JiverFileLink *)[messageArray objectAtIndex:indexPath.row] getMessageTimestamp];
        }
        
        calculatedHeight = [[cellHeight objectForKey:[NSNumber numberWithLongLong:ts]] floatValue];
    }
    else {
        long long ts = 0;
        if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverMessage class]]) {
            [messageSizingTableViewCell setModel:[messageArray objectAtIndex:indexPath.row]];
            calculatedHeight = [messageSizingTableViewCell getHeightOfViewCell:self.view.frame.size.width];
            ts = [(JiverMessage *)[messageArray objectAtIndex:indexPath.row] getMessageTimestamp];
        }
        else if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverBroadcastMessage class]]) {
            [broadcastMessageSizingTableViewCell setModel:(JiverBroadcastMessage *)[messageArray objectAtIndex:indexPath.row]];
            calculatedHeight = [broadcastMessageSizingTableViewCell getHeightOfViewCell:self.view.frame.size.width];
            ts = [(JiverBroadcastMessage *)[messageArray objectAtIndex:indexPath.row] getMessageTimestamp];
        }
        else if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverFileLink class]]) {
            JiverFileLink *fileLink = [messageArray objectAtIndex:indexPath.row];
            if ([[[fileLink fileInfo] type] hasPrefix:@"image"]) {
                [fileLinkSizingTableViewCell setModel:fileLink];
                calculatedHeight = [fileLinkSizingTableViewCell getHeightOfViewCell:self.view.frame.size.width];
            }
            else {
                [fileMessageSizingTableViewCell setModel:fileLink];
                calculatedHeight = [fileMessageSizingTableViewCell getHeightOfViewCell:self.view.frame.size.width];
            }
            ts = [(JiverFileLink *)[messageArray objectAtIndex:indexPath.row] getMessageTimestamp];
        }
        else {
            calculatedHeight = 32;
        }
        [cellHeight setObject:[NSNumber numberWithFloat:calculatedHeight] forKey:[NSNumber numberWithLongLong:ts]];
    }
    
    return calculatedHeight;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.messageInputView hideKeyboard];
    
    if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverMessage class]]) {
        JiverMessage *message = [messageArray objectAtIndex:indexPath.row];
        NSString *msgString = [message message];
        NSString *url = [JiverUtils getUrlFromString:msgString];
        if ([url length] > 0) {
            [self clickURL:[NSURL URLWithString:url]];
        }
    }
    else if ([[messageArray objectAtIndex:indexPath.row] isKindOfClass:[JiverFileLink class]]) {
        JiverFileLink *fileLink = [messageArray objectAtIndex:indexPath.row];
        if ([[[fileLink fileInfo] type] hasPrefix:@"image"]) {
            [self clickImage:[NSURL URLWithString:[[fileLink fileInfo] url]]];
        }
    }
}

- (void) clickURL:(NSURL *)url
{
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:[url absoluteString]
                                                             delegate:self
                                                    cancelButtonTitle:@"Cancel"
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:@"Open Link in Safari", nil];
    [actionSheet setTag:kActionSheetTagUrl];
    [actionSheet showInView:self.view];
}

- (void) clickImage:(NSURL *)url
{
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:[url absoluteString]
                                                             delegate:self
                                                    cancelButtonTitle:@"Cancel"
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:@"See Image in Safari", nil];
    [actionSheet setTag:kActionSheetTagImage];
    [actionSheet showInView:self.view];
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if(actionSheet.tag == kActionSheetTagUrl || actionSheet.tag == kActionSheetTagImage)
    {
        if (buttonIndex == actionSheet.cancelButtonIndex) {
            return;
        }
        
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:actionSheet.title]];
    }
}

#pragma mark - ChatMessageInputViewDelegate
- (void) clickSendButton:(NSString *)message
{
    [self scrollToBottomWithReloading:YES force:YES animated:NO];
    if ([message length] > 0) {
        NSString *messageId = [[NSUUID UUID] UUIDString];
        [Jiver sendMessage:message withTempId:messageId];
    }
}

- (void) clickFileAttachButton
{
    UIImagePickerController *mediaUI = [[UIImagePickerController alloc] init];
    mediaUI.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    NSMutableArray *mediaTypes = [[NSMutableArray alloc] initWithObjects:(NSString *)kUTTypeMovie, (NSString *)kUTTypeImage, nil];
    mediaUI.mediaTypes = mediaTypes;
    [mediaUI setDelegate:self];
    self.openImagePicker = YES;
    [self presentViewController:mediaUI animated:YES completion:nil];
}

- (void) clickChannelListButton
{
    [self clearPreviousChatting];
    if ([self.channelListTableView isHidden]) {
        [self.channelListTableView setHidden:NO];
        [self.channelListTableView reloadChannels];
        [self.messageInputView setInputEnable:NO];
        [Jiver disconnect];
    }
    else {
        [self.channelListTableView setHidden:YES];
        [self.messageInputView setInputEnable:YES];
        [Jiver connect];
    }
}

#pragma mark - UIImagePickerControllerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    __block NSString *mediaType = [info objectForKey: UIImagePickerControllerMediaType];
    __block UIImage *originalImage, *editedImage, *imageToUse;
    __block NSURL *imagePath;
    __block NSString *imageName;
    
    [self setIndicatorHidden:NO];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (CFStringCompare ((CFStringRef) mediaType, kUTTypeImage, 0) == kCFCompareEqualTo) {
            editedImage = (UIImage *) [info objectForKey:
                                       UIImagePickerControllerEditedImage];
            originalImage = (UIImage *) [info objectForKey:
                                         UIImagePickerControllerOriginalImage];
            
            if (originalImage) {
                imageToUse = originalImage;
            } else {
                imageToUse = editedImage;
            }
            
            NSData *imageFileData = UIImagePNGRepresentation(imageToUse);
            imagePath = [info objectForKey:@"UIImagePickerControllerReferenceURL"];
            imageName = [imagePath lastPathComponent];
            
            [Jiver uploadFile:imageFileData type:@"image/jpg" hasSizeOfFile:[imageFileData length] withCustomField:@"" uploadBlock:^(JiverFileInfo *fileInfo, NSError *error) {
                self.openImagePicker = NO;
                [Jiver sendFile:fileInfo];
                [self setIndicatorHidden:YES];
            }];
        }
        else if (CFStringCompare ((CFStringRef) mediaType, kUTTypeVideo, 0) == kCFCompareEqualTo) {
            NSURL *videoURL = [info objectForKey:UIImagePickerControllerMediaURL];
            
            NSData *videoFileData = [NSData dataWithContentsOfURL:videoURL];
            
            [Jiver uploadFile:videoFileData type:@"video/mov" hasSizeOfFile:[videoFileData length] withCustomField:@"" uploadBlock:^(JiverFileInfo *fileInfo, NSError *error) {
                self.openImagePicker = NO;
                [Jiver sendFile:fileInfo];
                [self setIndicatorHidden:YES];
            }];
        }
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:^{
        self.openImagePicker = NO;
    }];
}

#pragma mark - UITextFieldDelegate
- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self scrollToBottomWithReloading:YES force:YES animated:NO];
    NSString *message = [textField text];
    if ([message length] > 0) {
        [textField setText:@""];
        NSString *messageId = [[NSUUID UUID] UUIDString];
        [Jiver sendMessage:message withTempId:messageId];
    }
    
    return YES;
}

#pragma mark - FileLinkTableViewCellDelegate
- (void)reloadCell:(NSIndexPath *)indexPath
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    [array addObject:indexPath];
    [self.tableView reloadRowsAtIndexPaths:array withRowAnimation:UITableViewRowAnimationNone];
}


@end