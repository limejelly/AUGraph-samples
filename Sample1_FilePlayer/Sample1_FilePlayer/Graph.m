//
//  Graph.m
//  Sample1_FilePlayer
//
//  Created by Aliksandr Andrashuk on 16.10.13.
//  Copyright (c) 2013 Aliksandr Andrashuk. All rights reserved.
//

#import "Graph.h"
#import <AssertMacros.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>

@interface Graph ()
{
    NSArray *_filePaths;
    AudioFileID *_audioFileIDs;
    SInt64 *_framesCount;
    AudioStreamBasicDescription *_asbd;
    AudioUnit _auFilePlayer;
    AudioUnit _auRemoteIO;
    AUGraph _auGraph;
    AUNode _nodeFilePlayer;
    AUNode _nodeRemoteIO;
}
@end

@implementation Graph

#pragma mark - Public methods

- (id)initWithFilePath:(NSString *)filePath {
    return [self initWithFilePaths:@[filePath]];
}

- (id)initWithFilePaths:(NSArray *)filePaths {
    self = [super init];
    __Require_Quiet(filePaths.count, fail);
    _filePaths = filePaths;
    __Require_Quiet([self setup], fail);
    return self;
fail:
    return nil;
}

- (BOOL)playFileAtIndex:(NSUInteger)index {
    return [self playFileAtIndex:index loopCount:1];
}

- (BOOL)playFileAtIndex:(NSUInteger)index
              loopCount:(NSInteger)loopCount {
    return [self playFileAtIndex:index loopCount:loopCount timeOffset:0.0];
}

- (BOOL)playFileAtIndex:(NSUInteger)index
              loopCount:(NSInteger)loopCount
             timeOffset:(NSTimeInterval)timeOffset {
    return [self playFileAtIndex:index loopCount:loopCount timeOffset:timeOffset playDuration:0];
}

- (BOOL)playFileAtIndex:(NSUInteger)index
              loopCount:(NSInteger)loopCount
             timeOffset:(NSTimeInterval)timeOffset
           playDuration:(NSTimeInterval)playDuration {
    
    __Require_Quiet(index < _filePaths.count, fail);
    __Require_Quiet(_auFilePlayer, fail);
    __Require_Quiet(timeOffset >= 0, fail);
    __Require_Quiet(playDuration >= 0, fail);
    
    AudioTimeStamp timeStamp;
    UInt32 propSize = sizeof(AudioTimeStamp);
    __Require_noErr(AudioUnitGetProperty(_auFilePlayer,
                                         kAudioUnitProperty_CurrentPlayTime,
                                         kAudioUnitScope_Global,
                                         0,
                                         &timeStamp,
                                         &propSize), fail);
    
    timeStamp.mSampleTime += 100;
    
    UInt32 framesToPlay = (UInt32)_framesCount[index];
    if (playDuration > 0) {
        framesToPlay = playDuration * _asbd[index].mSampleRate;
    }
    UInt32 startFrame = timeOffset * _asbd[index].mSampleRate;
    
    __Require_Quiet(startFrame <= _framesCount[index], fail);
    
    ScheduledAudioFileRegion region;
    memset(&region, 0, sizeof(ScheduledAudioFileRegion));
    region.mAudioFile = _audioFileIDs[index];
    region.mFramesToPlay = framesToPlay;
    region.mLoopCount = loopCount;
    region.mStartFrame = startFrame;
    region.mTimeStamp = timeStamp;
    region.mCompletionProc = NULL;
    region.mCompletionProcUserData = NULL;
    
    __Require_noErr(AudioUnitSetProperty(_auFilePlayer,
                                         kAudioUnitProperty_ScheduledFileRegion,
                                         kAudioUnitScope_Global,
                                         0,
                                         &region,
                                         sizeof(region)), fail);
    
    __Require_Quiet([self startGraph], fail);
    
    return YES;
fail:
    return NO;
}

- (BOOL)stop {
    __Require_Quiet([self stopGraph], fail);
    __Require_Quiet([self resetGraph], fail);
    return YES;
fail:
    return NO;
}

- (NSTimeInterval)durationOfFileAtIndex:(NSUInteger)index {
    __Require_Quiet(index < _filePaths.count, fail);
    return _framesCount[index] / _asbd[index].mSampleRate;
fail:
    return 0;
}

