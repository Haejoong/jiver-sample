//
//  FileLinkTableViewCell.h
//  JiveriOSSample
//
//  Created by Jed Kyung on 2015. 7. 29..
//  Copyright (c) 2015년 JIVER.CO. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <JiverSDK/JiverSDK.h>
#import "JiverCommon.h"

@protocol FileLinkTableViewCellDelegate

- (void) reloadCell:(NSIndexPath *)indexPath;

@end

@interface FileLinkTableViewCell : UITableViewCell

@property (retain) JiverFileLink *fileLink;
@property (retain) UILabel *messageLabel;
@property (retain) UIImageView *fileImageView;
@property (retain) UILabel *filenameLabel;
@property (retain) UILabel *filesizeLabel;
@property (retain) UIView *leftBarView;
@property (retain) id<FileLinkTableViewCellDelegate> delegate;

- (void) setModel:(JiverFileLink *)model;
- (CGFloat)getHeightOfViewCell:(CGFloat)totalWidth;

@end
