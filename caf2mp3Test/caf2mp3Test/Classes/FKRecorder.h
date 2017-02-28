//
//  FKRecorder.h
//  caf2mp3Test
//
//  Created by QQ920924960 on 2017/2/28.
//  Copyright © 2017年 zmosa. All rights reserved.
//

#import <Foundation/Foundation.h>
@class FKRecorder;
typedef NS_ENUM(NSInteger, FKRecorderState) {
    FKRecorderStateBegin = 0,
    FKRecorderStateRecoding,
    FKRecorderStateFailure,
    FKRecorderStateEnd,
};

@protocol FKRecorderDelegate <NSObject>

- (void)recorderStateDidChange:(FKRecorder *)recorder state:(FKRecorderState)state;
- (void)recorderDidFinishedConvert:(FKRecorder *)recorder;

@end

@interface FKRecorder : NSObject

@property (nonatomic, weak) id<FKRecorderDelegate> delegate;

+ (FKRecorder *)sharedRecorder;

//开始录音, autoTranscoding 设置为YES则边录边转码
+ (void)fk_starRecordingWithAutoTranscoding:(BOOL)autoTranscoding;

+ (void)fk_stopRecording;

//录音结束后, 一次性转码
+ (void)fk_transcodingToMP3;

@end
