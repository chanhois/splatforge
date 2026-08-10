# SplatForge Phase 1: Capture + Sparse Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iPhone 17(LiDAR 없음)에서 작은 물체 주위를 돌며 촬영하면, ARKit 카메라 포즈 + 직접 구현한 feature matching/triangulation으로 sparse 3D point cloud를 재구성해 `.ply`로 내보내는, 완결되고 실행 가능한 iOS 앱을 만든다.

**Architecture:** ARKit(`ARWorldTrackingConfiguration`)로 실시간 카메라 포즈 스트림을 받아 baseline/각도/블러 기준으로 키프레임을 실시간 필터링해 디스크에 저장한다. 캡처 종료 후, OpenCV(Objective-C++ 브릿지)로 이웃 키프레임 쌍마다 ORB 특징점을 매칭하고, 이미 알고 있는 ARKit 포즈로부터 만든 투영행렬로 `cv::triangulatePoints`를 호출해 3D 점을 복원한다. 재투영 오차로 outlier를 제거하고 `.ply`로 내보낸다.

**Tech Stack:** Swift 5.9+/SwiftUI, ARKit, OpenCV 4.x(CocoaPods, Objective-C++ 브릿지), Accelerate/simd, XCTest.

**스코프 안내:** 이 계획은 설계 스펙(`docs/superpowers/specs/2026-07-30-splatforge-design.md`)의 마일스톤 M0~M2까지만 다룬다 — Xcode 프로젝트 셋업부터 첫 sparse point cloud `.ply` 출력까지. Dense Reconstruction/Fusion/Viewer/에러처리 UI(M3~M5)는 Phase 1이 실제로 동작하는 걸 확인한 뒤 별도 계획으로 작성한다. 이렇게 나눈 이유: OpenCV 브릿지 설정이나 ARKit 좌표계 부호 규약처럼 실제로 기기에서 돌려봐야 확실해지는 디테일이 많아, M3 이후를 지금 미리 bite-size로 못박는 건 오히려 틀린 디테일을 고정할 위험이 있음.

## Global Constraints

- iOS 배포 타겟: 17.0 이상
- **반드시 실제 iPhone 기기에서 빌드/실행** — ARKit는 iOS Simulator를 지원하지 않음
- LiDAR 관련 API(`sceneDepth`, `smoothedSceneDepth`, `ARMeshAnchor`/`.sceneReconstruction`) 사용 금지 — iPhone 17 기본형은 LiDAR 없음
- OpenCV는 CocoaPods(`pod 'OpenCV'`)로 설치하고 Objective-C++(`.mm`) 브릿지를 통해서만 사용 — Swift에서 C++ 헤더 직접 import 안 함
- 오프라인 batch 처리 — 캡처 중에는 pose 스트림만 저장하고, 재구성 연산은 캡처 종료 후 별도 단계에서 실행
- **테스트 실행은 반드시 `-only-testing:SplatForgeTests`를 붙일 것** — 스킴이 자동 생성이라 그냥 `xcodebuild test`를 돌리면 Xcode가 만든 `SplatForgeUITests`(화면 방향/외관 조합마다 앱을 실행하는 `testLaunch()`)까지 딸려 실행돼 시뮬레이터가 여러 개 뜨고 훨씬 느려진다:
  ```
  xcodebuild test -project SplatForge.xcodeproj -scheme SplatForge \
    -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SplatForgeTests
  ```
- 이 프로젝트는 `PBXFileSystemSynchronizedRootGroup`(Xcode 16+)을 쓰므로, **디스크에 `.swift` 파일을 만들면 자동으로 타겟에 포함된다** — `project.pbxproj`를 수동 편집할 필요 없음
- 이 프로젝트는 학습 목적을 겸하므로, 모든 코드 스텝에 왜 이렇게 하는지 설명을 포함한다 (특히 ARKit 좌표계, simd 행렬 규약처럼 처음 보면 헷갈리는 부분)

---

## File Structure

```
SplatForge/
  Podfile
  SplatForge.xcodeproj          (Task 1에서 생성, Task 4 이후로는 SplatForge.xcworkspace로 연다)
  SplatForge/
    SplatForgeApp.swift
    ContentView.swift
    Info.plist
    OpenCVWrapper.h              (Task 4)
    OpenCVWrapper.mm             (Task 4, 5, 8, 9에서 계속 확장)
    SplatForge-Bridging-Header.h (Task 4, Xcode가 자동 생성)
    Capture/
      PosedFrame.swift           (Task 2)
      GeometricKeyframeFilter.swift (Task 3)
      KeyframeSelector.swift     (Task 6)
      CaptureSession.swift       (Task 2, Task 6에서 확장)
      CaptureView.swift          (Task 7)
    Extensions/
      CVPixelBuffer+UIImage.swift (Task 6)
    Reconstruction/
      ProjectionMath.swift       (Task 9)
      SparsePoint3D.swift        (Task 10)
      SparseReconstructor.swift  (Task 10)
      PLYExporter.swift          (Task 10)
      ReconstructionViewModel.swift (Task 11)
    Result/
      ResultView.swift           (Task 11)
  SplatForgeTests/
    GeometricKeyframeFilterTests.swift (Task 3)
    OpenCVBridgeTests.swift      (Task 4)
    BlurFilterTests.swift        (Task 5)
    KeyframeSelectorStateTests.swift (Task 6)
    FeatureMatchingTests.swift   (Task 8)
    ProjectionMathTests.swift    (Task 9)
    TriangulationTests.swift     (Task 9)
    PLYExporterTests.swift       (Task 10)
```

---

### Task 1: Xcode 프로젝트 생성 + 기기 셋업 + 최소 카메라 프리뷰

**Files:**
- Create: `SplatForge.xcodeproj` (Xcode가 생성)
- Create: `SplatForge/SplatForgeApp.swift`
- Create: `SplatForge/ContentView.swift`
- Modify: `SplatForge/Info.plist`

**Interfaces:**
- Consumes: 없음(첫 태스크)
- Produces: `ContentView` (SwiftUI 진입점 뷰) — 이후 태스크들이 여기에 기능을 얹는다.

> **Xcode 26.6 실제 진행 시 발견된 차이점 (2026-08-03):**
> - Xcode 26에는 **`Info.plist` 파일이 생성되지 않는다.** 대신 `project.pbxproj`의 `INFOPLIST_KEY_*` 빌드 설정으로 관리하고 빌드 시 자동 생성한다. 따라서 Step 3은 "Info.plist 편집"이 아니라 앱 타겟 빌드 설정에 `INFOPLIST_KEY_NSCameraUsageDescription`을 추가하는 것으로 대체됐다.
> - 프로젝트 생성 시 **Testing System을 XCTest로 명시 선택**해야 한다(Xcode 26 기본값은 Swift Testing). 이 계획서의 테스트는 전부 `XCTestCase` 기반이다.
> - 신규 프로젝트의 배포 타겟 기본값이 26.5라, 앱뿐 아니라 **프로젝트 레벨/테스트 타겟까지 전부 17.0으로** 내려야 한다(앱만 바꾸면 테스트 타겟이 26.5로 남는다).
> - `SplatForgeUITests` 타겟도 함께 생성된다. Phase 1에서는 사용하지 않지만 그대로 둬도 무방.

- [x] **Step 1: Xcode 프로젝트 생성**

Xcode 실행 → File > New > Project > iOS > App. 설정값:
- Product Name: `SplatForge`
- Interface: SwiftUI
- Language: Swift
- 저장 위치: `/Users/seochanho/repositories/splatforge`

생성 후 프로젝트 네비게이터에서 `SplatForge` 타겟 선택 → General 탭 → Minimum Deployments를 **17.0**으로 설정.

- [ ] **Step 2: 개발자 계정 + 기기 등록** *(미완 — 개발자 모드 미설정. iPhone을 USB로 Mac에 최초 연결해야 설정 앱에 개발자 모드 항목이 나타난다)*

Xcode > Settings > Accounts에서 Apple ID로 로그인(없으면 추가). 무료 개인 계정으로도 기기 빌드 가능(단, 서명 인증서가 7일마다 만료돼서 재빌드 필요 — 계속 불편하면 Apple Developer Program($99/년) 고려).

iPhone에서 설정 > 개인정보 보호 및 보안 > 개발자 모드를 켜고 재시작(iOS 16+ 필수 단계, 안 하면 기기에 앱이 설치되지 않음).

- [x] **Step 3: 카메라 권한 설명 추가** *(Info.plist 파일 대신 `INFOPLIST_KEY_NSCameraUsageDescription` 빌드 설정으로 처리 — 위 박스 참고)*

`Info.plist`에 다음 키 추가 (Xcode의 Info 탭에서 `+` 버튼으로 "Privacy - Camera Usage Description" 검색 후 추가, 또는 소스 코드 보기로 직접 편집):

```xml
<key>NSCameraUsageDescription</key>
<string>물체를 3D로 스캔하기 위해 카메라가 필요합니다.</string>
```

ARKit는 카메라를 사용하므로 이 키가 없으면 앱이 즉시 크래시한다.

- [x] **Step 4: 최소 ARKit 카메라 프리뷰 작성**

`SplatForge/ContentView.swift`:

```swift
import SwiftUI
import ARKit

// ARSCNView는 UIKit 뷰라서 SwiftUI에서 쓰려면 UIViewRepresentable로 감싸야 한다.
// 지금은 동작 확인용 임시 세션만 돌린다 — 실제 캡처 로직은 Task 6/7에서 CaptureSession으로 교체한다.
struct ARCameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        let configuration = ARWorldTrackingConfiguration()
        view.session.run(configuration)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct ContentView: View {
    var body: some View {
        ARCameraPreview()
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
```

`SplatForge/SplatForgeApp.swift`는 Xcode가 이미 만들어준 기본 템플릿을 그대로 사용(`@main struct SplatForgeApp: App { var body: some Scene { WindowGroup { ContentView() } } }` 형태인지만 확인).

