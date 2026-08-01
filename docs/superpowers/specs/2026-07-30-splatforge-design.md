# SplatForge — iPhone 3D Reconstruction App 설계

- 날짜: 2026-07-30
- 상태: 브레인스토밍 완료, 사용자 리뷰 대기

## 개요

LiDAR가 없는 iPhone 17(기본형)에서 실행되는 3D reconstruction 앱. 작은 물체를 손에 든 채(또는 물체 주위를) 카메라로 돌면서 촬영하면, ARKit의 카메라 포즈 추적(VIO)만으로 — 즉 깊이 센서 없이 순수 비전 기반 멀티뷰 지오메트리로 — point cloud를 재구성해서 앱 안에서 보고 파일로 내보낼 수 있다.

## 배경 및 목적

- **목적**: iOS/Swift 학습 + 포트폴리오. 완성도보다 "기술적 깊이를 직접 구현해서 보여주는 것"이 우선순위. 단순히 Apple의 완성형 API를 호출하는 것이 아니라, 멀티뷰 지오메트리(feature matching, triangulation, multi-view stereo, point cloud fusion)를 직접 구현하는 경로를 원함.
- **사용자 배경**: 로봇/센서 엔지니어로 LiDAR·RGB-D 카메라 캘리브레이션, point cloud 처리(PCL), 센서 퓨전을 실무로 다뤄본 경험이 있음. 3D 비전 이론은 이미 익숙하고, Swift/iOS 개발은 이번이 완전히 처음.
- **왜 이 방향이 포트폴리오로 강한가**: 전문 분야(LiDAR/RGB-D 기반 point cloud)를 깊이 센서 없이 순수 비전으로 재현한다는 스토리 — "센서가 없어서 못한 게 아니라, 센서 없이도 되게 만들었다"는 차별점.

## 요구사항 / 제약

- 대상 기기: iPhone 17 기본형 — **LiDAR 없음**. ARKit의 `sceneDepth` 계열 API(LiDAR 전용) 사용 불가. 6DoF 카메라 포즈는 VIO(비전+IMU)로 모든 ARKit 기기에서 제공됨.
- 개발자: Swift/iOS 완전 초보. C++ 실무 경험 있음(로봇/센서 스택).
- 스캔 대상: 작은 물체(책상 위에 놓고 주위를 도는 턴테이블식 캡처). 방/공간 스케일은 스코프 밖.
- 처리 모델: 온디바이스 offline batch 처리(캡처 후 별도 처리 단계). 실시간 incremental fusion(SLAM 스타일)은 스코프 밖 — 데이터 구조·라이브 재삼각측량 등 난이도가 크게 높아지고, 학습/포트폴리오 목적에 필수적이지 않음.

## 검토한 접근법

### A. Apple Object Capture (RealityKit `PhotogrammetrySession`)
사진 세트를 넘기면 SfM+MVS+메싱+텍스처링까지 자동 처리하는 Apple 완제품 API. 가장 빠르게 동작하는 결과를 얻을 수 있지만 블랙박스라 멀티뷰 지오메트리를 "직접 구현"하지 않음 — 포트폴리오 목적과 반대 방향이라 **채택하지 않음**. 품질 비교용 baseline으로는 유효.

### B. 직접 구현 Geometric SfM/MVS 파이프라인 (채택, MVP 축)
ARKit이 제공하는 카메라 포즈(VIO)를 "이미 캘리브레이션된 리그의 pose/timestamp"로 취급하고, 그 위에 실제 3D reconstruction(매칭→triangulation→dense stereo→fusion)을 직접 구현. 포즈를 이미 알기 때문에 SfM에서 가장 어려운 "포즈 추정"(essential matrix 추정/분해) 단계를 건너뛰고, "포즈가 주어졌을 때 dense geometry를 복원하는" — 실제로 더 새롭고 실무 경험과 맞닿는 — 문제에 집중할 수 있음.

### C. ARKit pose + monocular depth 모델(Core ML) fusion (폴백)
classical dense correspondence 대신 사전학습 monocular depth 모델을 프레임마다 돌려 relative depth map을 얻고, ARKit 포즈로 스케일 정렬 후 fusion. B보다 "직접 구현"의 순도는 낮지만 텍스처 없는 표면 등 classical matching이 실패하는 구간에서 더 견고함. **B와 동일한 인터페이스(`DenseDepthEstimator` protocol) 뒤에서 교체 가능한 전략으로 채택** — 구간별로 B/C를 선택적으로 스위칭.

