//
//  AudioUnitRecorder.m
//  AudioUnitPlayer
//
//  Created by Sajiv Nair on 02/07/15.
//  Copyright (c) 2015 intelliswift. All rights reserved.
//

#import "AudioUnitRecorder.h"
#import <AudioToolbox/AudioSession.h>
#import <AudioUnit/AUComponent.h>
#import <AudioUnit/AudioUnitProperties.h>
#import <AudioUnit/AudioOutputUnit.h>

@implementation AudioUnitRecorder

OSStatus recordCallback(void                              *inRefCon,
                        AudioUnitRenderActionFlags        *ioActionFlags,
                        const AudioTimeStamp              *inTimeStamp,
                        UInt32                            inBusNumber,
                        UInt32                            inNumberFrames,
                        AudioBufferList                   *ioData){
    
    AudioBufferList bufferList;
    UInt16 numSamples=inNumberFrames*kChannels;
    UInt16 samples[numSamples];
    memset (&samples, 0, sizeof (samples));
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = samples;
    bufferList.mBuffers[0].mNumberChannels = kChannels;
    bufferList.mBuffers[0].mDataByteSize = numSamples*sizeof(UInt16);
    AudioUnitRecorder* this = (__bridge AudioUnitRecorder *)inRefCon;
    CheckError(AudioUnitRender(this->mAudioUnit,
                               ioActionFlags,
                               inTimeStamp,
                               kInputBus,
                               inNumberFrames,
                               &bufferList),"AudioUnitRender failed");
    
    // Now, we have the samples we just read sitting in buffers in bufferList
    ExtAudioFileWriteAsync(this->mAudioFileRef, inNumberFrames, &bufferList);
    return noErr;
}

static void CheckError(OSStatus error,const char *operaton){
    if (error==noErr) {
        return;
    }
    char errorString[20]={};
    *(UInt32 *)(errorString+1)=CFSwapInt32HostToBig(error);
    if (isprint(errorString[1])&&isprint(errorString[2])&&isprint(errorString[3])&&isprint(errorString[4])) {
        errorString[0]=errorString[5]='\'';
        errorString[6]='\0';
    }else{
        sprintf(errorString, "%d",(int)error);
    }
    fprintf(stderr, "Error:%s (%s)\n",operaton,errorString);
    exit(1);
}

void routeChangeListener(void                      *inClientData,
                              AudioSessionPropertyID    inID,
                              UInt32                    inDataSize,
                              const void                *inData) {
    printf("audioRouteChangeListener");
}

void interruptionListener(void *inClientData,UInt32 inInterruptionState){
    switch (inInterruptionState) {
        case kAudioSessionBeginInterruption:
            break;
        case kAudioSessionEndInterruption:
            break;
        default:
            break;
    }
}