- [ ] **Step 5: 실기기에서 빌드 및 확인** *(대기 중 — 개발자 모드 설정 후 진행. 시뮬레이터 빌드는 경고 0건으로 통과 확인함)*

iPhone을 USB로 연결(또는 같은 Wi-Fi에서 무선 연결 설정) → Xcode 상단에서 빌드 대상으로 본인 iPhone 선택 → Cmd+R로 실행. iPhone에서 "이 개발자를 신뢰하시겠습니까" 팝업이 뜨면 설정 > 일반 > VPN 및 기기 관리에서 신뢰 처리.

Expected: 앱이 실행되고 카메라 화면이 실시간으로 보인다. (시뮬레이터로는 절대 확인 불가 — ARKit 미지원)

- [x] **Step 6: Git 저장소에 커밋** *(커밋 2635630. 원격: https://github.com/chanhois/splatforge)*

```bash
cd /Users/seochanho/repositories/splatforge
cat > .gitignore << 'EOF'
xcuserdata/
DerivedData/
*.xcworkspace/xcuserdata/
Pods/
EOF
git add SplatForge.xcodeproj SplatForge/ .gitignore
git commit -m "Add Xcode project with minimal ARKit camera preview"
```

---

### Task 2: PosedFrame 데이터 구조 + CaptureSession 스켈레톤

**Files:**
- Create: `SplatForge/Capture/PosedFrame.swift`
- Create: `SplatForge/Capture/CaptureSession.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `struct PosedFrame { let imagePath: URL; let pose: simd_float4x4; let intrinsics: simd_float3x3; let timestamp: TimeInterval }`
  - `class CaptureSession: NSObject, ObservableObject, ARSessionDelegate` — `var session: ARSession`(읽기 전용 프로퍼티로 노출), `@Published var keyframeCount: Int`, `func start()`, `func stop()`. Task 6에서 실시간 필터링 로직이 추가된다.

- [x] **Step 1: PosedFrame 정의**

`SplatForge/Capture/PosedFrame.swift`:

```swift
import simd
import Foundation

/// 캡처된 한 키프레임: 이미지(디스크에 저장됨) + 그 순간의 카메라 포즈/내부파라미터.
/// 이미지를 메모리에 CVPixelBuffer로 들고 있지 않고 파일 경로만 저장한다 —
/// 수백 프레임이 쌓여도 메모리 부담이 없도록 하기 위함(설계 스펙의 Capture 섹션 참고).
struct PosedFrame {
    let imagePath: URL
    let pose: simd_float4x4       // ARFrame.camera.transform과 동일한 규약: camera-to-world, ARKit는 로컬 -Z가 전방
    let intrinsics: simd_float3x3 // ARFrame.camera.intrinsics
    let timestamp: TimeInterval
}
```

- [x] **Step 2: CaptureSession 스켈레톤 작성 (포즈 로깅만)**

`SplatForge/Capture/CaptureSession.swift`:

```swift
import ARKit
import Combine

/// ARSession을 감싸는 클래스. 이 시점에서는 재구성 로직을 전혀 모르고,
/// ARKit이 주는 프레임을 받아서 콘솔에 찍어보는 것까지만 한다 —
/// 실시간 키프레임 필터링/저장은 Task 6에서 추가된다.
final class CaptureSession: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published private(set) var keyframeCount = 0

    private var frameCounter = 0

    func start() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        session.delegate = self
        session.run(configuration)
    }

    func stop() {
        session.pause()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCounter += 1
        // 30프레임(약 0.5초)마다 한 번씩만 로그 — 매 프레임 찍으면 콘솔이 감당 안 됨
        if frameCounter % 30 == 0 {
            let t = frame.camera.transform.columns.3
            print("frame #\(frameCounter) tracking=\(frame.camera.trackingState) pos=(\(t.x), \(t.y), \(t.z))")
        }
    }
}
```

- [x] **Step 3: ContentView에 연결해서 실기기로 확인** *(코드 작성 + 시뮬레이터 빌드 통과. 실기기 확인은 Step 4에서)*

`SplatForge/ContentView.swift`의 `ARCameraPreview`가 자체 세션을 만들던 걸, `CaptureSession`이 소유한 세션을 쓰도록 바꾼다:

```swift
import SwiftUI
import ARKit