### Gaussian Splatting 반영
선례 확인됨 — 상용 앱(Scaniverse, Polycam, KIRI Engine, Luma AI), 2026년 온디바이스 트레이닝 연구(PocketGS, Mobile-GS/ICLR 2026)가 존재. Apple RealityKit의 `GaussianSplatComponent`는 문서상 visionOS 27(Vision Pro) 전용으로 보이며 iPhone 지원 근거는 확인 안 됨 — iOS에서는 오픈소스 **MetalSplatter**가 현실적인 렌더링 경로.

3DGS의 입력(posed image + sparse point cloud)이 Sparse Reconstruction 단계 출력과 동일하므로, **Dense Reconstruction 단계에서 Mesh 경로와 병렬로 분기하는 확장 경로**로 설계에 반영(아래 아키텍처 참고). MVP는 Mesh 경로만 완주하는 것을 목표로 하고, GS 경로는 스트레치.

## 아키텍처

### 파이프라인 개요

```
Capture → Keyframe Selection → Sparse Reconstruction (공통)
                                        │
                        ┌───────────────┴───────────────┐
                        ▼ Path 1: Mesh (MVP)             ▼ Path 2: Splat (확장, stretch)
                Dense Reconstruction(B/C)          SplatTrainerAdapter
                        │                        (sparse cloud+pose →
                        ▼                         오픈소스 3DGS 트레이너 입력 포맷)
                    Fusion                                  │
                        │                                   ▼
                        ▼                          Splat 데이터(.ply 등)
                  Meshing (stretch)                          │
                        │                                   ▼
                        ▼                        SplatRenderer(MetalSplatter
                  Viewer / Export                  기반 온디바이스 렌더링)
```

**중요**: "Capture"와 "Keyframe Selection"은 다이어그램상 순차 단계처럼 보이지만 실제로는 하나의 실시간 루프다 (ARKit이 ~60fps로 프레임을 주는데, 전부 메모리에 들고 있으면 메모리 부족 위험이 크기 때문에 캡처 중 즉시 필터링해야 함). 자세한 내용은 컴포넌트 상세의 Capture 절 참고.

**GS 경로의 실행 위치**: 캡처+Sparse Reconstruction은 iPhone에서, 표준 3DGS 트레이너(Python/CUDA 기반, 예: `gsplat`)는 iPhone에서 실행 불가하므로 Mac/클라우드에서 오프라인으로, 렌더링은 다시 iPhone(MetalSplatter)에서. Mesh 경로(B)는 캡처~재구성~뷰잉이 전부 온디바이스로 끝나는 반면, GS 경로 기본형은 트레이닝 단계에서 외부 컴퓨트가 필요한 하이브리드 워크플로우다. PocketGS 스타일의 완전 온디바이스 트레이닝(Metal differentiable rasterizer 직접 구현)으로 이 갭을 없앨 수 있지만, 이는 별도의 최상급 스트레치(S5)로 분리한다.

### 모듈 경계

각 모듈은 하나의 책임만 가지며, 명확한 데이터 타입으로 통신한다.

| 모듈 | 책임 | 입력 → 출력 |
|---|---|---|
| `CaptureSession` | ARSession 래핑, 재구성 로직은 전혀 모름 | ARKit 이벤트 → `PosedFrame` 스트림 |
| `KeyframeSelector` | 실시간 스트림 필터링(트래킹상태/baseline/각도/블러) | `PosedFrame` 스트림 → 큐레이션된 부분집합 |
| `SparseReconstructor` | 매칭 + triangulation | Keyframes → sparse point cloud |
| `DenseDepthEstimator` (**protocol**) | `estimate(frame, neighbors) -> DepthMap`. `GeometricMVS`(B)와 `MLDepthFusion`(C) 두 구현체 | Keyframes(+sparse) → per-frame depth map |
| `PointCloudFuser` | depth map들 → 통합 cloud, outlier 제거 | Depth maps → fused point cloud |
| `Mesher` (stretch) | point cloud → mesh | Point cloud → mesh |
| `Viewer/Exporter` | 최종 데이터만 소비 — 어떻게 만들어졌는지는 모름 | Point cloud/mesh → 화면 표시 + `.ply`/`.usdz` |
| `SplatTrainerAdapter` (확장) | sparse cloud+pose → 오픈소스 트레이너 입력 포맷 변환 | Sparse cloud → 외부 트레이너 입력 |
| `SplatRenderer` (확장) | MetalSplatter 통합 | Splat 데이터 → 온디바이스 렌더링 |

