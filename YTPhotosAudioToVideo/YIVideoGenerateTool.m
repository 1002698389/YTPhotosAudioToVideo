//
//  YIVideoGenerateTool.m
//  YTPhotosAudioToVideo
//
//  Created by Geson on 2017/6/26.
//  Copyright © 2017年 yetaiwen. All rights reserved.
//

#import "YIVideoGenerateTool.h"
#import <QuartzCore/CoreAnimation.h>
#import <AVFoundation/AVFoundation.h>
#import "XCHudHelper.h"
@interface YIVideoGenerateTool()
{
    NSArray *_imageArr;
    AVMutableVideoComposition *_videoComposition;
    AVMutableComposition *_mainComposition;
    AVMutableCompositionTrack *_videoTrack;
    CVPixelBufferRef _imageBufferRef;
    dispatch_queue_t _SerialQueue;
    completeConvertVideo _completeBlock;
    NSString *_finalMoviePath;
}
@end

#define ShareHud [XCHudHelper sharedInstance]
#define FlashDir [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)firstObject]stringByAppendingPathComponent:@"IFlashDevice"]
#define BacePath [FlashDir stringByAppendingPathComponent:@"IFlashSynVideos"]
#define compositionTempMov(i) [BacePath stringByAppendingPathComponent:[NSString stringWithFormat:@"compositionTemp%d.mov",i]]
#define compositionJointMov(i) [BacePath stringByAppendingPathComponent:[NSString stringWithFormat:@"compositionTotal%d.mov",i]]
#define VideoSize CGSizeMake(480, 640)
#define VideoLengh 3*fps*_imageArr.count

static const NSUInteger fps = 30;

@implementation YIVideoGenerateTool

-(instancetype)initWithImages:(NSArray *)images completionHander:(completeConvertVideo)completion
{
    if (self = [super init]) {
        _imageArr = [images copy];
        _SerialQueue = dispatch_queue_create("createVideo", DISPATCH_QUEUE_SERIAL);
        _completeBlock = completion;
    }return self;
}

-(void)createVideoFromGivenImageArr
{
    [self createSingleVideoWithImageIndex:0];
}

-(void)createSingleVideoWithImageIndex:(int)index
{
    id compositionPath = compositionTempMov(index);
    _mainComposition = [AVMutableComposition composition];
    
    _videoComposition = [AVMutableVideoComposition videoComposition];
    _videoComposition.renderSize = CGSizeMake(VideoSize.width, VideoSize.height);
    _videoComposition.frameDuration = CMTimeMake(1, fps);
    
    [[NSFileManager defaultManager]removeItemAtURL:[NSURL fileURLWithPath:compositionPath] error:nil];
    AVAssetWriter *videoWriter = [[AVAssetWriter alloc]initWithURL:[NSURL fileURLWithPath:compositionPath] fileType:AVFileTypeQuickTimeMovie error:nil];
    NSDictionary *inputSetting = [NSDictionary dictionaryWithObjectsAndKeys:AVVideoCodecH264,AVVideoCodecKey,@(VideoSize.width),AVVideoWidthKey,@(VideoSize.height),AVVideoHeightKey, nil];
    AVAssetWriterInput *writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:inputSetting];
    NSDictionary * pixelBufferAtribture = @{(__bridge NSString*)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32ARGB)};
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [[AVAssetWriterInputPixelBufferAdaptor alloc]initWithAssetWriterInput:writerInput sourcePixelBufferAttributes:pixelBufferAtribture];
    if ([videoWriter canAddInput:writerInput]) {
        [videoWriter addInput:writerInput];
    }
    [videoWriter startWriting];
    [videoWriter startSessionAtSourceTime:kCMTimeZero];
    __block NSUInteger frameCount = 0;
    
    [writerInput requestMediaDataWhenReadyOnQueue:_SerialQueue usingBlock:^{
        while([writerInput isReadyForMoreMediaData]) {
            NSLog(@"%d",index);
            if (++frameCount > 3 * fps) {
                [writerInput markAsFinished];
                [videoWriter finishWritingWithCompletionHandler:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:compositionPath]];
                        _videoTrack = [_mainComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
                        [_videoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, CMTimeMake(3 * fps, fps)) ofTrack:[asset tracksWithMediaType:AVMediaTypeVideo].firstObject atTime:kCMTimeZero error:nil];
                        
                        [self CoverVideoLayerWithAnimationLayer:[self creatFramesLayerWithImage:_imageArr[index] withAnimationMode:0 atTime:kCMTimeRangeZero]];
                        [self createVideoAtPathByVideoComposition:index];
                        
                    });
                    
                }];
            }
            break;
        }
        if (!_imageBufferRef) {
            _imageBufferRef = [self pixelBufferFromCGImage:[UIImage imageNamed:@""].CGImage size:VideoSize];
        }
        [adaptor appendPixelBuffer:_imageBufferRef withPresentationTime:CMTimeMake(frameCount, fps)];
    }];
    
}

- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image size:(CGSize)size
{
    NSDictionary *options =[NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithBool:YES],kCVPixelBufferCGImageCompatibilityKey,
                            [NSNumber numberWithBool:YES],kCVPixelBufferCGBitmapContextCompatibilityKey,nil];
    CVPixelBufferRef pxbuffer =NULL;
    CVReturn status =CVPixelBufferCreate(kCFAllocatorDefault,size.width,size.height,kCVPixelFormatType_32ARGB,(__bridge CFDictionaryRef) options,&pxbuffer);
    
    NSParameterAssert(status ==kCVReturnSuccess && pxbuffer !=NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer,0);
    void *pxdata =CVPixelBufferGetBaseAddress(pxbuffer);
    
    NSParameterAssert(pxdata !=NULL);
    
    CGColorSpaceRef rgbColorSpace=CGColorSpaceCreateDeviceRGB();
    CGContextRef context =CGBitmapContextCreate(pxdata,size.width,size.height,8,4*size.width,rgbColorSpace,kCGImageAlphaPremultipliedFirst);
    
    NSParameterAssert(context);
    
    CGContextDrawImage(context,CGRectMake((size.width-CGImageGetWidth(image))/2,(size.height-CGImageGetHeight(image))/2,CGImageGetWidth(image),CGImageGetHeight(image)), image);
    
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer,0);
    
    return pxbuffer;
    
}


-(CALayer*)creatFramesLayerWithImage:(UIImage*)image withAnimationMode:(NSUInteger)mode atTime:(CMTimeRange)time
{
    CALayer *contentLayer = [CALayer layer];
    contentLayer.frame = CGRectMake(50, 50, VideoSize.width -100, VideoSize.height -100);
    contentLayer.contents = (id)image.CGImage;
    
    CABasicAnimation *scaleAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scaleAnimation.fromValue = @0.7;
    scaleAnimation.toValue = @1.3;
    scaleAnimation.duration = 1.5;
    scaleAnimation.repeatCount = 1;
    scaleAnimation.autoreverses = YES;
    scaleAnimation.beginTime = AVCoreAnimationBeginTimeAtZero;
    [contentLayer addAnimation:scaleAnimation forKey:@"scale"];
    
    //    CABasicAnimation *opacityAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    //    opacityAnimation.fromValue = @0.8;
    //    opacityAnimation.toValue = @0.2;
    //    opacityAnimation.duration = 1.5;
    //    opacityAnimation.repeatCount = 3;
    //    opacityAnimation.beginTime = 3;
    //    [contentLayer addAnimation:opacityAnimation forKey:@"opacity"];
    
    return contentLayer;
    
}


-(void)CoverVideoLayerWithAnimationLayer:(CALayer*)animationLayer
{
    CALayer *parentLayer = [CALayer layer];
    CALayer *videoLayer = [CALayer layer];
    parentLayer.frame = CGRectMake(0, 0, VideoSize.width, VideoSize.height);
    videoLayer.frame = CGRectMake(0, 0, VideoSize.width, VideoSize.height);
    [parentLayer addSublayer:videoLayer];
    [parentLayer addSublayer:animationLayer];
    
    _videoComposition.animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer inLayer:parentLayer];
}

-(void)createVideoAtPathByVideoComposition:(int)index
{
    AVMutableVideoCompositionInstruction *videoInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    videoInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMake(3 * fps, fps));
    
    AVMutableVideoCompositionLayerInstruction *layerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:[_mainComposition tracksWithMediaType:AVMediaTypeVideo].firstObject];
    
    videoInstruction.layerInstructions = @[layerInstruction];
    _videoComposition.instructions = @[videoInstruction];
    
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]initWithAsset:_mainComposition presetName:AVAssetExportPresetHighestQuality];
    
    NSParameterAssert(exportSession);
    
    exportSession.outputURL = [NSURL fileURLWithPath:compositionJointMov(index)];
    NSLog(@"%@",compositionJointMov(index));
    exportSession.outputFileType = @"com.apple.quicktime-movie";
    exportSession.shouldOptimizeForNetworkUse = YES;
    exportSession.videoComposition = _videoComposition;
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        
        NSLog(@"完成单个视频");
        [[NSFileManager defaultManager]removeItemAtURL:[NSURL fileURLWithPath:compositionTempMov(index)] error:nil];
        int currentIndex = index + 1;
        if (currentIndex < _imageArr.count) {
            [self createSingleVideoWithImageIndex:currentIndex];
        }else{
            _videoComposition = nil;
            _mainComposition = nil;
            _videoTrack = nil;
            [self compositionTheSingleVideos];
        }
    }];
}

