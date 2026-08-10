#import "OpenCVWrapper.h"
#import <CoreImage/CoreImage.h>
#import <opencv2/opencv.hpp>

@implementation FeatureMatchResult
@end

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

+ (FeatureMatchResult *)matchFeaturesBetween:(UIImage *)image1 and:(UIImage *)image2 {
    FeatureMatchResult *result = [FeatureMatchResult new];
    result.points1 = @[];
    result.points2 = @[];

    cv::Mat rgba1 = matFromUIImage(image1);
    cv::Mat rgba2 = matFromUIImage(image2);
    if (rgba1.empty() || rgba2.empty()) {
        return result;
    }

    cv::Mat gray1, gray2;
    cv::cvtColor(rgba1, gray1, cv::COLOR_RGBA2GRAY);
    cv::cvtColor(rgba2, gray2, cv::COLOR_RGBA2GRAY);

    cv::Ptr<cv::ORB> orb = cv::ORB::create(2000);
    std::vector<cv::KeyPoint> keypoints1, keypoints2;
    cv::Mat descriptors1, descriptors2;
    orb->detectAndCompute(gray1, cv::noArray(), keypoints1, descriptors1);
    orb->detectAndCompute(gray2, cv::noArray(), keypoints2, descriptors2);

    if (descriptors1.empty() || descriptors2.empty()) {
        return result;
    }

    cv::BFMatcher matcher(cv::NORM_HAMMING);
    std::vector<std::vector<cv::DMatch>> knnMatches;
    matcher.knnMatch(descriptors1, descriptors2, knnMatches, 2);

    NSMutableArray<NSValue *> *points1 = [NSMutableArray array];
    NSMutableArray<NSValue *> *points2 = [NSMutableArray array];

    for (const auto &matches : knnMatches) {
        if (matches.size() < 2 || matches[0].distance >= 0.75f * matches[1].distance) {
            continue;
        }

        const cv::DMatch &match = matches[0];
        if (match.queryIdx < 0 || match.trainIdx < 0 ||
            static_cast<size_t>(match.queryIdx) >= keypoints1.size() ||
            static_cast<size_t>(match.trainIdx) >= keypoints2.size()) {
            continue;
        }

        const cv::Point2f &point1 = keypoints1[match.queryIdx].pt;
        const cv::Point2f &point2 = keypoints2[match.trainIdx].pt;
        [points1 addObject:[NSValue valueWithCGPoint:CGPointMake(point1.x, point1.y)]];
        [points2 addObject:[NSValue valueWithCGPoint:CGPointMake(point2.x, point2.y)]];
    }

    result.points1 = points1;
    result.points2 = points2;
    return result;
}

@end