-(void)configAudio {
    //Upon launch, the application automatically gets a singleton audio session.
    //Initialize a session and registering an interruption callback
    CheckError(AudioSessionInitialize(NULL, kCFRunLoopDefaultMode, interruptionListener, (__bridge void *)(self)), "couldn't initialize the audio session");
    
    //Add a AudioRouteChange listener
    CheckError(AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, routeChangeListener, (__bridge void *)(self)),"couldn't add a route change listener");
    
    //Is there an audio input device available
    UInt32 inputAvailable;
    UInt32 propSize=sizeof(inputAvailable);
    CheckError(AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable, &propSize, &inputAvailable), "not available for the current input audio device");
    if (!inputAvailable) {
        return;
    }
    
    //Adjust audio hardware I/O buffer duration.If I/O latency is critical in your app, you can request a smaller duration.
    Float32 ioBufferDuration = .005;
    CheckError(AudioSessionSetProperty(kAudioSessionProperty_PreferredHardwareIOBufferDuration, sizeof(ioBufferDuration), &ioBufferDuration),"couldn't set the buffer duration on the audio session");
    
    //Set the audio category
    UInt32 audioCategory = kAudioSessionCategory_PlayAndRecord;
    CheckError(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(audioCategory), &audioCategory), "couldn't set the category on the audio session");
    
    UInt32 override=true;
    AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker, sizeof(override), &override);
    
    //Get hardware sample rate and setting the audio format
    Float64 sampleRate;
    UInt32 sampleRateSize=sizeof(sampleRate);
    CheckError(AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate, &sampleRateSize, &sampleRate),                                      "Couldn't get hardware samplerate");
    mAudioFormat.mSampleRate         = sampleRate;
    mAudioFormat.mFormatID           = kAudioFormatLinearPCM; //kAudioFormatMPEG4AAC
    mAudioFormat.mFormatFlags        = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;  // kMPEG4Object_AAC_Main
    mAudioFormat.mFramesPerPacket    = 1;
    mAudioFormat.mChannelsPerFrame   = kChannels;
    mAudioFormat.mBitsPerChannel     = 16;
    mAudioFormat.mBytesPerFrame      = mAudioFormat.mBitsPerChannel*mAudioFormat.mChannelsPerFrame/8;
    mAudioFormat.mBytesPerPacket     = mAudioFormat.mBytesPerFrame*mAudioFormat.mFramesPerPacket;
    mAudioFormat.mReserved           = 0;
    
    //Obtain a RemoteIO unit instance
    AudioComponentDescription acd;
    acd.componentType = kAudioUnitType_Output;
    acd.componentSubType = kAudioUnitSubType_RemoteIO;
    acd.componentFlags = 0;
    acd.componentFlagsMask = 0;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &acd);
    CheckError(AudioComponentInstanceNew(inputComponent, &mAudioUnit), "Couldn't new AudioComponent instance");
    
    //The Remote I/O unit, by default, has output enabled and input disabled
    //Enable input scope of input bus for recording.
    UInt32 enable = 1;
    UInt32 disable=0;
    CheckError(AudioUnitSetProperty(mAudioUnit,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Input,
                                    kInputBus,
                                    &enable,
                                    sizeof(enable)),
                                    "kAudioOutputUnitProperty_EnableIO::kAudioUnitScope_Input::kInputBus");
    
    //Apply format to output scope of input bus for recording.
    CheckError(AudioUnitSetProperty(mAudioUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    kInputBus,
                                    &mAudioFormat,
                                    sizeof(mAudioFormat)),
                                    "kAudioUnitProperty_StreamFormat::kAudioUnitScope_Output::kInputBus");
    
    //Disable buffer allocation for recording(optional)
    CheckError(AudioUnitSetProperty(mAudioUnit,
                                    kAudioUnitProperty_ShouldAllocateBuffer,
                                    kAudioUnitScope_Output,
                                    kInputBus,
                                    &disable,
                                    sizeof(disable)),
                                    "kAudioUnitProperty_ShouldAllocateBuffer::kAudioUnitScope_Output::kInputBus");
    
    //Applying format to input scope of output bus for playing
    CheckError(AudioUnitSetProperty(mAudioUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Input,
                                    kOutputBus,
                                    &mAudioFormat,
                                    sizeof(mAudioFormat)),
                                    "kAudioUnitProperty_StreamFormat::kAudioUnitScope_Input::kOutputBus");
    
    //AudioUnitInitialize
    CheckError(AudioUnitInitialize(mAudioUnit), "AudioUnitInitialize");
}


- (id)init {
    
    [self configAudio];
    
    AURenderCallbackStruct recorderStruct;
    recorderStruct.inputProc = recordCallback;
    recorderStruct.inputProcRefCon = (__bridge void *)(self);
    CheckError(AudioUnitSetProperty(mAudioUnit,
                                    kAudioOutputUnitProperty_SetInputCallback,
                                    kAudioUnitScope_Input,
                                    kInputBus,
                                    &recorderStruct,
                                    sizeof(recorderStruct)),
                                    "kAudioOutputUnitProperty_SetInputCallback::kAudioUnitScope_Input::kInputBus");
    return self;
}

-(void)setFilePath:(NSString *)destinationFilePath {
    
    CFURLRef destinationURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)destinationFilePath, kCFURLPOSIXPathStyle, false);
    CheckError(ExtAudioFileCreateWithURL(destinationURL, kAudioFileM4AType, &mAudioFormat, NULL, kAudioFileFlags_EraseFile, &mAudioFileRef),"Couldn't create a file for writing");
    CFRelease(destinationURL);

}

-(void)startRecording {
     AudioOutputUnitStart(mAudioUnit);
}

-(void)stopRecording {
    AudioOutputUnitStop(mAudioUnit);
}




@end