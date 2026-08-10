#import "OpenCVWrapper.h"
#import <CoreImage/CoreImage.h>
#import <opencv2/opencv.hpp>

// UIImage(CGImage 기반) -> cv::Mat(RGBA) 변환.
// 이후 태스크(feature matching 등)에서도 재사용하므로 static 헬퍼로 분리해둔다.
static cv::Mat matFromUIImage(UIImage *image) {
    if (!image) {
        return cv::Mat();
    }

    CGImageRef cgImage = image.CGImage;
    bool ownsCGImage = false;
    if (!cgImage && image.CIImage) {
        CGRect extent = image.CIImage.extent;
        if (!CGRectIsNull(extent) && !CGRectIsInfinite(extent) && !CGRectIsEmpty(extent)) {
            CIContext *context = [CIContext contextWithOptions:nil];
            cgImage = [context createCGImage:image.CIImage fromRect:extent];
            ownsCGImage = (cgImage != nil);
        }
    }
    if (!cgImage) {
        return cv::Mat();
    }

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    CGColorSpaceRef sourceColorSpace = CGImageGetColorSpace(cgImage);
    CGColorSpaceModel colorSpaceModel = sourceColorSpace ? CGColorSpaceGetModel(sourceColorSpace) : kCGColorSpaceModelUnknown;
    if (width == 0 || height == 0 || (colorSpaceModel != kCGColorSpaceModelRGB && colorSpaceModel != kCGColorSpaceModelMonochrome)) {
        if (ownsCGImage) {
            CGImageRelease(cgImage);
        }
        return cv::Mat();
    }

    cv::Mat mat(static_cast<int>(height), static_cast<int>(width), CV_8UC4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
    CGContextRef contextRef = CGBitmapContextCreate(mat.data, width, height, 8, mat.step[0],
                                                      colorSpace,
                                                      bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    if (!contextRef) {
        if (ownsCGImage) {
            CGImageRelease(cgImage);
        }
        return cv::Mat();
    }
    CGContextDrawImage(contextRef, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(contextRef);
    if (ownsCGImage) {
        CGImageRelease(cgImage);
    }
    return mat;
}

@implementation OpenCVWrapper

+ (NSString *)openCVVersion {
    return [NSString stringWithUTF8String:CV_VERSION];
}

+ (double)laplacianVarianceForImage:(UIImage *)image {
    cv::Mat rgba = matFromUIImage(image);
    if (rgba.empty()) {
        return 0.0;
    }
    cv::Mat gray;
    cv::cvtColor(rgba, gray, cv::COLOR_RGBA2GRAY);

    cv::Mat laplacian;
    cv::Laplacian(gray, laplacian, CV_64F);

    cv::Scalar mean, stddev;
    cv::meanStdDev(laplacian, mean, stddev);
    return stddev[0] * stddev[0]; // variance = stddev^2
}

@end
