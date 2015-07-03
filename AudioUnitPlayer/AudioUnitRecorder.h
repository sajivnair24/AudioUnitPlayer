//
//  AudioUnitRecorder.h
//  AudioUnitPlayer
//
//  Created by Sajiv Nair on 02/07/15.
//  Copyright (c) 2015 intelliswift. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioFile.h>
#import <AudioUnit/AudioComponent.h>
#import <AudioToolbox/ExtendedAudioFile.h>
#include <sys/time.h>

#import "InMemoryAudioFile.h"

#define kChannels   2
#define kOutputBus  0
#define kInputBus   1

@interface AudioUnitRecorder : NSObject {
    AudioComponentInstance      mAudioUnit;
    ExtAudioFileRef             mAudioFileRef;
    InMemoryAudioFile           *inMemoryAudioFile;
    AudioStreamBasicDescription mAudioFormat;
}

-(id)init;

// Opens an audio file
-(void)setFilePath:(NSString *)destinationFilePath;

// Play the opened file
-(void)startRecording;

// Stop playback
-(void)stopRecording;


@end