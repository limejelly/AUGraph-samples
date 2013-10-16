//
//  Graph.h
//  Sample1_FilePlayer
//
//  Created by Aliksandr Andrashuk on 16.10.13.
//  Copyright (c) 2013 Aliksandr Andrashuk. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Graph : NSObject

- (id)initWithFilePath:(NSString *)filePath;
- (id)initWithFilePaths:(NSArray *)filePaths;

- (BOOL)playFileAtIndex:(NSUInteger)index;

- (BOOL)playFileAtIndex:(NSUInteger)index
              loopCount:(NSInteger)loopCount;

- (BOOL)playFileAtIndex:(NSUInteger)index
              loopCount:(NSInteger)loopCount
             timeOffset:(NSTimeInterval)timeOffset;

- (BOOL)playFileAtIndex:(NSUInteger)index
              loopCount:(NSInteger)loopCount
             timeOffset:(NSTimeInterval)timeOffset
           playDuration:(NSTimeInterval)playDuration;

- (BOOL)stop;

- (NSTimeInterval)durationOfFileAtIndex:(NSUInteger)index;

@end
