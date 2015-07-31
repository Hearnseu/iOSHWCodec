//
//  ViewController.m
//  videoCodec
//
//  Created by INMOTION on 15/7/31.
//  Copyright (c) 2015年 INMOTION. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "AAPLEAGLLayer.h"
#import "VideoToolboxPlus.h"


VTDecompressionSessionRef decompressionSession;
AAPLEAGLLayer *displayLayer;
CMFormatDescriptionRef formatDescription;


@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate,VTPCompressionSessionDelegate>

@property(nonatomic, strong) AVCaptureDevice *videoDevice;
@property(nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property(nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property(nonatomic, strong) AVCaptureConnection *videoConnection;
@property(nonatomic, strong) AVCaptureSession *videoSession;

@property(nonatomic, strong) VTPCompressionSession *vtpCompressionSession;
@property(nonatomic, strong) AVSampleBufferDisplayLayer *sampleLayer;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, strong) dispatch_queue_t compressionQueue;
@property(nonatomic, strong) dispatch_queue_t videoOutputQueue;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self videoSessionSetup];
    [self compressionSetup];
    // Do any additional setup after loading the view, typically from a nib.
}

#pragma mark - encoding

-(void)videoSessionSetup
{
    NSError *error;
    self.videoDevice=[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    self.videoInput=[AVCaptureDeviceInput deviceInputWithDevice:self.videoDevice error:&error];
    if (error) {
        return;
    }
    
    self.videoSession=[[AVCaptureSession alloc]init];
    self.videoSession.sessionPreset=AVCaptureSessionPresetMedium;
    
    if ([self.videoSession canAddInput:self.videoInput]) {
        [self.videoSession addInput:self.videoInput];
    }
    
    self.videoOutputQueue=dispatch_queue_create("com.video.output", NULL);
    self.videoOutput=[[AVCaptureVideoDataOutput alloc]init];
    self.videoOutput.alwaysDiscardsLateVideoFrames=YES;
    self.videoOutput.videoSettings=@{(id)kCVPixelBufferPixelFormatTypeKey:
                                         @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)};
    [self.videoOutput setSampleBufferDelegate:self queue:self.videoOutputQueue];
    if ([self.videoSession canAddOutput:self.videoOutput]) {
        [self.videoSession addOutput:self.videoOutput];
    }
    
    self.videoConnection=[self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if ([self.videoDevice.activeFormat isVideoStabilizationModeSupported:AVCaptureVideoStabilizationModeCinematic]) {
        [self.videoConnection setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeCinematic];
    }else if([self.videoDevice.activeFormat isVideoStabilizationModeSupported:AVCaptureVideoStabilizationModeAuto]){
        [self.videoConnection setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeAuto];
    }

    
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.videoSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.backgroundColor=[UIColor blackColor].CGColor;
    
    CGSize size=[UIScreen mainScreen].bounds.size;
    
    self.previewLayer.frame=CGRectMake(0, 0, size.width, size.height/2);
    [self.view.layer addSublayer:self.previewLayer];
    
    [UIApplication sharedApplication].statusBarHidden=YES;
    
    
    self.sampleLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.sampleLayer.frame = CGRectMake(0, size.height/2, size.width, size.height/2);
    self.sampleLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.sampleLayer.backgroundColor = [[UIColor greenColor] CGColor];
    [self.view.layer addSublayer:self.sampleLayer];
    self.sampleLayer.transform=CATransform3DMakeRotation(M_PI/2, 0, 0, 1);
    [self.videoSession startRunning];

    
}

-(void)compressionSetup
{
    NSError *error;
    _vtpCompressionSession=[[VTPCompressionSession alloc]initWithWidth:480 height:320 codec:kCMVideoCodecType_H264 error:&error];
    if (!error) {
        NSLog(@"ressionSession sucess");
    }else{
        NSLog(@"failed ");
    }
    
    
    _compressionQueue=dispatch_queue_create("video.compression", NULL);
    [_vtpCompressionSession setDelegate:self queue:self.compressionQueue];
    
    [_vtpCompressionSession setMaxKeyframeInterval:16 error:&error];
    if (!error) {
        NSLog(@"setMaxKeyframeInterval sucess");
    }
    [_vtpCompressionSession setAllowTemporalCompression:YES error:&error];
    if (!error) {
        NSLog(@"setAllowTemporalCompression sucess");
    }
    [_vtpCompressionSession setAverageBitrate:480*320*4.5 error:&error];
    if (!error) {
        NSLog(@"setAverageBitrate sucess");
    }
    [_vtpCompressionSession setProfileLevel:AVVideoProfileLevelH264BaselineAutoLevel error:&error];
    if (!error) {
        NSLog(@"setProfileLevel sucess");
    }


}

-(void)videoCompressionSession:(VTPCompressionSession *)compressionSession didEncodeSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    [self.sampleLayer enqueueSampleBuffer:sampleBuffer];
}

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (connection==self.videoConnection) {
        
        [_vtpCompressionSession encodeSampleBuffer:sampleBuffer forceKeyframe:NO];
    }

}