struct ARContainerView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var captureSession = CaptureSession()

    var body: some View {
        ARContainerView(session: captureSession.session)
            .ignoresSafeArea()
            .onAppear { captureSession.start() }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 4: 실기기 실행으로 pose 로그 확인** *(대기 중 — 개발자 모드 필요)*

Cmd+R로 실행 → Xcode 콘솔을 보면서 iPhone을 좌우로 움직여본다.

Expected: `frame #30 tracking=normal pos=(0.01, -0.02, 0.03)` 같은 로그가 계속 찍히고, 폰을 움직이면 `pos` 값이 그에 맞게 변한다. (이게 이 태스크의 "테스트"다 — ARSession 자체는 실기기 없이 단위 테스트하기 어렵다.)

- [x] **Step 5: 커밋** *(6925937)*

```bash
git add SplatForge/Capture/PosedFrame.swift SplatForge/Capture/CaptureSession.swift SplatForge/ContentView.swift
git commit -m "Add PosedFrame struct and CaptureSession pose logging skeleton"
```

---

### Task 3: GeometricKeyframeFilter (baseline/각도 필터링, TDD)

**Files:**
- Create: `SplatForge/Capture/GeometricKeyframeFilter.swift`
- Test: `SplatForgeTests/GeometricKeyframeFilterTests.swift`

**Interfaces:**
- Consumes: `simd_float4x4`, `simd_float3`(순수 simd 타입만, PosedFrame에 의존 안 함 — 포즈만 있으면 테스트 가능하도록)
- Produces: `struct GeometricKeyframeFilter { let minBaselineRatio: Float; let minAngleDegrees: Float; func shouldSelect(candidatePose: simd_float4x4, lastKeyframePose: simd_float4x4?, objectCenter: simd_float3) -> Bool }`

- [x] **Step 1: 실패하는 테스트 작성**

`SplatForgeTests/GeometricKeyframeFilterTests.swift` (아직 `GeometricKeyframeFilter`가 없으므로 컴파일 실패 예상):

```swift
import XCTest
import simd
@testable import SplatForge

final class GeometricKeyframeFilterTests: XCTestCase {
    func test_firstFrame_alwaysSelected() {
        let filter = GeometricKeyframeFilter(minBaselineRatio: 0.05, minAngleDegrees: 5.0)
        let pose = matrix_identity_float4x4
        XCTAssertTrue(filter.shouldSelect(candidatePose: pose, lastKeyframePose: nil, objectCenter: simd_float3(0, 0, -0.5)))
    }

    func test_tinyMovement_rejected() {
        let filter = GeometricKeyframeFilter(minBaselineRatio: 0.05, minAngleDegrees: 5.0)
        let objectCenter = simd_float3(0, 0, -0.5)

        var lastPose = matrix_identity_float4x4
        lastPose.columns.3 = simd_float4(0, 0, 0, 1)

        var candidatePose = matrix_identity_float4x4
        candidatePose.columns.3 = simd_float4(0.001, 0, 0, 1) // 1mm 이동 — object까지 0.5m 대비 매우 작음

        XCTAssertFalse(filter.shouldSelect(candidatePose: candidatePose, lastKeyframePose: lastPose, objectCenter: objectCenter))
    }

    func test_sufficientRotationAroundObject_selected() {
        let filter = GeometricKeyframeFilter(minBaselineRatio: 0.05, minAngleDegrees: 5.0)
        let objectCenter = simd_float3(0, 0, 0)
        let radius: Float = 0.5

        var lastPose = matrix_identity_float4x4
        lastPose.columns.3 = simd_float4(radius, 0, 0, 1) // objectCenter 기준 반경 0.5m 지점, 각도 0도

        let angleRad: Float = 10 * .pi / 180 // 임계값(5도)보다 큰 10도 회전
        var candidatePose = matrix_identity_float4x4
        candidatePose.columns.3 = simd_float4(radius * cos(angleRad), 0, radius * sin(angleRad), 1)

        XCTAssertTrue(filter.shouldSelect(candidatePose: candidatePose, lastKeyframePose: lastPose, objectCenter: objectCenter))
    }
}
```

- [x] **Step 2: 테스트 실패 확인** *(RED 확인: `cannot find 'GeometricKeyframeFilter' in scope`)*

Xcode에서 Cmd+U (또는 Product > Test). `GeometricKeyframeFilter`가 없으므로 빌드 자체가 실패해야 한다.

Expected: FAIL — "Cannot find 'GeometricKeyframeFilter' in scope"

- [x] **Step 3: 최소 구현 작성**

`SplatForge/Capture/GeometricKeyframeFilter.swift`:

```swift
import simd

/// 마지막으로 저장한 키프레임 대비 카메라가 충분히 움직였는지(baseline) 또는
/// 물체 중심 기준으로 충분히 돌았는지(각도)를 판단한다.
/// 절대 거리 대신 "물체까지 거리 대비 비율"로 baseline을 판단하는 이유:
/// 물체가 가까우면 작은 이동도 큰 시차를 만들고, 멀면 그 반대이기 때문.
struct GeometricKeyframeFilter {
    let minBaselineRatio: Float
    let minAngleDegrees: Float

    func shouldSelect(candidatePose: simd_float4x4, lastKeyframePose: simd_float4x4?, objectCenter: simd_float3) -> Bool {
        guard let lastPose = lastKeyframePose else { return true } // 첫 프레임은 항상 채택

        let candidatePos = simd_float3(candidatePose.columns.3.x, candidatePose.columns.3.y, candidatePose.columns.3.z)
        let lastPos = simd_float3(lastPose.columns.3.x, lastPose.columns.3.y, lastPose.columns.3.z)

        let baseline = simd_distance(candidatePos, lastPos)
        let distanceToObject = simd_distance(candidatePos, objectCenter)
        let baselineRatio = distanceToObject > 0 ? baseline / distanceToObject : 0

        let candidateDir = simd_normalize(candidatePos - objectCenter)
        let lastDir = simd_normalize(lastPos - objectCenter)
        let cosAngle = simd_clamp(simd_dot(candidateDir, lastDir), -1, 1)
        let angleDegrees = acos(cosAngle) * 180 / .pi

        return baselineRatio >= minBaselineRatio || angleDegrees >= minAngleDegrees
    }
}
```

- [x] **Step 4: 테스트 통과 확인** *(GREEN: 3개 모두 통과)*

Cmd+U 재실행.

Expected: PASS — 3개 테스트 모두 통과.

- [x] **Step 5: 커밋** *(e72ef77)*

```bash
git add SplatForge/Capture/GeometricKeyframeFilter.swift SplatForgeTests/GeometricKeyframeFilterTests.swift
git commit -m "Add GeometricKeyframeFilter with baseline/angle filtering"
```

---

### Task 4: OpenCV CocoaPods 연동 + Objective-C++ 브릿지 스모크 테스트

**Files:**
- Create: `Podfile`
- Create: `SplatForge/OpenCVWrapper.h`
- Create: `SplatForge/OpenCVWrapper.mm`
- Create: `SplatForge/SplatForge-Bridging-Header.h` (Xcode 자동 생성)
- Test: `SplatForgeTests/OpenCVBridgeTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces: `OpenCVWrapper` (Objective-C 클래스) — `+ (NSString *)openCVVersion;`. 이후 태스크들이 여기에 메서드를 계속 추가한다.

> **실제 진행 시 변경됨 (2026-08-04): CocoaPods → xcframework 직접 빌드**
>
> OpenCV 공식 iOS 배포본(`opencv-4.14.0-ios-framework.zip`)은 `.xcframework`가 아니라 **fat framework**이고, 아키텍처가 `armv7 armv7s x86_64 arm64`다. 여기서 `x86_64`는 인텔 맥 시뮬레이터용이라 **Apple Silicon 시뮬레이터에서 쓸 수 없다** — fat framework는 기기 arm64와 시뮬레이터 arm64를 구분할 수 없기 때문이고, 바로 그 한계 때문에 `.xcframework` 포맷이 존재한다. CocoaPods의 `pod 'OpenCV'`도 같은 바이너리를 쓰므로 문제가 동일하다.
>
> 그래서 **소스에서 직접 xcframework를 빌드**하는 방식으로 전환했다(`scripts/setup-opencv.sh`, Apple Silicon 기준 약 5분). 결과물은 `ios-arm64` + `ios-arm64-simulator` 두 슬라이스를 갖춰 **실기기 없이 시뮬레이터에서 OpenCV 의존 테스트를 돌릴 수 있다** — Task 5/8/9의 TDD가 기기 대기 없이 진행 가능해진다.
>
> 빌드 시 주의점 두 가지:
> - 빌드 스크립트가 `git branch --show-current`로 브랜치명을 읽어서, tarball로 받은 소스(`.git` 없음)에서는 exit 128로 죽는다 → `git init`으로 우회
> - 마지막 "Copying documentation" 단계에서 `docs` 디렉토리가 없어 `FileNotFoundError`로 죽지만, 그 시점엔 xcframework가 이미 완성돼 있다 → 종료 코드 대신 **산출물 존재 여부로 성공을 판정**해야 한다
>
> 산출물 47MB는 커밋하지 않고 `.gitignore`에 넣었다. `Frameworks/opencv2.xcframework`로 설치되며, `pbxproj`에는 링크 + `FRAMEWORK_SEARCH_PATHS` + `SWIFT_OBJC_BRIDGING_HEADER`를 배선했다. **브릿징 헤더는 앱 타겟과 테스트 타겟 양쪽에 지정해야 한다** — 타겟별 설정이라 앱에만 걸면 테스트에서 `OpenCVWrapper`를 못 찾는다.
>
> OpenCV 헤더가 뿜는 `-Wquoted-include-in-framework-header` / `-Wdocumentation` 경고는 서드파티 노이즈라 `CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER=NO`, `CLANG_WARN_DOCUMENTATION_COMMENTS=NO`로 억제했다(우리 코드의 진짜 경고가 묻히지 않도록).
>
> 아래 Step 1~5(CocoaPods 관련)는 **수행하지 않았고**, Step 6부터가 실제로 적용됐다.

- [~] **Step 1: CocoaPods 설치** *(미수행 — xcframework 방식으로 대체)*

```bash
brew install cocoapods
```

Expected: 설치 완료 메시지. (이미 설치돼 있으면 `cocoapods 1.x.x already installed` 류의 메시지)

- [~] **Step 2: Podfile 생성 및 편집** *(미수행)*

```bash
cd /Users/seochanho/repositories/splatforge
pod init
```

생성된 `Podfile`을 열어서 아래 내용으로 교체:

```ruby
platform :ios, '17.0'

target 'SplatForge' do
  use_frameworks!
  pod 'OpenCV', '~> 4.3'

  target 'SplatForgeTests' do
    inherit! :search_paths
  end
end
```

`inherit! :search_paths`가 중요하다 — 이게 없으면 테스트 타겟에서 `OpenCVWrapper`를 쓸 때 "OpenCV 헤더를 못 찾는다"는 링커 에러가 난다(테스트 타겟은 기본적으로 앱 타겟의 Pod를 상속받지 않음).

- [~] **Step 3: pod install 실행** *(미수행 — 대신 `scripts/setup-opencv.sh`)*

```bash
pod install
```

Expected: `Pod installation complete!` 메시지와 함께 `SplatForge.xcworkspace`가 생성됨.

**이 시점부터는 `SplatForge.xcodeproj`가 아니라 `SplatForge.xcworkspace`를 연다.** (Xcode가 이미 `.xcodeproj`로 열려 있으면 닫고 `.xcworkspace`로 다시 열기)

> 만약 `pod install`이 `OpenCV` pod 관련 에러로 실패하면(오래된 pod가 최신 Xcode/iOS SDK와 호환성 문제를 일으킬 수 있음), OpenCV 공식 사이트(opencv.org/releases)에서 `opencv2.xcframework`를 직접 다운로드해서 Xcode 프로젝트에 드래그 앤 드롭하는 방식으로 전환한다 — 이 경우 Podfile/CocoaPods 관련 스텝은 건너뛰고 Step 4부터 이어서 진행.

- [~] **Step 4: Objective-C++ 래퍼 클래스 생성** *(Xcode GUI 불필요 — 파일시스템 동기화 그룹이라 디스크에 만들면 자동 포함)*

Xcode(workspace)에서: File > New > File > Cocoa Touch Class. 이름 `OpenCVWrapper`, Subclass of `NSObject`, Language `Objective-C`. 저장 위치는 `SplatForge/` 폴더.

생성 직후 Xcode가 팝업으로 "Would you like to configure an Objective-C bridging header?"라고 물으면 **Create Bridging Header** 선택 — 이게 `SplatForge-Bridging-Header.h`를 자동 생성해준다.

- [~] **Step 5: .m을 .mm으로 변경** *(해당 없음 — 처음부터 .mm으로 생성)*

프로젝트 네비게이터에서 `OpenCVWrapper.m`을 선택 → 우클릭 > Rename → `OpenCVWrapper.mm`으로 변경.

이유: OpenCV는 C++로 작성돼 있어서 C++ 문법을 쓰려면 파일이 Objective-C++(`.mm`)이어야 한다. 순수 Objective-C(`.m`)에서는 C++ 헤더를 include할 수 없다.

- [x] **Step 6: OpenCVWrapper.h 작성 (Swift에 노출될 순수 Objective-C 인터페이스)**

`SplatForge/OpenCVWrapper.h`:

```objc
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

+ (NSString *)openCVVersion;

@end

NS_ASSUME_NONNULL_END
```

이 헤더에는 C++ 타입을 절대 노출하지 않는다 — Swift가 직접 보는 파일이라, C++ 타입이 섞이면 Swift에서 import가 깨진다. C++는 항상 `.mm` 구현 파일 안에만 숨긴다.

- [x] **Step 7: OpenCVWrapper.mm 작성**

`SplatForge/OpenCVWrapper.mm`:

```objc
#import "OpenCVWrapper.h"
#import <opencv2/opencv.hpp>

@implementation OpenCVWrapper

+ (NSString *)openCVVersion {
    return [NSString stringWithUTF8String:CV_VERSION];
}

@end
```

- [x] **Step 8: 브릿징 헤더에 import 추가** *(+ 앱/테스트 타겟 양쪽에 `SWIFT_OBJC_BRIDGING_HEADER` 설정)*

`SplatForge/SplatForge-Bridging-Header.h` (Xcode가 생성한 파일, 내용이 비어있을 것):

```objc
#import "OpenCVWrapper.h"
```

- [x] **Step 9: 스모크 테스트 작성**

`SplatForgeTests/OpenCVBridgeTests.swift`:

```swift
import XCTest
@testable import SplatForge

final class OpenCVBridgeTests: XCTestCase {
    func test_openCVVersion_isReported() {
        let version = OpenCVWrapper.openCVVersion()
        XCTAssertTrue(version.hasPrefix("4."), "OpenCV 4.x를 기대했지만 \(version)을 받음")
    }
}
```

- [x] **Step 10: 테스트 실행 및 확인** *(PASS — OpenCV 4.14.0, 경고 0건)*

Cmd+U.

Expected: PASS. 만약 "No such module 'opencv2'"류의 에러가 나면 Step 2의 `inherit! :search_paths`가 빠졌거나 `.xcworkspace`가 아니라 `.xcodeproj`를 열고 있는 게 원인일 가능성이 높다.

- [x] **Step 11: 커밋** *(e669688)*

```bash
cat >> .gitignore << 'EOF'
Pods/
*.xcworkspace
EOF
git add Podfile Podfile.lock SplatForge/OpenCVWrapper.h SplatForge/OpenCVWrapper.mm SplatForge/SplatForge-Bridging-Header.h SplatForgeTests/OpenCVBridgeTests.swift .gitignore
git commit -m "Add OpenCV via CocoaPods with Objective-C++ bridge smoke test"
```

---

### Task 5: matFromUIImage 헬퍼 + BlurFilter (Laplacian variance, TDD)

**Files:**
- Modify: `SplatForge/OpenCVWrapper.h`
- Modify: `SplatForge/OpenCVWrapper.mm`
- Test: `SplatForgeTests/BlurFilterTests.swift`

**Interfaces:**
- Consumes: `OpenCVWrapper`(Task 4)
- Produces: `OpenCVWrapper.laplacianVariance(forImage: UIImage) -> Double` (Swift에서 이렇게 보임 — Objective-C 셀렉터 `laplacianVarianceForImage:`를 Swift 임포터가 자동 변환)

> **실제 진행 시 보강됨 (2026-08-10):** 계획서의 최초 `matFromUIImage` 구현은 모든 `UIImage`가 `CGImage` backing을 가진다고 가정했지만, `UIImage(ciImage:)`로 만든 유효한 이미지에서는 `CGImage`가 nil일 수 있다. finite `CIImage`는 `CIContext`로 렌더링하고, backing/color space/bitmap context 생성이 실패하면 빈 Mat을 반환한 뒤 variance `0.0`으로 안전하게 거부하도록 보강했다. CIImage-backed 입력과 backing 없는 입력의 회귀 테스트도 추가했다.

- [x] **Step 1: 실패하는 테스트 작성** *(checkerboard/solid + CIImage-backed + backing 없는 이미지)*

`SplatForgeTests/BlurFilterTests.swift`:

```swift
import XCTest
import UIKit
@testable import SplatForge

final class BlurFilterTests: XCTestCase {
    func test_checkerboardHasHigherVarianceThanSolidColor() {
        let solid = Self.makeTestImage(checkerboard: false)
        let checker = Self.makeTestImage(checkerboard: true)

        let solidVariance = OpenCVWrapper.laplacianVariance(forImage: solid)
        let checkerVariance = OpenCVWrapper.laplacianVariance(forImage: checker)

        XCTAssertGreaterThan(checkerVariance, solidVariance)
    }

    private static func makeTestImage(checkerboard: Bool) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            if !checkerboard {
                UIColor.gray.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            } else {
                for y in stride(from: 0, to: Int(size.height), by: 8) {
                    for x in stride(from: 0, to: Int(size.width), by: 8) {
                        let isBlack = ((x / 8) + (y / 8)) % 2 == 0
                        (isBlack ? UIColor.black : UIColor.white).setFill()
                        context.fill(CGRect(x: x, y: y, width: 8, height: 8))
                    }
                }
            }
        }
    }
}
```

- [x] **Step 2: 테스트 실패 확인** *(RED: API 부재 확인, 보강 RED: 빈 Mat `cvtColor` assertion 확인)*

Cmd+U.

Expected: FAIL — "Type 'OpenCVWrapper' has no member 'laplacianVariance'"

- [x] **Step 3: OpenCVWrapper.h에 메서드 선언 추가** *(`NS_SWIFT_NAME`으로 요구된 Swift selector 보장)*

`SplatForge/OpenCVWrapper.h`을 다음으로 교체(기존 `openCVVersion` 선언 유지하고 추가):

```objc
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