`DenseDepthEstimator`를 protocol로 분리해 둔 덕분에, B가 특정 구간(텍스처 없는 표면 등)에서 불안정하면 그 프레임만 C 구현체로 교체하는 결정이 실제 인터페이스 교체로 반영된다. `PointCloudFuser` 이후 단계는 depth map이 어떻게 만들어졌는지 몰라도 되므로 건드릴 필요가 없다.

## 컴포넌트 상세

### Capture

`ARWorldTrackingConfiguration` 기반 world tracking만 사용(LiDAR 관련 프레임 세만틱은 `supportsFrameSemantics(.sceneDepth) == false`이므로 애초에 미사용). `planeDetection = .horizontal`로 물체가 놓인 바닥면을 잡아 이후 배경 분리에 참고.

```swift
struct PosedFrame {
    let imagePath: URL             // 디스크에 저장된 JPEG/HEIC 경로
    let pose: simd_float4x4        // ARFrame.camera.transform
    let intrinsics: simd_float3x3  // ARFrame.camera.intrinsics
    let timestamp: TimeInterval
}
```

`ARFrame.capturedImage`(YCbCr 4:2:0)는 키프레임으로 확정되는 즉시 인코딩해 디스크에 저장하고, 메모리에는 pose/intrinsics/경로만 유지한다(수백 프레임이 쌓여도 메모리 부담 없음).

**실시간 키프레임 필터링** — ARSession delegate 콜백 안에서 순서대로 체크, 하나라도 걸리면 스킵:
1. 트래킹 상태 — `ARCamera.TrackingState != .normal`이면 스킵
2. Baseline — 마지막 키프레임 대비 이동 거리가 (물체까지 대략 거리 대비) 너무 작으면 스킵
3. 회전각 — 물체 중심 기준 방위각이 마지막 키프레임 대비 일정 각도 이상 안 돌았으면 스킵
4. 블러 — Laplacian variance(vImage)가 임계치 미만이면 스킵

통과하면 JPEG 인코딩 + 디스크 저장 + `PosedFrame` append.

**캡처 UX(MVP)**: 버튼 탭으로 시작 → 카메라 패스스루 위에 저장된 키프레임 수 표시 → 다시 탭하거나 목표 수(40~60장) 도달 시 종료. 각도 커버리지 게이지 등은 폴리싱 단계 스트레치.

**에러 케이스**: 트래킹 로스 시 ARKit이 relocalization을 시도하지만 완전히 깨지면 좌표계 자체가 신뢰 불가 — 처음부터 재촬영 유도(재추적 후 이어붙이는 것은 pose drift 위험이 있어 v1에서 제외). 최소 키프레임 수(20~40장) 미달 시 재구성이 성립하지 않음.

### Sparse Reconstruction

- **매칭 대상 축소**: 포즈를 이미 알므로 모든 프레임 쌍(O(N²))이 아니라 포즈 그래프상 가까운 이웃(각 키프레임 기준 앞뒤 K개, 턴테이블이라 마지막-처음도 이웃)만 매칭.
- **Triangulation**: 포즈가 알려져 있으므로 essential matrix 추정/분해 불필요 — 매칭된 각 점쌍에 바로 linear triangulation(DLT). 3뷰 이상 겹치는 track은 다중뷰 최소자승으로 더 안정적. Reprojection error로 outlier 제거.
- **결과물**: `[Point3D{position, color, observations}]` — 색상은 관측된 프레임들의 픽셀 색 평균. 이 sparse cloud가 GS 경로(`SplatTrainerAdapter`)의 입력과 동일.
- **CV 구현체**: Vision framework에는 classical feature detector/matcher/RANSAC이 없으므로 **OpenCV를 Objective-C++ 브릿지로 연동**(feature detection/matching, RANSAC, stereo rectify, SGBM). C++ 실무 경험과 맞고, 검증된 구현을 재사용해 파이프라인 오케스트레이션·fusion·iOS 통합에 학습을 집중할 수 있음.
- **알려진 한계**: 이 설계에는 bundle adjustment(전역 포즈 최적화)가 없다 — ARKit pose를 그대로 신뢰하는 구조라 ARKit 자체의 drift가 재구성 품질에 그대로 반영된다. v1의 명시적 한계로 받아들이고, bundle adjustment 추가는 스트레치로 미룬다.

