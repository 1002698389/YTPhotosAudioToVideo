//
//  YIVideoGenerateTool.m
//  YTPhotosAudioToVideo
//
//  Created by Geson on 2017/6/26.
//  Copyright © 2017年 yetaiwen. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^completeConvertVideo)();

@interface YIVideoGenerateTool : NSObject
-(instancetype)initWithImages:(NSArray*)images completionHander:(completeConvertVideo)completion;
-(void)createVideoFromGivenImageArr;
-(void)addAudioToVideo:(NSString *)audioPath completed:(completeConvertVideo)completeBlock;
-(void)copyMuteVideoToFile:(completeConvertVideo)completeBlock;
@end