+ (NSString *)openCVVersion;
+ (double)laplacianVarianceForImage:(UIImage *)image;

@end

NS_ASSUME_NONNULL_END
```

- [x] **Step 4: OpenCVWrapper.mm에 UIImage↔cv::Mat 변환 헬퍼 + 구현 추가** *(CIImage/failure 처리 보강 포함)*

`SplatForge/OpenCVWrapper.mm`을 다음으로 교체:

```objc
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
```

- [x] **Step 5: 테스트 통과 확인** *(GREEN: 전체 XCTest 9개 Passed)*

Cmd+U.

Expected: PASS.

- [x] **Step 6: 커밋** *(b28ef21, 보강 0f0a33c)*

```bash
git add SplatForge/OpenCVWrapper.h SplatForge/OpenCVWrapper.mm SplatForgeTests/BlurFilterTests.swift
git commit -m "Add Laplacian-variance blur detection via OpenCV"
```

---

### Task 6: KeyframeSelector 통합 + 실시간 캡처 루프 + 디스크 저장

**Files:**
- Create: `SplatForge/Extensions/CVPixelBuffer+UIImage.swift`
- Create: `SplatForge/Capture/KeyframeSelector.swift`
- Modify: `SplatForge/Capture/CaptureSession.swift`
- Test: `SplatForgeTests/KeyframeSelectorStateTests.swift`

**Interfaces:**
- Consumes: `GeometricKeyframeFilter`(Task 3), `OpenCVWrapper.laplacianVariance(forImage:)`(Task 5), `PosedFrame`(Task 2)
- Produces:
  - `CVPixelBuffer.toUIImage() -> UIImage`
  - `class KeyframeSelector { func passesGeometricFilter(pose: simd_float4x4, trackingState: ARCamera.TrackingState) -> Bool; func passesBlurFilter(image: UIImage) -> Bool; func commit(pose: simd_float4x4) }`
  - `CaptureSession.keyframes: [PosedFrame]` (캡처 종료 후 Task 10에서 사용)

- [ ] **Step 1: CVPixelBuffer -> UIImage 변환 익스텐션 작성**

`SplatForge/Extensions/CVPixelBuffer+UIImage.swift`:

```swift
import CoreImage
import UIKit

extension CVPixelBuffer {
    /// ARFrame.capturedImage는 YCbCr 4:2:0 포맷이라 그대로 못 쓴다.
    /// CIImage는 이 포맷을 이해하므로, CIContext를 거쳐 표준 RGB CGImage/UIImage로 변환한다.
    func toUIImage() -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: self)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            preconditionFailure("CVPixelBuffer를 CGImage로 변환 실패")
        }
        return UIImage(cgImage: cgImage)
    }
}
```

- [ ] **Step 2: objectCenter 추정 로직을 포함한 KeyframeSelector 실패 테스트 작성**

`SplatForgeTests/KeyframeSelectorStateTests.swift`:

```swift
import XCTest
import ARKit
import simd
@testable import SplatForge

final class KeyframeSelectorStateTests: XCTestCase {
    func test_secondEvaluation_rejectedUntilFirstCommitted() {
        let selector = KeyframeSelector()

        var pose = matrix_identity_float4x4
        pose.columns.3 = simd_float4(0, 0, 0, 1)

        // 첫 평가: lastKeyframePose가 없으므로 항상 채택
        XCTAssertTrue(selector.passesGeometricFilter(pose: pose, trackingState: .normal))

        // commit 전이므로 여전히 "첫 프레임" 취급 -> 같은 포즈라도 true
        XCTAssertTrue(selector.passesGeometricFilter(pose: pose, trackingState: .normal))

        selector.commit(pose: pose)

        // commit 이후, 같은 포즈로 재평가하면 이동량이 0이라 false여야 함
        XCTAssertFalse(selector.passesGeometricFilter(pose: pose, trackingState: .normal))
    }

