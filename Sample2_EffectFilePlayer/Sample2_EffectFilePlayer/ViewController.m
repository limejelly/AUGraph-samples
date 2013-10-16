//
//  ViewController.m
//  Sample2_EffectFilePlayer
//
//  Created by Aliksandr Andrashuk on 16.10.13.
//  Copyright (c) 2013 Aliksandr Andrashuk. All rights reserved.
//

#import "ViewController.h"
#import "Graph.h"

@interface ViewController ()
{
    Graph *_graph;
    IBOutlet UISlider *_loopSlider;
    IBOutlet UISlider *_offsetSlider;
    IBOutlet UISlider *_durationSlider;
    IBOutlet UISlider *_delaySlider;
}
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSString *path = [[NSBundle mainBundle] pathForResource:@"sound" ofType:@"caf"];
    _graph = [[Graph alloc] initWithFilePath:path];
    
    _durationSlider.maximumValue = _offsetSlider.maximumValue = [_graph durationOfFileAtIndex:0];
    _durationSlider.value = _durationSlider.maximumValue;
    _offsetSlider.value = 0;
}

- (IBAction)playButtonTouched:(id)sender {
    _graph.delayTime = _delaySlider.value;
    
    [_graph playFileAtIndex:0
                  loopCount:(int)_loopSlider.value
                 timeOffset:_offsetSlider.value
               playDuration:_durationSlider.value];
}

- (IBAction)stopButtonTouched:(id)sender {
    [_graph stop];
}

- (IBAction)delaySliderValueChanged:(id)sender {
    _graph.delayTime = _delaySlider.value;
}

@end