#pragma mark - Common

- (void)dealloc {
    if ([self isGraphStarted]) {
        [self stopGraph];
    }
    if ([self isGraphInited]) {
        [self uninitializeGraph];
    }
    if ([self isGraphOpened]) {
        [self closeGraph];
    }
    DisposeAUGraph(_auGraph);
    [self closeAudioFiles];
}

- (BOOL)openAudioFiles {
    _audioFileIDs = (AudioFileID *)malloc(sizeof(AudioFileID) * _filePaths.count);
    
    AudioFileID audioFile;
    NSInteger i = 0;
    for (NSString *filePath in _filePaths) {
        CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:filePath];
        __Require_noErr(AudioFileOpenURL(url, kAudioFileReadPermission, 0, &audioFile), fail);
        _audioFileIDs[i] = audioFile;
        i++;
    }
    
    return YES;
fail:
    return NO;
}

- (void)closeAudioFiles {
    for (NSInteger i=0; i<_filePaths.count; i++) {
        AudioFileID audioFile = _audioFileIDs[i];
        AudioFileClose(audioFile);
    }
    if (_audioFileIDs) {
        free(_audioFileIDs);
    }
    if (_framesCount) {
        free(_framesCount);
    }
    if (_asbd) {
        free(_asbd);
    }
}

- (BOOL)prepareAudioFilesInfo {
    _framesCount = (SInt64 *)malloc(sizeof(SInt64) * _filePaths.count);
    _asbd = (AudioStreamBasicDescription *)malloc(sizeof(AudioStreamBasicDescription) * _filePaths.count);
    
    UInt32 propertySize;
    UInt32 packetsCount;
    
    for (NSInteger i=0; i<_filePaths.count; i++) {
        AudioFileID audioFile = _audioFileIDs[i];
        
        __Require_noErr(AudioFileGetPropertyInfo(audioFile, kAudioFilePropertyAudioDataPacketCount, &propertySize, NULL), fail);
        __Require_noErr(AudioFileGetProperty(audioFile, kAudioFilePropertyAudioDataPacketCount, &propertySize, &packetsCount), fail);
        
        AudioStreamBasicDescription asbd;
        __Require_noErr(AudioFileGetPropertyInfo(audioFile, kAudioFilePropertyDataFormat, &propertySize, NULL), fail);
        __Require_noErr(AudioFileGetProperty(audioFile, kAudioFilePropertyDataFormat, &propertySize, &asbd), fail);
        
        _asbd[i] = asbd;
        _framesCount[i] = packetsCount * asbd.mFramesPerPacket;
    }
    
    UInt32 prime = 0;
    __Require_noErr(AudioUnitSetProperty(_auFilePlayer,
                                         kAudioUnitProperty_ScheduledFilePrime,
                                         kAudioUnitScope_Global,
                                         0,
                                         &prime,
                                         sizeof(prime)), fail);
    
    return YES;
fail:
    return NO;
}
- (BOOL)scheduleFiles {
    __Require_noErr(AudioUnitSetProperty(_auFilePlayer,
                                         kAudioUnitProperty_ScheduledFileIDs,
                                         kAudioUnitScope_Global,
                                         0,
                                         _audioFileIDs,
                                         sizeof(AudioFileID) * _filePaths.count), fail);
    
    return YES;
fail:
    return NO;
}

- (BOOL)adjustStartupTime {
    AudioTimeStamp startTime;
    memset (&startTime, 0, sizeof(AudioTimeStamp));
    startTime.mFlags = kAudioTimeStampSampleTimeValid;
    startTime.mSampleTime = -1;
    
    __Require_noErr(AudioUnitSetProperty(_auFilePlayer,
                                         kAudioUnitProperty_ScheduleStartTimeStamp,
                                         kAudioUnitScope_Global,
                                         0,
                                         &startTime,
                                         sizeof(AudioTimeStamp)), fail);
    
    return YES;
fail:
    return NO;
}

