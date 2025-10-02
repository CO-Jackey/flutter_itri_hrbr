//
//  CPP-Wrapper.h
//  ITRIHRBR
//
//  Created by GeorgeTsao on 2020/9/21.
//  Copyright © 2020 ITRI. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CPP_Wrapper : NSObject 
- (void) printInfo;
- (void) setIndex:(int)i;
- (void)hr_calculate:(int) rawdata initBit:(int *) initBit HB_rate: (double *) rate HB_rawout: (double *) rawout fftArray: (double *) fft_out;
- (void)br_calculate:(int) rawdata initBit:(int *) initBit BR_rate: (double *) rate BR_rawout: (double *) rawout;
- (void)hr_setType:(int) type;
- (void)br_setType:(int) type;
- (int)hr_getType;
- (int)br_getType;
- (void)br_setThreshold:(int) threshold;
@end

//HRBRCaculate cpp;
