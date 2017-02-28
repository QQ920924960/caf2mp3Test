//
//  FKRecorder.m
//  caf2mp3Test
//
//  Created by QQ920924960 on 2017/2/28.
//  Copyright © 2017年 zmosa. All rights reserved.
//

#import "FKRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import "lame.h"

// 采样率
typedef NS_ENUM(NSInteger, AudioSample) {
    AudioSampleRateLow = 8000,
    AudioSampleRateMedium = 44100, //音频CD采样率
    AudioSampleRateHigh = 96000
};

@interface FKRecorder ()

{
    BOOL isStopRecording;
}
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) AVAudioSession *audioSession;
@property (nonatomic, strong) NSMutableDictionary *settings;
@property (nonatomic, strong) NSString *originalDataPath;
@property (nonatomic, strong) NSString *mp3DataPath;

@end

@implementation FKRecorder

static inline NSString* GetAudioDirectoryPathWithAudioName(NSString *audioName) {
    NSString *path = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).lastObject;
    NSString *directoryPath = [path stringByAppendingPathComponent:@"com.zmosa.audio"];
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isCreateSuccess = [manager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    if (isCreateSuccess) return [directoryPath stringByAppendingPathComponent:audioName];
    return nil;
}

- (NSString *)originalDataPath {
    if (!_originalDataPath) {
        _originalDataPath = GetAudioDirectoryPathWithAudioName(@"originalAudio");
    }
    return _originalDataPath;
}

- (NSString *)mp3DataPath {
    if (!_mp3DataPath) {
        _mp3DataPath = GetAudioDirectoryPathWithAudioName(@"translatedAudio.mp3");
    }
    return _mp3DataPath;
}

+ (FKRecorder *)sharedRecorder {
    static FKRecorder *recorder = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        recorder = [[self alloc] init];
        [recorder configureSession];
        [recorder configureRecorder];
    });
    return recorder;
}

- (void)configureSession {
    _audioSession = [AVAudioSession sharedInstance];
    [_audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [_audioSession setActive:YES error:nil];
    [_audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
}

- (void)configureRecorder {
    _settings = [NSMutableDictionary dictionary];
    [_settings setObject:@(kAudioFormatLinearPCM) forKey:AVFormatIDKey];
    [_settings setObject:@(AudioSampleRateMedium) forKey:AVSampleRateKey];
    [_settings setObject:@(2) forKey:AVNumberOfChannelsKey]; //双声道
    [_settings setValue:@(16) forKey:AVLinearPCMBitDepthKey];
    [_settings setObject:@(AVAudioQualityHigh) forKey:AVEncoderAudioQualityKey];
}

+ (void)fk_starRecordingWithAutoTranscoding:(BOOL)autoTranscoding {
    NSError *error = nil;
    FKRecorder *_self = [FKRecorder sharedRecorder];
    _self.recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:_self.originalDataPath] settings:_self.settings error:&error];
    _self.recorder.meteringEnabled = YES;
    [_self.recorder prepareToRecord];
    BOOL isRecordSuccess = [_self.recorder record];
    if (isRecordSuccess) {
        NSString *textValue = [NSString stringWithFormat:@"开始录音：%@", _self.originalDataPath];
        NSLog(@"%@", textValue);
        [_self changeRecordState:FKRecorderStateBegin];
        if (autoTranscoding) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [_self transcodingWhileRecording];
            });
        }
    }
    else {
        NSLog(@"录音失败：%@", error);
        [_self changeRecordState:FKRecorderStateFailure];
    }
}

+ (void)fk_stopRecording {
    FKRecorder *_self = [FKRecorder sharedRecorder];
    [_self.recorder stop];
    _self.recorder = nil;
    _self->isStopRecording = YES;
    [_self changeRecordState:FKRecorderStateEnd];
}

+ (void)fk_transcodingToMP3 {
    [[FKRecorder sharedRecorder] startTranscoding];
}

