#import "OpenCVWrapper.h"
#import <opencv2/opencv.hpp>

// UIImage(CGImage 기반) -> cv::Mat(RGBA) 변환.
// 이후 태스크(feature matching 등)에서도 재사용하므로 static 헬퍼로 분리해둔다.
static cv::Mat matFromUIImage(UIImage *image) {
    CGImageRef cgImage = image.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);

    cv::Mat mat(static_cast<int>(height), static_cast<int>(width), CV_8UC4);
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(cgImage);
    CGContextRef contextRef = CGBitmapContextCreate(mat.data, width, height, 8, mat.step[0],
                                                      colorSpace,
                                                      kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault);
    CGContextDrawImage(contextRef, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(contextRef);
    return mat;
}

@implementation OpenCVWrapper

+ (NSString *)openCVVersion {
    return [NSString stringWithUTF8String:CV_VERSION];
}

+ (double)laplacianVarianceForImage:(UIImage *)image {
    cv::Mat rgba = matFromUIImage(image);
    cv::Mat gray;
    cv::cvtColor(rgba, gray, cv::COLOR_RGBA2GRAY);

    cv::Mat laplacian;
    cv::Laplacian(gray, laplacian, CV_64F);

    cv::Scalar mean, stddev;
    cv::meanStdDev(laplacian, mean, stddev);
    return stddev[0] * stddev[0]; // variance = stddev^2
}

@end