-(void)compositionTheSingleVideos
{
    _mainComposition = [AVMutableComposition composition];
    AVMutableCompositionTrack *compositionTrack = [_mainComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    for (int i = 0; i < _imageArr.count; i++) {
        CMTimeRange range = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(3, fps));
        
        AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:compositionJointMov(i)]];
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        
        if ([compositionTrack insertTimeRange:range ofTrack:track atTime:CMTimeMakeWithSeconds(3 * i, fps) error:nil]) {
            NSLog(@"插入成功%d",i);
        }else{
            NSLog(@"插入失败%d",i);
        }
    }
    
    AVAssetExportSession *totalSession = [[AVAssetExportSession alloc]initWithAsset:_mainComposition presetName:AVAssetExportPresetHighestQuality];
    NSDateFormatter * dateFormatter = [[NSDateFormatter alloc]init];
    [dateFormatter setDateFormat:@"yyyyMMddHHmmss"];
    NSString * videoName = [dateFormatter stringFromDate:[NSDate date]];
    NSString *path = [FlashDir stringByAppendingPathComponent:@"IFlashSynVideos"];
    NSString *moviePath =[path stringByAppendingPathComponent:[NSString stringWithFormat:@"222PV%@.mov",videoName]];
    _finalMoviePath = moviePath;
    totalSession.outputURL = [NSURL fileURLWithPath:moviePath];
    totalSession.outputFileType = @"com.apple.quicktime-movie";
    totalSession.shouldOptimizeForNetworkUse = YES;
    [totalSession exportAsynchronouslyWithCompletionHandler:^{
        for (int i = 0; i < _imageArr.count; i++) {
            [[NSFileManager defaultManager]removeItemAtURL:[NSURL fileURLWithPath:compositionJointMov(i)] error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (_completeBlock) {
                _completeBlock();
            }
        });
        
        NSLog(@"合成完毕");
    }];
    
}

- (void)addAudioToVideo:(NSString *)audioPath completed:(completeConvertVideo)completeBlock{
    [ShareHud showHudAcitivityOnWindow];
    NSDateFormatter * dateFormatter = [[NSDateFormatter alloc]init];
    [dateFormatter setDateFormat:@"yyyyMMddHHmmss"];
    NSString * videoName = [dateFormatter stringFromDate:[NSDate date]];
    NSString *path = [FlashDir stringByAppendingPathComponent:@"IFlashSynVideos"];
    NSString *moviePath =[path stringByAppendingPathComponent:[NSString stringWithFormat:@"PV%@.mov",videoName]];
    
    NSParameterAssert([[NSThread currentThread]isMainThread]);
    
    NSURL * audioUrl = [NSURL fileURLWithPath:audioPath];
    NSURL * videoUrl = [NSURL fileURLWithPath:_finalMoviePath];
    AVAsset * audioAsset = [AVAsset assetWithURL:audioUrl];
    AVAsset * videoAsset = [AVAsset assetWithURL:videoUrl];
    AVAssetTrack * audioTrack = [[audioAsset tracksWithMediaType:AVMediaTypeAudio]firstObject];
    AVAssetTrack * videoTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo]firstObject];
    
    AVMutableComposition * mixComposition = [AVMutableComposition composition];
    AVMutableCompositionTrack * audioCompositionTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    [audioCompositionTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoTrack.timeRange.duration) ofTrack:audioTrack atTime:kCMTimeZero error:nil];
    
    AVMutableCompositionTrack * videoCompositionTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    [videoCompositionTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero,videoTrack.timeRange.duration) ofTrack:videoTrack atTime:kCMTimeZero error:nil];
    
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]initWithAsset:mixComposition presetName:AVAssetExportPresetMediumQuality];
    exportSession.outputURL = [NSURL fileURLWithPath:moviePath];
    exportSession.outputFileType = @"com.apple.quicktime-movie";
    exportSession.shouldOptimizeForNetworkUse = YES;
    
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSFileManager defaultManager]removeItemAtURL:[NSURL fileURLWithPath:_finalMoviePath] error:nil];
            completeBlock();
            [ShareHud hideHud];
            [XCHudHelper showSuccess:nil];
        });
    }];
}

- (void)copyMuteVideoToFile:(completeConvertVideo)completeBlock{
    [ShareHud showHudAcitivityOnWindow];
    NSDateFormatter * dateFormatter = [[NSDateFormatter alloc]init];
    [dateFormatter setDateFormat:@"yyyyMMddHHmmss"];
    NSString * videoName = [dateFormatter stringFromDate:[NSDate date]];
    NSString *path = [FlashDir stringByAppendingPathComponent:@"IFlashSynVideos"];
    NSString *moviePath =[path stringByAppendingPathComponent:[NSString stringWithFormat:@"PV%@.mov",videoName]];
    NSLog(@"path2:%@",moviePath);
    
    [[NSFileManager defaultManager] copyItemAtPath:_finalMoviePath toPath:moviePath error:nil];
    //    completeBlock();
    [ShareHud hideHud];
    [XCHudHelper showSuccess:nil];
}
@end