// 边录边转码(要在子线中进行)
- (void)transcodingWhileRecording {
    @try {
        int read, write;
        // source
        FILE *pcm = fopen([self.originalDataPath cStringUsingEncoding:1], "rb");
        //skip file header
        fseek(pcm, 4*1024, SEEK_CUR);
        //output
        FILE *mp3 = fopen([self.mp3DataPath cStringUsingEncoding:1], "wb");
        
        const int PCM_SIZE = 8192;
        const int MP3_SIZE = 8192;
        short int pcm_buffer[PCM_SIZE*2];
        unsigned char mp3_buffer[MP3_SIZE];
        
        lame_t lame = lame_init();
        lame_set_in_samplerate(lame, AudioSampleRateMedium);
        lame_set_VBR(lame, vbr_default);
        lame_init_params(lame);
        
        long currentPosition;
        do {
            currentPosition = ftell(pcm);     //文件读到当前位置
            long startPosition = ftell(pcm);  //起始点
            fseek(pcm, 0, SEEK_END);          //将文件指针指向结束位置,为了获取结束点
            long endPosition = ftell(pcm);    //结束点
            long length = endPosition - startPosition; //获得文件长度
            fseek(pcm, currentPosition, SEEK_SET);//再将文件指针复位
            
            if (length > PCM_SIZE * 2 * sizeof(short int)) {
                read = (int)fread(pcm_buffer, 2*sizeof(short int), PCM_SIZE, pcm);
                if (read == 0) write = lame_encode_flush(lame, mp3_buffer, MP3_SIZE);
                else write = lame_encode_buffer_interleaved(lame, pcm_buffer, read, mp3_buffer, MP3_SIZE);
                fwrite(mp3_buffer, write, 1, mp3);
                NSLog(@"转码中...");
            }
            else {
                //让当前线程睡眠一小会,等待音频数据增加时,再继续转码
                [NSThread sleepForTimeInterval:0.02];
                NSLog(@"等待中...");
            }
            
        } while (!isStopRecording);
        
        lame_close(lame);
        fclose(mp3);
        fclose(pcm);
        
    }
    @catch (NSException *exception) {
        NSLog(@"%@",[exception description]);
    }
    @finally {
        NSString *textValue = [NSString stringWithFormat:@"转换成功：%@", self.mp3DataPath];
        NSLog(@"%@", textValue);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self excuteFinished];
        });
    }
    
}


// 录音结束后一次性转码
- (void)startTranscoding {
    @try {
        int read, write;
        
        // source
        FILE *pcm = fopen([self.originalDataPath cStringUsingEncoding:1], "rb");
        // skip file header
        fseek(pcm, 4*1024, SEEK_CUR);
        // output
        FILE *mp3 = fopen([self.mp3DataPath cStringUsingEncoding:1], "wb");
        
        const int PCM_SIZE = 8192;
        const int MP3_SIZE = 8192;
        short int pcm_buffer[PCM_SIZE*2];
        unsigned char mp3_buffer[MP3_SIZE];
        
        lame_t lame = lame_init();
        lame_set_in_samplerate(lame, AudioSampleRateMedium);
        lame_set_VBR(lame, vbr_default);
        lame_init_params(lame);
        
        do {
            read = (int)fread(pcm_buffer, 2*sizeof(short int), PCM_SIZE, pcm);
            if (read == 0)
                write = lame_encode_flush(lame, mp3_buffer, MP3_SIZE);
            else
                write = lame_encode_buffer_interleaved(lame, pcm_buffer, read, mp3_buffer, MP3_SIZE);
            
            fwrite(mp3_buffer, write, 1, mp3);
            
        } while (read != 0);
        
        lame_close(lame);
        fclose(mp3);
        fclose(pcm);
    }
    @catch (NSException *exception) {
        NSLog(@"%@",[exception description]);
    }
    @finally {
        NSString *textValue = [NSString stringWithFormat:@"转换成功：%@", self.mp3DataPath];
        NSLog(@"%@", textValue);
        [self excuteFinished];
    }
}

- (void)changeRecordState:(FKRecorderState)state
{
    if ([self.delegate respondsToSelector:@selector(recorderStateDidChange:state:)]) {
        [self.delegate recorderStateDidChange:self state:state];
    }
}

- (void)excuteFinished
{
    if ([self.delegate respondsToSelector:@selector(recorderDidFinishedConvert:)]) {
        [self.delegate recorderDidFinishedConvert:self];
    }
}

@end
