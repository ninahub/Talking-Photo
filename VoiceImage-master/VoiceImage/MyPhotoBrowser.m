//
//  MyPhotoBrowser.m
//  VoiceImage
//
//  Created by SPG on 7/3/15.
//  Copyright (c) 2015 SPG. All rights reserved.
//

#import "MyPhotoBrowser.h"
#import "global.h"
#import "HttpHelper.h"
#import "PhotoDataProvider.h"
#import "HttpHelper.h"
#import "IATConfig.h"
#import "ISRDataHelper.h"
#import <MAMapKit/MAMapKit.h>
#import <AMapSearchKit/AMapSearchAPI.h>
#import "DataBaseHelper.h"

#define SEARCH_PHOTO 0
#define RETAG_PHOTO 1

@interface MyPhotoBrowser () <MAMapViewDelegate, AMapSearchDelegate>
{
    AMapSearchAPI *_search;
    int _voiceSource;
}
@property (strong, nonatomic) NSMutableArray * imageNameArray;

@end

@implementation MyPhotoBrowser

- (NSMutableArray *) imageNameArray
{
    if(_imageNameArray == nil)
    {
        _imageNameArray = [[NSMutableArray alloc] init];
    }
    return _imageNameArray;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if (error)
    {
        NSLog(@"Error setting up audio session category: %@", error.localizedDescription);
    }
    [session setActive:YES error:&error];
    if (error)
    {
        NSLog(@"Error setting up audio session active: %@", error.localizedDescription);
    }
    
    self.microphone = [EZMicrophone microphoneWithDelegate:self];
    CGRect rect = [[UIScreen mainScreen] bounds];
    rect.origin.x = 0;
    rect.origin.y = rect.size.height / 2 - 95;
    rect.size.height = 190;
    
    self.recordingAudioPlot = [[EZAudioPlotGL alloc] initWithFrame:rect];
    self.recordingAudioPlot.color           = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0];
    UIColor* color = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.3];
    self.recordingAudioPlot.backgroundColor = color;
    self.recordingAudioPlot.plotType        = EZPlotTypeBuffer;
    self.recordingAudioPlot.shouldFill      = NO;
    self.recordingAudioPlot.shouldMirror    = YES;
    self.recordingAudioPlot.hidden = YES;
    self.recordingAudioPlot.gain = 4.0;
    
    [self.view addSubview:self.recordingAudioPlot];
    
}

-(void)initRecognizer
{
    NSLog(@"%s",__func__);
    
    //单例模式，无UI的实例
    if (_iFlySpeechRecognizer == nil) {
        _iFlySpeechRecognizer = [IFlySpeechRecognizer sharedInstance];
        
        [_iFlySpeechRecognizer setParameter:@"" forKey:[IFlySpeechConstant PARAMS]];
        
        //设置听写模式
        [_iFlySpeechRecognizer setParameter:@"iat" forKey:[IFlySpeechConstant IFLY_DOMAIN]];
    }
    _iFlySpeechRecognizer.delegate = self;
    
    if (_iFlySpeechRecognizer != nil) {
        IATConfig *instance = [IATConfig sharedInstance];
        
        //设置最长录音时间
        [_iFlySpeechRecognizer setParameter:instance.speechTimeout forKey:[IFlySpeechConstant SPEECH_TIMEOUT]];
        //设置后端点
        [_iFlySpeechRecognizer setParameter:instance.vadEos forKey:[IFlySpeechConstant VAD_EOS]];
        //设置前端点
        [_iFlySpeechRecognizer setParameter:instance.vadBos forKey:[IFlySpeechConstant VAD_BOS]];
        //网络等待时间
        [_iFlySpeechRecognizer setParameter:@"20000" forKey:[IFlySpeechConstant NET_TIMEOUT]];
        
        //设置采样率，推荐使用16K
        [_iFlySpeechRecognizer setParameter:instance.sampleRate forKey:[IFlySpeechConstant SAMPLE_RATE]];
        
        if ([instance.language isEqualToString:[IATConfig chinese]]) {
            //设置语言
            [_iFlySpeechRecognizer setParameter:instance.language forKey:[IFlySpeechConstant LANGUAGE]];
            //设置方言
            [_iFlySpeechRecognizer setParameter:instance.accent forKey:[IFlySpeechConstant ACCENT]];
        }else if ([instance.language isEqualToString:[IATConfig english]]) {
            [_iFlySpeechRecognizer setParameter:instance.language forKey:[IFlySpeechConstant LANGUAGE]];
        }
        //设置是否返回标点符号
        [_iFlySpeechRecognizer setParameter:instance.dot forKey:[IFlySpeechConstant ASR_PTT]];
        
    }
}

- (void)setNavBarAppearance:(BOOL)animated
{
    
}

