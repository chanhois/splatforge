#!/usr/bin/env bash
#
# OpenCV iOS xcframework를 소스에서 빌드해 Frameworks/에 설치한다.
#
# 왜 직접 빌드하는가:
#   OpenCV 공식 배포본(opencv-X.Y.Z-ios-framework.zip)은 .xcframework가 아니라
#   fat framework이고, 시뮬레이터 슬라이스가 x86_64뿐이다. Apple Silicon 맥의
#   시뮬레이터는 arm64를 요구하는데 fat framework는 기기 arm64와 시뮬레이터 arm64를
#   구분할 수 없다 — 바로 그 한계 때문에 .xcframework 포맷이 존재한다.
#   따라서 시뮬레이터에서 테스트를 돌리려면 직접 빌드하는 수밖에 없다.
#
# 빌드 결과물(약 47MB)은 git에 커밋하지 않는다(.gitignore). 클론 후 이 스크립트를
# 한 번 실행하면 된다. 소요 시간: Apple Silicon 기준 약 5분.
#
# 사용법: ./scripts/setup-opencv.sh

set -euo pipefail

OPENCV_VERSION="4.14.0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/Frameworks/opencv2.xcframework"
WORK="$(mktemp -d)"

trap 'rm -rf "$WORK"' EXIT

if [ -d "$DEST" ]; then
    echo "이미 설치돼 있음: $DEST"
    echo "다시 빌드하려면 해당 디렉토리를 지우고 재실행하세요."
    exit 0
fi

command -v cmake >/dev/null || { echo "cmake가 필요합니다: brew install cmake"; exit 1; }
xcode-select -p >/dev/null || { echo "Xcode가 필요합니다"; exit 1; }

echo "==> OpenCV $OPENCV_VERSION 소스 다운로드"
curl -sL -o "$WORK/opencv.tar.gz" \
    "https://github.com/opencv/opencv/archive/refs/tags/${OPENCV_VERSION}.tar.gz"
tar xzf "$WORK/opencv.tar.gz" -C "$WORK"
SRC="$WORK/opencv-${OPENCV_VERSION}"

# 빌드 스크립트가 `git branch --show-current`로 브랜치명을 읽는데,
# tarball에는 .git이 없어 exit 128로 죽는다. 빈 저장소로 초기화해 우회한다.
git -C "$SRC" init -q

echo "==> xcframework 빌드 (기기 arm64 + 시뮬레이터 arm64, 약 5분)"
# 이 프로젝트가 쓰는 모듈만 남긴다: core, imgproc, features2d, flann, calib3d, imgcodecs
# objc 바인딩과 swift 래퍼는 불필요 — .mm에서 C++ API를 직접 호출한다.
python3 "$SRC/platforms/apple/build_xcframework.py" \
    -o "$WORK/out" \
    --iphoneos_archs arm64 \
    --iphonesimulator_archs arm64 \
    --build_only_specified_archs \
    --iphoneos_deployment_target 17.0 \
    --without dnn --without gapi --without ml --without objdetect \
    --without photo --without stitching --without video --without videoio \
    --without highgui --without js --without java --without python --without ts \
    --without objc --disable-swift \
    > "$WORK/build.log" 2>&1 || true
# `|| true`인 이유: 빌드 스크립트가 마지막에 문서 디렉토리를 복사하려다
# FileNotFoundError로 죽지만, 그 시점엔 xcframework가 이미 완성돼 있다.
# 실제 성공 여부는 아래 산출물 존재 확인으로 판정한다.

if [ ! -d "$WORK/out/opencv2.xcframework" ]; then
    echo "빌드 실패. 로그 마지막 40줄:"
    tail -40 "$WORK/build.log"
    exit 1
fi

mkdir -p "$REPO_ROOT/Frameworks"
cp -R "$WORK/out/opencv2.xcframework" "$REPO_ROOT/Frameworks/"

echo "==> 설치 완료: $DEST"
for slice in "$DEST"/*/; do
    bin="$slice/opencv2.framework/Versions/A/opencv2"
    [ -f "$bin" ] && printf "    %-24s %s\n" "$(basename "$slice")" "$(lipo -info "$bin" | sed 's/.*: //')"
done