- (BOOL)setup {
    __Require_Quiet([self setupAUGraph], fail);
    __Require_Quiet([self setupNodes], fail);
    __Require_Quiet([self connectNodes], fail);
    __Require_Quiet([self openGraph], fail);
    __Require_Quiet([self prepareAUs], fail);
    __Require_Quiet([self initializeGraph], fail);
    __Require_Quiet([self openAudioFiles], fail);
    __Require_Quiet([self prepareAudioFilesInfo], fail);
    __Require_Quiet([self scheduleFiles], fail);
    __Require_Quiet([self adjustStartupTime], fail);
    
    return YES;
fail:
    return NO;
}

#pragma mark - AUGraph

- (BOOL)setupNodes {
    AudioComponentDescription filePlayerDescription;
    filePlayerDescription.componentFlags = 0;
    filePlayerDescription.componentFlagsMask = 0;
    filePlayerDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    filePlayerDescription.componentType = kAudioUnitType_Generator;
    filePlayerDescription.componentSubType = kAudioUnitSubType_AudioFilePlayer;
    
    AudioComponentDescription remoteIODescription;
    remoteIODescription.componentFlags = 0;
    remoteIODescription.componentFlagsMask = 0;
    remoteIODescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    remoteIODescription.componentType = kAudioUnitType_Output;
    remoteIODescription.componentSubType = kAudioUnitSubType_RemoteIO;
    
    __Require_noErr(AUGraphAddNode(_auGraph, &filePlayerDescription, &_nodeFilePlayer), fail);
    __Require_noErr(AUGraphAddNode(_auGraph, &remoteIODescription, &_nodeRemoteIO), fail);
    
    return YES;
fail:
    return NO;
}

- (BOOL)connectNodes {
    __Require_noErr(AUGraphConnectNodeInput(_auGraph, _nodeFilePlayer, 0, _nodeRemoteIO, 0), fail);
    return YES;
fail:
    return NO;
}

- (BOOL)prepareAUs {
    __Require_noErr(AUGraphNodeInfo(_auGraph, _nodeFilePlayer, NULL, &_auFilePlayer), fail);
    __Require_noErr(AUGraphNodeInfo(_auGraph, _nodeRemoteIO, NULL, &_auRemoteIO), fail);
    return YES;
fail:
    return NO;
}

- (BOOL)setupAUGraph {
    __Require_noErr(NewAUGraph(&_auGraph), fail);
    return YES;
fail:
    return NO;
}

- (BOOL)openGraph {
    __Require_noErr(AUGraphOpen(_auGraph), fail);
    return YES;
fail:
    return NO;
}

- (BOOL)closeGraph {
    __Require_noErr(AUGraphClose(_auGraph), fail);
    return YES;
fail:
    return NO;
}

- (BOOL)initializeGraph {
    __Require_noErr(AUGraphInitialize(_auGraph), fail);
    return YES;
fail:
    return NO;
}

- (BOOL)uninitializeGraph {
    __Require_noErr(AUGraphUninitialize(_auGraph), fail);
    return YES;
fail:
    return NO;
}

- (BOOL)startGraph {
    __Require_Quiet(![self isGraphStarted], fail);
    __Require_noErr(AUGraphStart(_auGraph), fail);
    CAShow(_auGraph);
    return YES;
fail:
    return NO;
}


- (BOOL)stopGraph {
    __Require_noErr(AUGraphStop(_auGraph), fail);
    return YES;
fail:
    return NO;
}

- (BOOL)isGraphOpened {
    Boolean value = false;
    __Require_noErr(AUGraphIsOpen(_auGraph, &value), fail);
    return value;
fail:
    return NO;
}

- (BOOL)isGraphInited {
    Boolean value = false;
    __Require_noErr(AUGraphIsInitialized(_auGraph, &value), fail);
    return value;
fail:
    return NO;
}

- (BOOL)isGraphStarted {
    Boolean value = false;
    __Require_noErr(AUGraphIsRunning(_auGraph, &value), fail);
    return value;
fail:
    return NO;
}

- (BOOL)resetGraph {
    __Require_noErr(AudioUnitReset(_auFilePlayer, kAudioUnitScope_Global, 0), fail);
    __Require_noErr(AudioUnitReset(_auRemoteIO, kAudioUnitScope_Input, 0), fail);
    __Require_Quiet([self adjustStartupTime], fail);
    return YES;
fail:
    return NO;
}

@end