    func test_limitedTracking_alwaysRejected() {
        let selector = KeyframeSelector()
        var pose = matrix_identity_float4x4
        pose.columns.3 = simd_float4(1, 0, 0, 1) // 충분히 먼 포즈라도

        XCTAssertFalse(selector.passesGeometricFilter(pose: pose, trackingState: .limited(.excessiveMotion)))
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Cmd+U. Expected: FAIL — `KeyframeSelector`가 없음.

- [ ] **Step 4: KeyframeSelector 구현**

`SplatForge/Capture/KeyframeSelector.swift`:

```swift
import ARKit
import simd
import UIKit

/// 캡처 중 실시간으로 "이 프레임을 키프레임으로 저장할지"를 결정한다.
/// 순서가 중요하다: 트래킹 상태 -> 기하학적 필터(싸다) -> 블러 필터(UIImage 변환 + OpenCV 호출, 비쌈) 순으로
/// 저렴한 체크부터 하고, 통과한 후보에 대해서만 비싼 연산을 수행한다.
final class KeyframeSelector {
    private let geometricFilter: GeometricKeyframeFilter
    private let blurVarianceThreshold: Double
    private let assumedObjectDistance: Float

    private var lastKeyframePose: simd_float4x4?
    private var objectCenter: simd_float3?

    init(geometricFilter: GeometricKeyframeFilter = GeometricKeyframeFilter(minBaselineRatio: 0.05, minAngleDegrees: 5.0),
         blurVarianceThreshold: Double = 50.0,
         assumedObjectDistance: Float = 0.3) {
        self.geometricFilter = geometricFilter
        self.blurVarianceThreshold = blurVarianceThreshold
        self.assumedObjectDistance = assumedObjectDistance
    }

    func passesGeometricFilter(pose: simd_float4x4, trackingState: ARCamera.TrackingState) -> Bool {
        guard case .normal = trackingState else { return false }

        if objectCenter == nil {
            // 캡처 시작 시점 카메라가 바라보는 방향으로 assumedObjectDistance만큼 앞을 물체 중심으로 가정.
            objectCenter = Self.estimateObjectCenter(fromCameraPose: pose, distance: assumedObjectDistance)
        }
        return geometricFilter.shouldSelect(candidatePose: pose, lastKeyframePose: lastKeyframePose, objectCenter: objectCenter!)
    }

    func passesBlurFilter(image: UIImage) -> Bool {
        OpenCVWrapper.laplacianVariance(forImage: image) >= blurVarianceThreshold
    }

    func commit(pose: simd_float4x4) {
        lastKeyframePose = pose
    }

    /// ARKit 카메라는 로컬 -Z를 바라본다(OpenGL/SceneKit과 동일한 규약).
    /// world-space forward = -(회전행렬의 3번째 열) = -pose.columns.2
    static func estimateObjectCenter(fromCameraPose pose: simd_float4x4, distance: Float) -> simd_float3 {
        let forward = -simd_float3(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z)
        let position = simd_float3(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
        return position + forward * distance
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Cmd+U. Expected: PASS.

- [ ] **Step 6: CaptureSession에 실시간 필터링 + 디스크 저장 연결**

`SplatForge/Capture/CaptureSession.swift`을 다음으로 교체:

```swift
import ARKit
import Combine

final class CaptureSession: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published private(set) var keyframeCount = 0

    private(set) var keyframes: [PosedFrame] = []
    private let keyframeSelector = KeyframeSelector()
    private let storageDirectory: URL

    override init() {
        storageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        super.init()
    }

    func start() {
        keyframes.removeAll()
        keyframeCount = 0
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        session.delegate = self
        session.run(configuration)
    }

    func stop() {
        session.pause()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 1. 싼 체크 먼저: 트래킹 상태 + baseline/각도 (이미지 변환 없이 pose만으로 판단)
        guard keyframeSelector.passesGeometricFilter(pose: frame.camera.transform, trackingState: frame.camera.trackingState) else {
            return
        }

        // 2. 비싼 체크: YCbCr -> RGB 변환 후 OpenCV로 블러 판정
        let image = frame.capturedImage.toUIImage()
        guard keyframeSelector.passesBlurFilter(image: image) else {
            return
        }

        keyframeSelector.commit(pose: frame.camera.transform)

        // 3. 디스크에 저장 (메모리에는 pose/intrinsics/경로만 남긴다)
        let imageURL = storageDirectory.appendingPathComponent("frame-\(keyframes.count).jpg")
        if let jpegData = image.jpegData(compressionQuality: 0.9) {
            try? jpegData.write(to: imageURL)
        }

        let posedFrame = PosedFrame(imagePath: imageURL, pose: frame.camera.transform,
                                     intrinsics: frame.camera.intrinsics, timestamp: frame.timestamp)
        keyframes.append(posedFrame)
        keyframeCount = keyframes.count
        print("키프레임 #\(keyframes.count) 저장: \(imageURL.path)")
    }
}
```

`storageDirectory`가 매 실행마다 랜덤 UUID 폴더라 Finder에서 직접 찾아가긴 번거롭다 — 대신 이 `print`로 콘솔에서 바로 정확한 경로를 확인한다(Step 7 참고).

- [ ] **Step 7: 실기기로 통합 확인**

Cmd+R로 실행 → 아무 물체(머그컵 등)를 앞에 두고 천천히 주위를 돈다.

Expected: 앱 UI는 아직 카운터를 안 보여주지만(Task 7에서 추가), Xcode 콘솔에 "키프레임 #1 저장: /path/to/frame-0.jpg", "키프레임 #2 저장: ..."처럼 계속 로그가 찍힌다. 찍힌 경로 중 하나를 그대로 Finder의 "이동 > 폴더로 이동"(Cmd+Shift+G)에 붙여넣으면 실제 JPEG 파일이 저장돼 있는 걸 확인할 수 있다.

- [ ] **Step 8: 커밋**

```bash
git add SplatForge/Extensions/CVPixelBuffer+UIImage.swift SplatForge/Capture/KeyframeSelector.swift SplatForge/Capture/CaptureSession.swift SplatForgeTests/KeyframeSelectorStateTests.swift
git commit -m "Wire real-time keyframe filtering and disk streaming into CaptureSession"
```

---

### Task 7: 캡처 UI (시작/종료 버튼 + 키프레임 카운터)

**Files:**
- Modify: `SplatForge/ContentView.swift`
- Create: `SplatForge/Capture/CaptureView.swift`

**Interfaces:**
- Consumes: `CaptureSession`(Task 6)
- Produces: `CaptureView` — 캡처가 끝나면 `onCaptureFinished: ([PosedFrame]) -> Void` 콜백으로 완료된 키프레임 배열을 넘긴다(Task 11에서 이 콜백을 재구성 파이프라인 실행에 연결).

- [ ] **Step 1: ARContainerView를 ContentView.swift에서 CaptureView.swift로 이동**

`ARContainerView`는 Task 2 Step 3에서 `ContentView.swift`에 정의했다. 다음 Step 2에서 `ContentView.swift`를 완전히 새 내용으로 교체하면서 이 정의가 사라지므로, 여기서 먼저 `CaptureView.swift`로 옮겨준다 — **`ContentView.swift`에 있는 기존 `ARContainerView` 구조체 정의는 잘라내고(삭제)**, 아래처럼 `CaptureView.swift`에 붙여넣는다. (Step 2를 마치기 전까지 두 파일에 동시에 존재하면 "invalid redeclaration" 컴파일 에러가 나므로, 반드시 Step 1과 Step 2를 함께 끝낸 뒤에 빌드할 것.)

`SplatForge/Capture/CaptureView.swift`:

```swift
import SwiftUI
import ARKit

struct ARContainerView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct CaptureView: View {
    @StateObject private var captureSession = CaptureSession()
    @State private var isCapturing = false
    var onCaptureFinished: ([PosedFrame]) -> Void

    private let targetKeyframeCount = 50

    var body: some View {
        ZStack(alignment: .bottom) {
            ARContainerView(session: captureSession.session)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("\(captureSession.keyframeCount) / \(targetKeyframeCount) 키프레임")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

                Button(isCapturing ? "촬영 종료" : "촬영 시작") {
                    toggleCapture()
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 32)
            }
        }
        .onChange(of: captureSession.keyframeCount) { _, newCount in
            if isCapturing && newCount >= targetKeyframeCount {
                toggleCapture()
            }
        }
    }

    private func toggleCapture() {
        if isCapturing {
            captureSession.stop()
            onCaptureFinished(captureSession.keyframes)
        } else {
            captureSession.start()
        }
        isCapturing.toggle()
    }
}
```

- [ ] **Step 2: ContentView를 CaptureView 진입점으로 교체**

`SplatForge/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        CaptureView { keyframes in
            print("캡처 완료: \(keyframes.count)개 키프레임")
            // Task 11에서 여기를 재구성 파이프라인 호출로 교체한다.
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 3: 실기기로 확인**

Cmd+R. 물체 주위를 돌면서 카운터가 올라가는지, 50개 도달 시(또는 버튼으로 수동 종료 시) "촬영 종료"로 바뀌고 콘솔에 "캡처 완료: N개 키프레임"이 찍히는지 확인.

Expected: 화면에 실시간 카운터가 보이고, 종료 시 콘솔 로그가 찍힌다.

- [ ] **Step 4: 커밋**

```bash
git add SplatForge/ContentView.swift SplatForge/Capture/CaptureView.swift
git commit -m "Add capture UI with start/stop button and keyframe counter"
```

---

### Task 8: Feature Detection + Matching (OpenCV ORB, TDD)

**Files:**
- Modify: `SplatForge/OpenCVWrapper.h`
- Modify: `SplatForge/OpenCVWrapper.mm`
- Test: `SplatForgeTests/FeatureMatchingTests.swift`

**Interfaces:**
- Consumes: `matFromUIImage`(Task 5, 내부 헬퍼)
- Produces:
  - Objective-C: `@interface FeatureMatchResult : NSObject @property NSArray<NSValue *> *points1; @property NSArray<NSValue *> *points2; @end`
  - `+ (FeatureMatchResult *)matchFeaturesBetween:(UIImage *)image1 and:(UIImage *)image2;` → Swift: `OpenCVWrapper.matchFeatures(between:and:) -> FeatureMatchResult`
  - `points1[i]`와 `points2[i]`(둘 다 `NSValue(CGPoint)`)는 서로 매칭된 대응점 쌍이다.

- [ ] **Step 1: 실패하는 테스트 작성**

`SplatForgeTests/FeatureMatchingTests.swift`:

```swift
import XCTest
import UIKit
@testable import SplatForge

final class FeatureMatchingTests: XCTestCase {
    func test_translatedPattern_findsConsistentMatches() {
        let base = Self.makePatternImage(offset: .zero)
        let shifted = Self.makePatternImage(offset: CGPoint(x: 10, y: 6))

        let result = OpenCVWrapper.matchFeatures(between: base, and: shifted)

        XCTAssertGreaterThan(result.points1.count, 10, "충분한 매칭이 나와야 함")
        XCTAssertEqual(result.points1.count, result.points2.count)

        let dxs = zip(result.points1, result.points2).map { $0.1.cgPointValue.x - $0.0.cgPointValue.x }
        let averageDx = dxs.reduce(0, +) / CGFloat(dxs.count)
        XCTAssertEqual(averageDx, 10, accuracy: 2.0)
    }

    private static func makePatternImage(offset: CGPoint) -> UIImage {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let rects: [(CGRect, UIColor)] = [
                (CGRect(x: 20, y: 20, width: 30, height: 30), .red),
                (CGRect(x: 80, y: 40, width: 25, height: 40), .blue),
                (CGRect(x: 130, y: 100, width: 35, height: 25), .green),
                (CGRect(x: 40, y: 130, width: 28, height: 28), .orange),
                (CGRect(x: 150, y: 20, width: 20, height: 50), .purple)
            ]
            for (rect, color) in rects {
                color.setFill()
                context.fill(rect.offsetBy(dx: offset.x, dy: offset.y))
            }
        }
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Cmd+U. Expected: FAIL — `matchFeatures`가 없음.

- [ ] **Step 3: OpenCVWrapper.h에 선언 추가**

`SplatForge/OpenCVWrapper.h`을 다음으로 교체:

```objc
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FeatureMatchResult : NSObject
@property (nonatomic, strong) NSArray<NSValue *> *points1;
@property (nonatomic, strong) NSArray<NSValue *> *points2;
@end

@interface OpenCVWrapper : NSObject

+ (NSString *)openCVVersion;
+ (double)laplacianVarianceForImage:(UIImage *)image;
+ (FeatureMatchResult *)matchFeaturesBetween:(UIImage *)image1 and:(UIImage *)image2;

@end

NS_ASSUME_NONNULL_END
```

- [ ] **Step 4: OpenCVWrapper.mm에 구현 추가**

`SplatForge/OpenCVWrapper.mm`에 `@implementation OpenCVWrapper ... @end` 블록 안, 기존 메서드들 뒤에 추가하고 파일 맨 위에 `@implementation FeatureMatchResult @end`를 넣는다. 전체 파일:

```objc
#import "OpenCVWrapper.h"
#import <opencv2/opencv.hpp>

@implementation FeatureMatchResult
@end

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
    return stddev[0] * stddev[0];
}

