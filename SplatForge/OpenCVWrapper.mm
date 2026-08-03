#import "OpenCVWrapper.h"
#import <opencv2/opencv.hpp>

@implementation OpenCVWrapper

+ (NSString *)openCVVersion {
    return [NSString stringWithUTF8String:CV_VERSION];
}

@end