### Dense Reconstruction (Approach B: GeometricMVS)

포즈를 아는 두 뷰 사이의 dense correspondence를 스테레오 카메라 depth 문제로 환원:
1. **Rectification**: reference-source 프레임 쌍을 알려진 relative pose(R,t)로 rectify
2. **Dense correspondence**: rectified 쌍에서 disparity 계산 — semi-global matching(OpenCV `StereoSGBM`)
3. **Disparity → Depth**: `depth = baseline × focal / disparity`
4. 여러 source 뷰로 반복 → reference 프레임당 depth map 여러 장 → median/consistency check으로 확정(여러 뷰에서 일치하는 값만 신뢰)

**Approach C(fallback)**는 동일 `DenseDepthEstimator` 인터페이스로, SGBM 대신 Core ML monocular depth 모델 추론 + ARKit 상대 pose로 스케일 정렬. 텍스처 없는 무광 표면 등 stereo matching이 실패하는 구간에 투입.

### Fusion

Depth map → world 좌표계 projection(픽셀+depth+intrinsics+pose) → voxel grid downsampling(중복 포인트 병합) + statistical outlier removal(이웃 거리 분포 기준). PCL의 표준 필터와 개념적으로 동일 — PCL 자체를 iOS로 포팅하는 것은 공식 배포가 없어 직접 빌드가 필요하므로, OpenCV 기반으로 직접 구현하는 쪽을 기본으로 한다.

### Meshing (stretch)

Poisson surface reconstruction — 기존 라이브러리 활용 여부는 구현 단계에서 검토.

### Viewer / Export

- **뷰어(MVP)**: SceneKit — point cloud는 `.point` primitive, mesh는 `SCNGeometry`. 회전/줌 인터랙션.
- **뷰어(스트레치)**: RealityKit — 재구성된 물체를 실공간에 AR로 재배치하는 데모.
- **Export(필수)**: `.ply` — 색상 포함 point cloud, MeshLab/CloudCompare 등 표준 툴에서 검증 가능(실무에서 쓰던 방식과 동일).
- **Export(스트레치)**: `.usdz` — iOS Quick Look 네이티브 지원, 웹페이지에 `<a rel="ar">`로 링크하면 방문자가 자신의 iPhone으로 AR 뷰 가능. 포트폴리오 사이트 임베드에 유용.

## 기술 스택

| 영역 | 선택 |
|---|---|
| UI | Swift + SwiftUI |
| 카메라/포즈 | ARKit (`ARWorldTrackingConfiguration`, LiDAR 미사용) |
| CV 코어 | OpenCV(Objective-C++ 브릿지) — feature matching, rectify, SGBM, RANSAC |
| 선형대수 보조 | Accelerate / simd |
| MVP 뷰어 | SceneKit |
| 스트레치 뷰어 | RealityKit(AR 재배치) |
| Export | `.ply`(필수), `.usdz`(스트레치) |
| GS 확장 | 오픈소스 3DGS 트레이너(Mac/클라우드, 앱 외부) + MetalSplatter(온디바이스 렌더링) |

## 에러 처리

이 파이프라인의 지배적 실패 모드는 크래시가 아니라 **조용한 품질 저하**(텍스처 없는 표면, 반사/투명 물체, 반복 패턴에서의 매칭 실패 등)다. 원칙:

1. 각 스테이지 출력에 품질 지표를 붙인다 — sparse: track 수/평균 reprojection error, dense: 유효 depth 픽셀 비율, fusion: 최종 포인트 수.
2. UI에 "재구성 품질: 양호/주의" 수준으로 노출해 silent 실패를 막는다.
3. 각 스테이지 중간 산출물(키프레임, sparse cloud, depth map, fused cloud)을 디스크에 남겨 어느 단계에서 품질이 무너졌는지 사후 확인 가능하게 한다.