+ (FeatureMatchResult *)matchFeaturesBetween:(UIImage *)image1 and:(UIImage *)image2 {
    cv::Mat gray1, gray2;
    cv::cvtColor(matFromUIImage(image1), gray1, cv::COLOR_RGBA2GRAY);
    cv::cvtColor(matFromUIImage(image2), gray2, cv::COLOR_RGBA2GRAY);

    cv::Ptr<cv::ORB> orb = cv::ORB::create(2000);
    std::vector<cv::KeyPoint> keypoints1, keypoints2;
    cv::Mat descriptors1, descriptors2;
    orb->detectAndCompute(gray1, cv::noArray(), keypoints1, descriptors1);
    orb->detectAndCompute(gray2, cv::noArray(), keypoints2, descriptors2);

    FeatureMatchResult *result = [FeatureMatchResult new];

    if (descriptors1.empty() || descriptors2.empty()) {
        result.points1 = @[];
        result.points2 = @[];
        return result;
    }

    cv::BFMatcher matcher(cv::NORM_HAMMING); // ORB는 이진 디스크립터이므로 해밍 거리 사용
    std::vector<std::vector<cv::DMatch>> knnMatches;
    matcher.knnMatch(descriptors1, descriptors2, knnMatches, 2);

    NSMutableArray<NSValue *> *points1 = [NSMutableArray array];
    NSMutableArray<NSValue *> *points2 = [NSMutableArray array];

    for (auto &match : knnMatches) {
        if (match.size() < 2) continue;
        // Lowe's ratio test: 가장 가까운 매칭이 두 번째로 가까운 매칭보다 뚜렷하게 좋아야 신뢰
        if (match[0].distance < 0.75f * match[1].distance) {
            cv::Point2f p1 = keypoints1[match[0].queryIdx].pt;
            cv::Point2f p2 = keypoints2[match[0].trainIdx].pt;
            [points1 addObject:[NSValue valueWithCGPoint:CGPointMake(p1.x, p1.y)]];
            [points2 addObject:[NSValue valueWithCGPoint:CGPointMake(p2.x, p2.y)]];
        }
    }

    result.points1 = points1;
    result.points2 = points2;
    return result;
}

@end
```

- [ ] **Step 5: 테스트 통과 확인**

Cmd+U. Expected: PASS. (색깔 사각형 패턴이라 ORB가 모서리를 특징점으로 잘 잡아낸다 — 만약 매칭 수가 10개 미만으로 나오면 `rects` 배열에 사각형을 몇 개 더 추가해서 텍스처를 늘린다.)

- [ ] **Step 6: 커밋**

```bash
git add SplatForge/OpenCVWrapper.h SplatForge/OpenCVWrapper.mm SplatForgeTests/FeatureMatchingTests.swift
git commit -m "Add ORB feature detection and matching via OpenCV"
```

---

### Task 9: ProjectionMath + Triangulation (synthetic ground-truth TDD)

이 태스크가 파이프라인의 수학적 핵심이다. **중요한 규약 하나를 먼저 짚는다**: ARKit 카메라는 로컬 **-Z**를 바라본다(OpenGL/SceneKit 관례). 반면 표준 핀홀 투영 공식(`u = fx·X/Z + cx`)은 물체가 카메라 앞에 있을 때 Z가 **양수**라고 가정한다. 그래서 `ARCamera.transform`으로 만든 world-to-camera 변환을 그대로 `ARCamera.intrinsics`에 넣으면 부호가 안 맞는다 — 카메라 공간으로 옮긴 뒤 Z축 부호를 뒤집어서 보정해야 한다. 아래 구현은 이 보정을 반영한다.

**Files:**
- Create: `SplatForge/Reconstruction/ProjectionMath.swift`
- Modify: `SplatForge/OpenCVWrapper.h`
- Modify: `SplatForge/OpenCVWrapper.mm`
- Test: `SplatForgeTests/ProjectionMathTests.swift`
- Test: `SplatForgeTests/TriangulationTests.swift`

**Interfaces:**
- Consumes: 없음(순수 수학 + OpenCV)
- Produces:
  - `enum ProjectionMath { static func projectionMatrixRowMajor(cameraToWorldPose: simd_float4x4, intrinsics: simd_float3x3) -> [Float]` (12개 원소, row-major 3x4)
  - `static func project(worldPoint: simd_float3, pose: simd_float4x4, intrinsics: simd_float3x3) -> (pixel: CGPoint, isInFrontOfCamera: Bool) }`
  - Objective-C: `@interface TriangulatedPoint : NSObject @property float x, y, z; @end` / `+ (NSArray<TriangulatedPoint *> *)triangulateWithProjection1:points1:projection2:points2:` → Swift: `OpenCVWrapper.triangulate(withProjection1:points1:projection2:points2:) -> [TriangulatedPoint]`

- [ ] **Step 1: ProjectionMath 실패 테스트 작성**

`SplatForgeTests/ProjectionMathTests.swift`:

```swift
import XCTest
import simd
@testable import SplatForge

final class ProjectionMathTests: XCTestCase {
    func test_identityPose_producesExpectedProjectionMatrix() {
        let pose = matrix_identity_float4x4
        let intrinsics = simd_float3x3(
            simd_float3(500, 0, 0),
            simd_float3(0, 500, 0),
            simd_float3(320, 240, 1)
        ) // fx=fy=500, principal point (320, 240)

        let p = ProjectionMath.projectionMatrixRowMajor(cameraToWorldPose: pose, intrinsics: intrinsics)

        XCTAssertEqual(p.count, 12)
        XCTAssertEqual(p[0], 500, accuracy: 1e-4)   // fx
        XCTAssertEqual(p[2], 320, accuracy: 1e-4)   // px
        XCTAssertEqual(p[5], 500, accuracy: 1e-4)   // fy
        XCTAssertEqual(p[6], 240, accuracy: 1e-4)   // py
        XCTAssertEqual(p[10], -1, accuracy: 1e-4)   // -Z 보정 반영
    }

