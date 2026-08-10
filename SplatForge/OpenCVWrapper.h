#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FeatureMatchResult : NSObject
@property (nonatomic, strong) NSArray<NSValue *> *points1;
@property (nonatomic, strong) NSArray<NSValue *> *points2;
@end

/// OpenCV(C++)를 Swift에서 쓰기 위한 Objective-C 브릿지.
///
/// 이 헤더에는 C++ 타입을 절대 노출하지 않는다 — Swift가 직접 보는 파일이라
/// C++ 타입이 섞이면 Swift에서 import가 깨진다. C++는 항상 .mm 구현 파일 안에만 숨긴다.
@interface OpenCVWrapper : NSObject

+ (NSString *)openCVVersion;
+ (double)laplacianVarianceForImage:(UIImage *)image NS_SWIFT_NAME(laplacianVariance(forImage:));
+ (FeatureMatchResult *)matchFeaturesBetween:(UIImage *)image1
                                          and:(UIImage *)image2 NS_SWIFT_NAME(matchFeatures(between:and:));

@end

NS_ASSUME_NONNULL_END