-(void)startRecord{
    _voiceSource = 0;
    self.recordingAudioPlot.hidden = NO;
    [self.view bringSubviewToFront:self.recordingAudioPlot];
    [self.recordingAudioPlot clear];
    [self.microphone startFetchingAudio];
    
    if (_iFlySpeechRecognizer == nil){
        [self initRecognizer];//初始化识别对象
    }
    //start SR interface
    [_iFlySpeechRecognizer cancel];
    //设置音频来源为麦克风
    [_iFlySpeechRecognizer setParameter:IFLY_AUDIO_SOURCE_MIC forKey:@"audio_source"];
    //设置听写结果格式为json
    [_iFlySpeechRecognizer setParameter:@"json" forKey:[IFlySpeechConstant RESULT_TYPE]];
    //保存录音文件，保存在sdk工作路径中，如未设置工作路径，则默认保存在library/cache下
    [_iFlySpeechRecognizer setParameter:@"asr2.pcm" forKey:[IFlySpeechConstant ASR_AUDIO_PATH]];
    [_iFlySpeechRecognizer setDelegate:self];
    BOOL ret = [_iFlySpeechRecognizer startListening];
    if (ret == NO){
        NSLog(@"failed");
    }

}

-(void)stopRecord{
    _voiceSource = 0;
    self.recordingAudioPlot.hidden = YES;
    [self.microphone stopFetchingAudio];
    [_iFlySpeechRecognizer stopListening];
}

-(void)foldAllPhotos{
    [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_FOLD_PHOTO_NOTIFICATION object:nil];
}

//not use
-(void)searchResponse:(NSData*)data {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ENABLE_GRIDVIEW"
                                                        object:nil];
    
    if (data == nil) {
        return;
    }
    NSError *error2;
    NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error2];
    NSLog(@"%@", jsonDict);
    BOOL suc = [[jsonDict valueForKey:@"Status"] boolValue];
    if (suc) {
        NSArray* imagesList = (NSArray*)[jsonDict valueForKey:@"Images"];
        NSMutableArray* imgs = [[NSMutableArray alloc] init];
        for (NSDictionary* dict in imagesList) {
            [imgs addObject:[dict valueForKey:@"ImageName"]];
        }

        NSArray* arr = [[NSArray alloc] initWithArray:imgs];
        [[PhotoDataProvider sharedInstance] getPicturesByName:self withSelector:@selector(imagesRetrieved:) names:arr];
    }
    else{
        [PhotoDataProvider sharedInstance].photos = nil;
        [PhotoDataProvider sharedInstance].thumbs = nil;
        [self reloadData];
        [self reloadGridView];
    }
}

-(void)imagesRetrieved:(id)object{
    [self reloadData];
    [self reloadGridView];
}

-(void)startUpdateRecord {
    _voiceSource = 1;
    
    self.recordingAudioPlot.hidden = NO;
    [self.view bringSubviewToFront:self.recordingAudioPlot];
    [self.recordingAudioPlot clear];
    [self.microphone startFetchingAudio];
    
    if (_iFlySpeechRecognizer == nil){
        [self initRecognizer];//初始化识别对象
    }
    //start SR interface
    [_iFlySpeechRecognizer cancel];
    //设置音频来源为麦克风
    [_iFlySpeechRecognizer setParameter:IFLY_AUDIO_SOURCE_MIC forKey:@"audio_source"];
    //设置听写结果格式为json
    [_iFlySpeechRecognizer setParameter:@"json" forKey:[IFlySpeechConstant RESULT_TYPE]];
    //保存录音文件，保存在sdk工作路径中，如未设置工作路径，则默认保存在library/cache下
    [_iFlySpeechRecognizer setParameter:@"asr2.pcm" forKey:[IFlySpeechConstant ASR_AUDIO_PATH]];
    [_iFlySpeechRecognizer setDelegate:self];
    BOOL ret = [_iFlySpeechRecognizer startListening];
    if (ret == NO){
        NSLog(@"failed");
    }

}

-(void)scrollToBottom {
    [super scrollToBottom];
}

-(void)stopUpdateRecord:(NSString*)imageName imageData:(NSData*)imageData {
    
    _voiceSource = 1;
    [self.imageNameArray removeAllObjects];
    [self.imageNameArray addObject:imageName];
    
    self.recordingAudioPlot.hidden = YES;
    [self.microphone stopFetchingAudio];
    [_iFlySpeechRecognizer stopListening];
    
}


-(void)stopUpdateRecordList:(NSArray*)imageName imageData:(NSArray*)imageData {
    //TOOD: upload group of images and one voice to website
    _voiceSource = 1;
    [self.imageNameArray removeAllObjects];
    
    NSArray * indexArr = [[PhotoDataProvider sharedInstance] selected];
    for (NSNumber * indexObject in indexArr) {
        NSInteger index = [indexObject integerValue];
        MWPhoto * photo = [[PhotoDataProvider sharedInstance] photoBrowser:self photoAtIndex:index];
        NSString* name = [photo caption];
        [self.imageNameArray addObject:name];
    }
    self.recordingAudioPlot.hidden = YES;
    [self.microphone stopFetchingAudio];
    [_iFlySpeechRecognizer stopListening];
}