    func test_pointInFrontOfCamera_isDetected() {
        let pose = matrix_identity_float4x4
        let intrinsics = simd_float3x3(
            simd_float3(500, 0, 0), simd_float3(0, 500, 0), simd_float3(320, 240, 1)
        )
        // 카메라는 -Z를 바라보므로 "앞쪽"은 world Z가 음수인 지점
        let (_, isInFront) = ProjectionMath.project(worldPoint: simd_float3(0, 0, -1), pose: pose, intrinsics: intrinsics)
        XCTAssertTrue(isInFront)

        let (_, isBehind) = ProjectionMath.project(worldPoint: simd_float3(0, 0, 1), pose: pose, intrinsics: intrinsics)
        XCTAssertFalse(isBehind)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Cmd+U. Expected: FAIL — `ProjectionMath`가 없음.

- [ ] **Step 3: ProjectionMath 구현**

`SplatForge/Reconstruction/ProjectionMath.swift`:

```swift
import simd
import CoreGraphics

enum ProjectionMath {
    /// world-to-camera 변환에 ARKit의 -Z-forward 규약을 표준 핀홀(양의 Z가 전방) 규약으로
    /// 보정해서 K*[R|t] 투영행렬을 row-major 12개 값(3x4)으로 반환한다.
    static func projectionMatrixRowMajor(cameraToWorldPose pose: simd_float4x4, intrinsics: simd_float3x3) -> [Float] {
        let m = pose.inverse // world-to-camera

        // [R|t]의 3번째 행(Z)에 -1을 곱해서 "카메라 앞쪽 = 양의 Z" 규약으로 바꾼다.
        let rt: [[Float]] = [
            [ m.columns.0.x,  m.columns.1.x,  m.columns.2.x,  m.columns.3.x],
            [ m.columns.0.y,  m.columns.1.y,  m.columns.2.y,  m.columns.3.y],
            [-m.columns.0.z, -m.columns.1.z, -m.columns.2.z, -m.columns.3.z]
        ]

        let k: [[Float]] = [
            [intrinsics.columns.0.x, intrinsics.columns.1.x, intrinsics.columns.2.x],
            [intrinsics.columns.0.y, intrinsics.columns.1.y, intrinsics.columns.2.y],
            [intrinsics.columns.0.z, intrinsics.columns.1.z, intrinsics.columns.2.z]
        ]

        var p = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 3)
        for row in 0..<3 {
            for col in 0..<4 {
                var sum: Float = 0
                for i in 0..<3 { sum += k[row][i] * rt[i][col] }
                p[row][col] = sum
            }
        }
        return p.flatMap { $0 }
    }

    /// world 좌표계의 3D 점을 픽셀 좌표로 투영. 카메라 앞쪽 여부도 함께 반환한다
    /// (뒤쪽 점을 재구성/매칭에 잘못 쓰지 않도록 호출부에서 반드시 체크할 것).
    static func project(worldPoint: simd_float3, pose: simd_float4x4, intrinsics: simd_float3x3) -> (pixel: CGPoint, isInFrontOfCamera: Bool) {
        let worldToCamera = pose.inverse
        let p4 = simd_float4(worldPoint.x, worldPoint.y, worldPoint.z, 1)
        let camPoint4 = worldToCamera * p4

        let isInFront = camPoint4.z < 0 // ARKit 카메라는 로컬 -Z를 바라봄
        let correctedZ = -camPoint4.z
        let camPoint = simd_float3(camPoint4.x, camPoint4.y, correctedZ)
        let projected = intrinsics * camPoint

        let pixel = CGPoint(x: CGFloat(projected.x / projected.z), y: CGFloat(projected.y / projected.z))
        return (pixel, isInFront)
    }
}
```

- [ ] **Step 4: ProjectionMath 테스트 통과 확인**

Cmd+U. Expected: PASS.

- [ ] **Step 5: Triangulation 실패 테스트 작성**

`SplatForgeTests/TriangulationTests.swift`:

```swift
import XCTest
import simd
@testable import SplatForge

final class TriangulationTests: XCTestCase {
    func test_knownPoint_recoveredWithinTolerance() {
        let pose1 = matrix_identity_float4x4
        var pose2 = matrix_identity_float4x4
        pose2.columns.3 = simd_float4(0.1, 0, 0, 1) // 카메라 2는 X축으로 10cm 이동 (baseline)

        let intrinsics = simd_float3x3(
            simd_float3(500, 0, 0), simd_float3(0, 500, 0), simd_float3(320, 240, 1)
        )

        // 카메라는 -Z를 바라보므로, "1m 앞, 살짝 오른쪽 위"는 world 기준 Z가 음수인 지점
        let knownPoint = simd_float3(0.02, 0.01, -1.0)

        let (pixel1, front1) = ProjectionMath.project(worldPoint: knownPoint, pose: pose1, intrinsics: intrinsics)
        let (pixel2, front2) = ProjectionMath.project(worldPoint: knownPoint, pose: pose2, intrinsics: intrinsics)
        XCTAssertTrue(front1)
        XCTAssertTrue(front2)

        let p1 = ProjectionMath.projectionMatrixRowMajor(cameraToWorldPose: pose1, intrinsics: intrinsics)
        let p2 = ProjectionMath.projectionMatrixRowMajor(cameraToWorldPose: pose2, intrinsics: intrinsics)

        let results = OpenCVWrapper.triangulate(withProjection1: p1.map { NSNumber(value: $0) },
                                                  points1: [NSValue(cgPoint: pixel1)],
                                                  projection2: p2.map { NSNumber(value: $0) },
                                                  points2: [NSValue(cgPoint: pixel2)])

        XCTAssertEqual(results.count, 1)
        let recovered = results[0]
        XCTAssertEqual(recovered.x, knownPoint.x, accuracy: 0.001)
        XCTAssertEqual(recovered.y, knownPoint.y, accuracy: 0.001)
        XCTAssertEqual(recovered.z, knownPoint.z, accuracy: 0.001)
    }
}
```

- [ ] **Step 6: 테스트 실패 확인**

Cmd+U. Expected: FAIL — `triangulate(withProjection1:...)`가 없음.

- [ ] **Step 7: OpenCVWrapper.h에 선언 추가**

`SplatForge/OpenCVWrapper.h`에 `FeatureMatchResult` 인터페이스 뒤, `OpenCVWrapper` 인터페이스 안에 추가:

```objc
@interface TriangulatedPoint : NSObject
@property (nonatomic) float x;
@property (nonatomic) float y;
@property (nonatomic) float z;
@end

@interface OpenCVWrapper : NSObject

+ (NSString *)openCVVersion;
+ (double)laplacianVarianceForImage:(UIImage *)image;
+ (FeatureMatchResult *)matchFeaturesBetween:(UIImage *)image1 and:(UIImage *)image2;
+ (NSArray<TriangulatedPoint *> *)triangulateWithProjection1:(NSArray<NSNumber *> *)projection1
                                                       points1:(NSArray<NSValue *> *)points1
                                                   projection2:(NSArray<NSNumber *> *)projection2
                                                       points2:(NSArray<NSValue *> *)points2;

@end
```

(전체 파일 구조는 `TriangulatedPoint`/`FeatureMatchResult` 두 인터페이스가 `OpenCVWrapper` 인터페이스보다 위에 오도록 배치)

- [ ] **Step 8: OpenCVWrapper.mm에 구현 추가**

`SplatForge/OpenCVWrapper.mm` 맨 위(다른 `@implementation`들 앞)에 `@implementation TriangulatedPoint @end` 추가, `@implementation OpenCVWrapper` 블록의 `matchFeaturesBetween:and:` 뒤에 추가:

```objc
+ (NSArray<TriangulatedPoint *> *)triangulateWithProjection1:(NSArray<NSNumber *> *)projection1
                                                       points1:(NSArray<NSValue *> *)points1
                                                   projection2:(NSArray<NSNumber *> *)projection2
                                                       points2:(NSArray<NSValue *> *)points2 {
    cv::Mat P1(3, 4, CV_64F);
    cv::Mat P2(3, 4, CV_64F);
    for (int i = 0; i < 12; i++) {
        P1.at<double>(i / 4, i % 4) = projection1[i].doubleValue;
        P2.at<double>(i / 4, i % 4) = projection2[i].doubleValue;
    }

    std::vector<cv::Point2f> pts1, pts2;
    for (NSValue *v in points1) {
        CGPoint p = v.CGPointValue;
        pts1.push_back(cv::Point2f(p.x, p.y));
    }
    for (NSValue *v in points2) {
        CGPoint p = v.CGPointValue;
        pts2.push_back(cv::Point2f(p.x, p.y));
    }

    cv::Mat points4D;
    cv::triangulatePoints(P1, P2, pts1, pts2, points4D);

    // triangulatePoints의 출력 타입이 항상 CV_64F로 보장되지 않으므로,
    // 명시적으로 변환해서 어떤 내부 타입이든 안전하게 읽는다.
    cv::Mat points4Ddouble;
    points4D.convertTo(points4Ddouble, CV_64F);

    NSMutableArray<TriangulatedPoint *> *result = [NSMutableArray array];
    for (int i = 0; i < points4Ddouble.cols; i++) {
        double w = points4Ddouble.at<double>(3, i);
        if (fabs(w) < 1e-9) continue;
        TriangulatedPoint *tp = [TriangulatedPoint new];
        tp.x = static_cast<float>(points4Ddouble.at<double>(0, i) / w);
        tp.y = static_cast<float>(points4Ddouble.at<double>(1, i) / w);
        tp.z = static_cast<float>(points4Ddouble.at<double>(2, i) / w);
        [result addObject:tp];
    }
    return result;
}
```

- [ ] **Step 9: 테스트 통과 확인**

Cmd+U. Expected: PASS — 이게 파이프라인 전체에서 가장 중요한 테스트다. 실패하면 `-Z` 보정 부분(Step 3)을 다시 확인.

- [ ] **Step 10: 커밋**

```bash
git add SplatForge/Reconstruction/ProjectionMath.swift SplatForge/OpenCVWrapper.h SplatForge/OpenCVWrapper.mm SplatForgeTests/ProjectionMathTests.swift SplatForgeTests/TriangulationTests.swift
git commit -m "Add projection math and OpenCV triangulation with synthetic ground-truth tests"
```

---

### Task 10: SparseReconstructor + PLYExporter (조립 + outlier 제거 + 내보내기)

**Files:**
- Create: `SplatForge/Reconstruction/SparsePoint3D.swift`
- Create: `SplatForge/Reconstruction/SparseReconstructor.swift`
- Create: `SplatForge/Reconstruction/PLYExporter.swift`
- Test: `SplatForgeTests/PLYExporterTests.swift`

**Interfaces:**
- Consumes: `PosedFrame`(Task 2), `OpenCVWrapper.matchFeatures`(Task 8), `ProjectionMath`/`OpenCVWrapper.triangulate`(Task 9)
- Produces:
  - `struct SparsePoint3D { let position: simd_float3; let color: SIMD3<UInt8> }`
  - `enum SparseReconstructor { static func reconstruct(keyframes: [PosedFrame], neighborWindow: Int = 3) -> [SparsePoint3D] }`
  - `enum PLYExporter { static func write(points: [SparsePoint3D], to url: URL) throws }`

- [ ] **Step 1: SparsePoint3D 정의**

`SplatForge/Reconstruction/SparsePoint3D.swift`:

```swift
import simd

struct SparsePoint3D {
    let position: simd_float3
    let color: SIMD3<UInt8>
}
```

- [ ] **Step 2: PLYExporter 실패 테스트 작성**

`SplatForgeTests/PLYExporterTests.swift`:

```swift
import XCTest
import simd
@testable import SplatForge

final class PLYExporterTests: XCTestCase {
    func test_writesReadableAsciiPLY() throws {
        let points = [
            SparsePoint3D(position: simd_float3(1, 2, 3), color: SIMD3<UInt8>(255, 0, 0)),
            SparsePoint3D(position: simd_float3(-1, 0.5, 2), color: SIMD3<UInt8>(0, 255, 0))
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).ply")

        try PLYExporter.write(points: points, to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("element vertex 2"))
        XCTAssertTrue(content.contains("1.0 2.0 3.0 255 0 0"))
    }
}
```

- [ ] **Step 3: 테스트 실패 확인 후 PLYExporter 구현**

`SplatForge/Reconstruction/PLYExporter.swift`:

```swift
import Foundation

enum PLYExporter {
    static func write(points: [SparsePoint3D], to url: URL) throws {
        var content = """
        ply
        format ascii 1.0
        element vertex \(points.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """
        for point in points {
            content += "\(point.position.x) \(point.position.y) \(point.position.z) \(point.color.x) \(point.color.y) \(point.color.z)\n"
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

Cmd+U로 통과 확인.

- [ ] **Step 4: SparseReconstructor 작성 (재투영 오차 outlier 제거 포함)**

`SplatForge/Reconstruction/SparseReconstructor.swift`:

```swift
import UIKit
import simd

enum SparseReconstructor {
    /// 각 키프레임을 기준(anchor)으로, 촬영 순서상 가까운 이웃 neighborWindow개와만 매칭한다.
    /// 턴테이블 캡처라 배열이 순환한다고 보고 마지막-처음도 이웃으로 취급(% count).
    static func reconstruct(keyframes: [PosedFrame], neighborWindow: Int = 3) -> [SparsePoint3D] {
        guard keyframes.count > neighborWindow else { return [] }
        var allPoints: [SparsePoint3D] = []

        for i in 0..<keyframes.count {
            for offset in 1...neighborWindow {
                let j = (i + offset) % keyframes.count
                if j == i { continue }
                allPoints.append(contentsOf: reconstructPair(frameA: keyframes[i], frameB: keyframes[j]))
            }
        }
        return allPoints
    }

    private static func reconstructPair(frameA: PosedFrame, frameB: PosedFrame) -> [SparsePoint3D] {
        guard let imageA = UIImage(contentsOfFile: frameA.imagePath.path),
              let imageB = UIImage(contentsOfFile: frameB.imagePath.path) else { return [] }

        let matches = OpenCVWrapper.matchFeatures(between: imageA, and: imageB)
        guard matches.points1.count > 0 else { return [] }

        let p1 = ProjectionMath.projectionMatrixRowMajor(cameraToWorldPose: frameA.pose, intrinsics: frameA.intrinsics)
        let p2 = ProjectionMath.projectionMatrixRowMajor(cameraToWorldPose: frameB.pose, intrinsics: frameB.intrinsics)

        let triangulated = OpenCVWrapper.triangulate(withProjection1: p1.map { NSNumber(value: $0) },
                                                       points1: matches.points1,
                                                       projection2: p2.map { NSNumber(value: $0) },
                                                       points2: matches.points2)

        var result: [SparsePoint3D] = []
        for (index, tp) in triangulated.enumerated() {
            guard index < matches.points1.count else { break }
            let position = simd_float3(tp.x, tp.y, tp.z)
            let pixel = matches.points1[index].cgPointValue

            guard isReprojectionErrorAcceptable(position: position, pixel: pixel, pose: frameA.pose,
                                                 intrinsics: frameA.intrinsics, maxErrorPixels: 4.0) else {
                continue
            }

            let color = sampleColor(image: imageA, at: pixel)
            result.append(SparsePoint3D(position: position, color: color))
        }
        return result
    }

    private static func isReprojectionErrorAcceptable(position: simd_float3, pixel: CGPoint, pose: simd_float4x4,
                                                        intrinsics: simd_float3x3, maxErrorPixels: Float) -> Bool {
        let (projectedPixel, isInFront) = ProjectionMath.project(worldPoint: position, pose: pose, intrinsics: intrinsics)
        guard isInFront else { return false }
        let error = hypot(projectedPixel.x - pixel.x, projectedPixel.y - pixel.y)
        return error <= CGFloat(maxErrorPixels)
    }

    // 참고: JPEG 디코더가 내부적으로 만드는 CGImage의 실제 바이트 순서(RGB vs BGR 등)는
    // 기기/iOS 버전에 따라 달라질 수 있어, 드물게 R/B가 바뀌어 보일 수 있다.
    // 지오메트리(점의 3D 위치) 정확도에는 영향 없는 순수 표시용 컬러라 Phase 1에서는 이 정도로 충분 —
    // 색이 이상해 보이면 아래 세 인덱스 순서를 [2,1,0]으로 바꿔서 재시도.
    private static func sampleColor(image: UIImage, at point: CGPoint) -> SIMD3<UInt8> {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return SIMD3<UInt8>(128, 128, 128) }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let x = Int(point.x.rounded())
        let y = Int(point.y.rounded())
        guard x >= 0, y >= 0, x < cgImage.width, y < cgImage.height else { return SIMD3<UInt8>(128, 128, 128) }

        let offset = y * bytesPerRow + x * bytesPerPixel
        return SIMD3<UInt8>(bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }
}
```

- [ ] **Step 5: 커밋**

```bash
git add SplatForge/Reconstruction/SparsePoint3D.swift SplatForge/Reconstruction/SparseReconstructor.swift SplatForge/Reconstruction/PLYExporter.swift SplatForgeTests/PLYExporterTests.swift
git commit -m "Add SparseReconstructor pipeline assembly and PLY export"
```

---

### Task 11: 결과 화면 UI + 엔드투엔드 실기기 검증

**Files:**
- Create: `SplatForge/Reconstruction/ReconstructionViewModel.swift`
- Create: `SplatForge/Result/ResultView.swift`
- Modify: `SplatForge/ContentView.swift`

**Interfaces:**
- Consumes: `SparseReconstructor`, `PLYExporter`(Task 10), `CaptureView`(Task 7)
- Produces: 없음(최종 UI 조립 — Phase 1의 마지막 태스크)

- [ ] **Step 1: ReconstructionViewModel 작성**

`SplatForge/Reconstruction/ReconstructionViewModel.swift`:

```swift
import Foundation
import simd

@MainActor
final class ReconstructionViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var pointCount: Int?
    @Published var exportedFileURL: URL?

    func reconstruct(keyframes: [PosedFrame]) {
        isProcessing = true
        pointCount = nil
        exportedFileURL = nil

        Task {
            // CPU 무거운 재구성 연산을 메인 액터 밖에서 돌리고 결과만 await로 받는다.
            let points = await Task.detached(priority: .userInitiated) {
                SparseReconstructor.reconstruct(keyframes: keyframes)
            }.value

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("sparse-\(Date().timeIntervalSince1970).ply")
            try? PLYExporter.write(points: points, to: url)

            pointCount = points.count
            exportedFileURL = url
            isProcessing = false
        }
    }
}
```

- [ ] **Step 2: ResultView 작성**

`SplatForge/Result/ResultView.swift`:

```swift
import SwiftUI

struct ResultView: View {
    @ObservedObject var viewModel: ReconstructionViewModel