#pragma mark - decoding

-(void)createDecompSession
{
    // make sure to destroy the old VTD session
    decompressionSession = NULL;
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    
    CGSize size=CGSizeMake(480, 320);
    
    //
    CFDictionaryRef attrs = NULL;
    const void *keys[] = { kCVPixelBufferPixelFormatTypeKey,kCVPixelBufferOpenGLESCompatibilityKey };
    uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    const void *values[] = { CFNumberCreate(NULL, kCFNumberSInt32Type, &v) ,kCFBooleanTrue};
    attrs = CFDictionaryCreate(NULL, keys, values, 2, NULL, NULL);
    CMVideoFormatDescriptionRef decoderFormatDescription=NULL;
    CMVideoFormatDescriptionCreate (NULL,kCMVideoCodecType_H264 , size.width, size.height, NULL, &decoderFormatDescription );
    
    
    OSStatus status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                   decoderFormatDescription,
                                                   NULL, attrs,
                                                   &callBackRecord,
                                                   &decompressionSession);
    
    NSLog(@"Video Decompression Session Create: \t %@", (status == noErr) ? @"successful!" : @"failed...");
    if(status != noErr) NSLog(@"\t\t VTD ERROR type: %d", (int)status);
    
    formatDescription = NULL;
    CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCMVideoCodecType_H264, 480, 320, nil, &formatDescription);
    
    displayLayer=[AAPLEAGLLayer layer];
    displayLayer.frame=self.view.bounds;
    displayLayer.presentationRect=CGSizeMake(size.width, size.height);
    [self.view.layer addSublayer:displayLayer];
    
    
}

-(void)decodingSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
    VTDecodeInfoFlags flagOut;
    VTDecompressionSessionDecodeFrame(decompressionSession, sampleBuffer, flags, NULL, &flagOut);

}

void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon,
                                             void *sourceFrameRefCon,
                                             OSStatus status,
                                             VTDecodeInfoFlags infoFlags,
                                             CVImageBufferRef imageBuffer,
                                             CMTime presentationTimeStamp,
                                             CMTime presentationDuration)
{
    if (status != noErr)
    {
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        NSLog(@"Decompressed error: %@", error);
    }
    else
    {
        NSLog(@"Decompressed sucessfully");
        
        [displayLayer displayPixelBuffer:imageBuffer];
    }
}



-(void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    if (size.height > size.width) {
        self.previewLayer.frame=CGRectMake(0, 0, size.width, size.height/2);
        self.sampleLayer.frame = CGRectMake(0, size.height/2, size.width, size.height/2);
    }else{
        self.previewLayer.frame=CGRectMake(0, 0, size.width/2, size.height);
        self.sampleLayer.frame = CGRectMake( size.width/2, 0, size.width/2, size.height);
        
    }


}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