-(void)uploadResponse:(NSData*)data {
    NSError *error2;
    NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error2];
    NSLog(@"%@", jsonDict);
    BOOL suc = [[jsonDict valueForKey:@"status"] boolValue];
    if (suc) {
        UIAlertView *myAlertView = [[UIAlertView alloc] initWithTitle:@"Success" message:@"Voice Image Updated" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [myAlertView show];
    }
}

- (void)   microphone:(EZMicrophone *)microphone
     hasAudioReceived:(float **)buffer
       withBufferSize:(UInt32)bufferSize
 withNumberOfChannels:(UInt32)numberOfChannels
{
    // Getting audio data as an array of float buffer arrays. What does that mean? Because the audio is coming in as a stereo signal the data is split into a left and right channel. So buffer[0] corresponds to the float* data for the left channel while buffer[1] corresponds to the float* data for the right channel.
    NSUInteger now = [[NSDate date] timeIntervalSince1970] * 1000;
    if (now - last > 50) {
        float sum = 0;
        for (int i = 0; i < bufferSize; i++) {
            float b = buffer[0][i];
            if (b > 0) {
                sum += b;
            }
        }
        
        sum /= bufferSize;
        if (sum < 0.001) {
            for (int i = 0; i < bufferSize; i++) {
                buffer[0][i] = 0;
            }
        }
        
        // See the Thread Safety warning above, but in a nutshell these callbacks happen on a separate audio thread. We wrap any UI updating in a GCD block on the main thread to avoid blocking that audio flow.
        __weak typeof (self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            // All the audio plot needs is the buffer data (float*) and the size. Internally the audio plot will handle all the drawing related code, history management, and freeing its own resources. Hence, one badass line of code gets you a pretty plot :)
            [weakSelf.recordingAudioPlot updateBuffer:buffer[0]
                                           withBufferSize:bufferSize];
        });
        
        last = now;
    }
    
}

//地址转经纬度回调
- (void)onGeocodeSearchDone:(AMapGeocodeSearchRequest *)request response:(AMapGeocodeSearchResponse *)response
{

    if(response.geocodes.count == 0)
    {
        NSLog(@"address not found!");
        return;
    }
    //处理搜索结果
//    NSString *strCount = [NSString stringWithFormat:@"count: %ld", (long)response.count];
//    NSLog(@"%@----%@",request.description, strCount);
//    for (AMapGeocode  *p in response.geocodes) {
//        NSLog(@"%@",p.location);
//    }
    AMapGeocode * p = [response.geocodes objectAtIndex:0];
    
    NSString * loc = [NSString stringWithFormat:@"%@",p.location];
    loc = [loc substringFromIndex:1];
    NSRange range = [loc rangeOfString:@"}"];
    loc = [loc substringToIndex:range.location+range.length-1];
    loc = [NSString stringWithFormat:@"%@,%@,%@,%@",loc,p.province,p.city,p.district];
    //发送search请求
    [[HttpHelper sharedHttpHelper] AFNetworingForSearchWithUserId:userId Desc:self.result Tag:searchTag Loc:loc Token:token RefreshObject:self];
}

#pragma mark - IFlySpeechRecognizerDelegate

/**
 听写结束回调（注：无论听写是否正确都会回调）
 error.errorCode =
 0     听写正确
 other 听写出错
 ****/
- (void) onError:(IFlySpeechError *) error
{
    NSLog(@"%s",__func__);
    
    if (error.errorCode == 0 ) {
        
    }else {
        UIAlertView *myAlertView = [[UIAlertView alloc] initWithTitle:@"提示" message:@"说话的时间太短了" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles: nil];
        [myAlertView show];
    }
    
}

/**
 无界面，听写结果回调
 results：听写结果
 isLast：表示最后一次
 ****/
- (void) onResults:(NSArray *) results isLast:(BOOL)isLast
{
    
    NSMutableString *resultString = [[NSMutableString alloc] init];
    NSDictionary *dic = results[0];
    for (NSString *key in dic) {
        [resultString appendFormat:@"%@",key];
    }
    
    NSString * resultFromJson =  [ISRDataHelper stringFromJson:resultString];
    
    if(self.result == nil)
    {
        self.result = resultFromJson;
    }
    else
    {
        self.result = [NSString stringWithFormat:@"%@%@", self.result,resultFromJson];
    }
    if (isLast){
        switch (_voiceSource) {
            case SEARCH_PHOTO:
                NSLog(@"Search--听写结果(json)：%@测试",  self.result);
                
#pragma -------------- test
                self.result = @"北京中关村微软大厦拍的照片";
                [[HttpHelper sharedHttpHelper]AFNetworkingForVoiceTag:self.result forInserting:nil orSearching:self];
                break;
                
            case RETAG_PHOTO:
                self.result = @"杯子";
                for (NSString * name in self.imageNameArray) {
                    
                    NSMutableDictionary * insertParams = [NSMutableDictionary dictionary];
                    insertParams[@"imageName"] = name;
                    insertParams[@"imagePath"] = @"";
                    insertParams[@"desc"] = self.result;
                    [[HttpHelper sharedHttpHelper] AFNetworkingForVoiceTag:self.result forInserting:insertParams orSearching:nil];
                }
                
                break;
            default:
                break;
        }
    }
}

@end