    var body: some View {
        VStack(spacing: 16) {
            if viewModel.isProcessing {
                ProgressView("재구성 중...")
            } else if let count = viewModel.pointCount, let url = viewModel.exportedFileURL {
                Text("\(count)개 포인트 재구성 완료")
                    .font(.headline)
                ShareLink(item: url) {
                    Label(".ply 내보내기", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 3: ContentView에서 캡처 -> 재구성 -> 결과 흐름 연결**

`SplatForge/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ReconstructionViewModel()
    @State private var isShowingResult = false

    var body: some View {
        CaptureView { keyframes in
            isShowingResult = true
            viewModel.reconstruct(keyframes: keyframes)
        }
        .sheet(isPresented: $isShowingResult) {
            ResultView(viewModel: viewModel)
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 4: 엔드투엔드 실기기 검증**

Cmd+R. 실제 작은 물체(예: 머그컵)를 책상에 놓고 주위를 천천히 돌면서 촬영 → 50 키프레임 도달 시 자동 종료(또는 수동 종료) → 시트가 뜨고 "재구성 중..." → 완료되면 포인트 개수와 내보내기 버튼이 보이는지 확인.

Expected: 포인트 수가 0이 아니고(수백~수천 개 수준이면 정상), "공유하기"로 `.ply` 파일을 Mac의 AirDrop 등으로 옮길 수 있다.

- [ ] **Step 5: 재구성 결과 시각적 검증 (중요 — 부호 규약 문제를 여기서 잡는다)**

내보낸 `.ply` 파일을 Mac으로 옮겨서 CloudCompare, MeshLab, 또는 macOS의 "미리보기" 앱(3D 파일 지원)으로 열어본다.

**정상**: 점들이 실제로 촬영한 물체와 대략 비슷한 형태로 한 군데 뭉쳐 있다.

**비정상 — 부호 문제 의심**: 점들이 넓게 흩어져 있거나, 카메라 궤적 반대쪽에 있거나, 형태를 전혀 알아볼 수 없다면 Task 9에서 다룬 -Z 부호 보정이 실제 ARKit 데이터에서는 반대일 가능성이 있다. 이 경우 `ProjectionMath.swift`의 `projectionMatrixRowMajor`와 `project` 두 함수에서 Z 부호 반전(`-m.columns.*.z`, `camPoint4.z < 0`, `correctedZ = -camPoint4.z`)을 모두 반대로 바꿔서(즉 부호 반전을 제거하고) 다시 시도해본다. `TriangulationTests`(Task 9)의 합성 데이터 테스트는 이 프로젝트 내부적으로는 항상 일관되게 통과하므로(투영과 삼각측량이 같은 규약을 공유), 실제 ARKit 데이터에서만 드러나는 문제라는 점에 유의.

- [ ] **Step 6: 커밋**

```bash
git add SplatForge/Reconstruction/ReconstructionViewModel.swift SplatForge/Result/ResultView.swift SplatForge/ContentView.swift
git commit -m "Wire capture-to-reconstruction-to-export end-to-end flow"
```

---

## Self-Review 결과

**스펙 커버리지**: 스펙의 M0(Xcode/Swift 기초)는 Task 1에 녹여 넣음, M1(캡처)은 Task 1-2-3-6-7, M2(OpenCV+Sparse Reconstruction)는 Task 4-5-8-9-10-11이 커버. M3-M5(Dense/Fusion/Viewer/에러UI)와 스트레치(S1-S5)는 의도적으로 이 계획 밖 — 상단 "스코프 안내" 참고.

**타입 일관성 확인**: `PosedFrame`(Task 2에서 정의)의 필드명(`imagePath`, `pose`, `intrinsics`, `timestamp`)이 Task 6(CaptureSession), Task 10(SparseReconstructor)에서 동일하게 쓰임. `KeyframeSelector`의 메서드명(`passesGeometricFilter`/`passesBlurFilter`/`commit`)이 Task 6에서 정의된 그대로 CaptureSession에서 호출됨. `OpenCVWrapper`에 Task 4/5/8/9가 순서대로 메서드를 추가하는 구조라 각 Step마다 "전체 파일" 또는 "추가분" 여부를 명시해뒀음.

**알려진 리스크(플레이스홀더 아님, 실제 불확실성)**: Task 9의 -Z 부호 보정은 ARKit 공식 문서에 명시적으로 나오지 않는 관례라 100% 확신은 못 함 — 그래서 Task 11 Step 5에 실기기 검증 + 반대로 뒤집어보는 트러블슈팅 절차를 명시적으로 넣어뒀음. Task 4의 OpenCV CocoaPods pod가 pod install 시점에 최신 Xcode와 호환성 문제가 있을 수 있어 xcframework 직접 다운로드 대안도 명시.