스테이지별 주요 실패 모드는 컴포넌트 상세의 각 절(Capture/Sparse/Dense) 참고.

## 테스트 전략

Classical unit test로 커버되는 부분과 안 되는 부분이 뚜렷이 갈린다.

1. **순수 로직(XCTest)**: `KeyframeSelector` 필터링 로직(합성 pose 시퀀스로 검증), disparity→depth 변환 등 순수 수학 함수.
2. **Triangulation — synthetic ground truth**: 알려진 3D 점을 가상 카메라 2대로 투영해 2D 대응점을 만들고, triangulation 함수가 원래 3D 점을 정확히 복원하는지 검증. 이 파이프라인에서 ground truth가 명확한 몇 안 되는 지점.
3. **기준 물체 회귀 테스트**: 치수를 정확히 아는 물체를 반복 스캔해 재구성된 bounding box 크기를 실측값과 비교(실무의 "잔차 RMSE 합부 판정"과 동일 패턴). 파이프라인 변경마다 재실행해 회귀 확인.
4. **정성적 확인**: 메싱 품질/텍스처는 결국 사람이 눈으로 확인 — 마일스톤마다 실스캔 후 육안 확인으로 인정.
5. **중간 산출물 덤프**: sparse cloud를 `.ply`로 찍어 CloudCompare로 열어보는 식 — 별도 테스트 도구 없이 기존 실무 툴 재사용.

## 마일스톤

각 마일스톤이 눈에 보이는 결과물을 만들도록 난이도를 순차적으로 쌓는다.

### MVP 경로

| # | 마일스톤 | 산출물 |
|---|---|---|
| M0 | Swift/SwiftUI 기초 + Xcode 프로젝트 구조 학습 | 카메라 프리뷰만 띄우는 최소 앱 |
| M1 | ARKit 캡처: PosedFrame 스트림 + 실시간 키프레임 필터링 + 디스크 저장 | "N장 캡처 완료" 앱, pose 궤적 원형 확인 |
| M2 | OpenCV 브릿지 연동 + Sparse Reconstruction | 첫 3D 결과물 — sparse point cloud `.ply` 익스포트. Synthetic triangulation 유닛테스트 포함 |
| M3 | Dense Reconstruction(rectify+SGBM) + Fusion | 조밀한 fused point cloud. 기준 물체 회귀 테스트 도입 |
| M4 | SceneKit 인앱 뷰어 | 앱 안에서 바로 회전/줌하며 결과 확인 |
| M5 | 에러 처리 + 품질 지표 UI (**MVP 완성선**) | LiDAR 없이 촬영한 작은 물체를 직접 구현한 멀티뷰 지오메트리 파이프라인으로 재구성해 앱에서 보고 `.ply`로 내보내는 완결된 결과물 |

### 스트레치 (우선순위 순)

| # | 내용 |
|---|---|
| S1 | Meshing(Poisson) + mesh 뷰어 |
| S2 | RealityKit AR 재배치 데모 + `.usdz`/Quick Look 웹 연동 |
| S3 | GS 확장 경로 — Mac에서 오픈소스 트레이너로 학습 → MetalSplatter 온디바이스 렌더링 |
| S4 | Approach C 폴백(Core ML monocular depth) 통합 + 신뢰도 기반 자동 스위칭 |
| S5 (최상급) | PocketGS 스타일 완전 온디바이스 GS 트레이닝(Metal differentiable rasterizer 직접 구현) |

## 미해결 / 구현 계획에서 구체화할 것

- Baseline/회전각/블러 임계값의 정확한 수치, 최소 키프레임 수 하한 — 실제 스캔 실험을 통해 튜닝 필요.
- OpenCV iOS 통합 방식(CocoaPods/SPM/프레임워크 직접 링크) 중 선택.
- Meshing 알고리즘을 기존 라이브러리로 가져올지 직접 구현할지.
- S1 이후 스트레치의 실제 착수 여부는 M5 완료 시점 상황에 따라 결정.
