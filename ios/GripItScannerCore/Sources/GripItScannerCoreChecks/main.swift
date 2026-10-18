import Foundation
import GripItScannerCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw CheckFailure.failed(message) }
}

func checkContracts() throws {
    let bundledSample = try SampleHandProfiles.averageRight()
    try expect(bundledSample.profileId == "sample-average-right", "Library simulator fixture must load")
    let profile = bundledSample
    try expect(profile.measurements.palm.widthMm == 82, "Fixture palm width must decode")
    let roundTrip = try HandProfileCodec.decode(HandProfileCodec.encode(profile))
    try expect(roundTrip == profile, "HandProfile must round trip")

    let encodedObject = try expectValue(
        JSONSerialization.jsonObject(with: HandProfileCodec.encode(profile)) as? [String: Any],
        "Encoded HandProfile must be a JSON object"
    )
    let measurements = try expectValue(encodedObject["measurements"] as? [String: Any], "Missing measurements")
    let palm = try expectValue(measurements["palm"] as? [String: Any], "Missing palm measurements")
    try expect(palm["thicknessMm"] is NSNull, "Unknown palm thickness must encode as null")
    let fingers = try expectValue(measurements["fingers"] as? [String: Any], "Missing finger measurements")
    for name in ["index", "middle", "ring", "pinky", "thumb"] {
        let finger = try expectValue(fingers[name] as? [String: Any], "Missing \(name) measurements")
        try expect(finger["diameterMm"] is NSNull, "Unknown \(name) diameter must encode as null")
    }

    do {
        _ = try HandProfileCodec.decode(Data(#"{"schemaVersion":"2.0.0"}"#.utf8))
        throw CheckFailure.failed("Unsupported major version must fail")
    } catch HandProfileCodingError.unsupportedMajorVersion(2) {
        // Expected.
    }
}

func checkMetricGeometry() throws {
    try expect(ScannerAdapterGeometry.physicalHandedness(label: "Right", convention: .subjectHand) == .right, "Subject handedness convention")
    try expect(ScannerAdapterGeometry.physicalHandedness(label: "Right", convention: .mirroredViewer) == .left, "Mirrored viewer labels must swap")
    try expect(ScannerAdapterGeometry.physicalHandedness(label: "invalid", convention: .subjectHand) == nil, "Unknown labels must fail")
    let rectified = try expectValue(ScannerAdapterGeometry.rectifiedPixel(PixelPoint(x: 75, y: 50), center: PixelPoint(x: 50, y: 50), width: 100, height: 100, lookupTable: [0.1, 0.1]), "Distortion lookup must rectify a point")
    try expect(rectified.x == 77.5 && rectified.y == 50, "Lens correction must magnify around the distortion center")
    let modelCorner = PixelPoint(x: 0.2, y: 0.3)
    let sensorCorner = SensorImageRotation.left.sensorPoint(fromModel: modelCorner)
    try expect(abs(sensorCorner.x - 0.7) < 0.000001 && sensorCorner.y == 0.2, "Portrait model points must map back to native sensor pixels")
    try expect(ScannerAdapterGeometry.medianValidDepth([.nan, 0, 0.39, 0.40, 0.41, 2]) == 0.40, "Depth median must ignore holes and invalid distances")
    try expect(ScannerAdapterGeometry.medianValidDepth([.nan, 0, 2]) == nil, "Invalid depth must not create a measurement")
    let scaled = try expectValue(ScannerAdapterGeometry.scaledIntrinsics(fx: 500, fy: 600, cx: 320, cy: 240, referenceWidth: 640, referenceHeight: 480, depthWidth: 320, depthHeight: 240), "Valid intrinsic scale must exist")
    try expect(scaled.fx == 250 && scaled.fy == 300 && scaled.cx == 160 && scaled.cy == 120, "Intrinsics must scale to depth resolution")
    // A right hand with its palm at the camera puts the thumb at image right; a
    // left hand mirrors that. Both must read as the palm view.
    let rightPalm = try expectValue(ScannerAdapterGeometry.handFacing(
        radial: Vector3D(x: 1, y: 0, z: 0), distal: Vector3D(x: 0, y: -1, z: 0),
        handedness: .right), "Right palm facing must resolve")
    let leftPalm = try expectValue(ScannerAdapterGeometry.handFacing(
        radial: Vector3D(x: -1, y: 0, z: 0), distal: Vector3D(x: 0, y: -1, z: 0),
        handedness: .left), "Left palm facing must resolve")
    try expect(ScannerAdapterGeometry.classifyView(rightPalm) == .palm, "Right palm orientation")
    try expect(ScannerAdapterGeometry.classifyView(leftPalm) == .palm, "Left palm orientation")
    // Tilting the same hand inside the image plane must not move the decision.
    let rolledPalm = try expectValue(ScannerAdapterGeometry.handFacing(
        radial: Vector3D(x: 0, y: 1, z: 0), distal: Vector3D(x: 1, y: 0, z: 0),
        handedness: .right), "Rolled palm facing must resolve")
    try expect(ScannerAdapterGeometry.classifyView(rolledPalm) == .palm, "Image-plane roll must not change the view")
    try expect(ScannerAdapterGeometry.classifyView(HandFacing(palm: 0, thumb: 1, fingers: 0)) == .thumbSide, "Thumb-side orientation")
    try expect(ScannerAdapterGeometry.classifyView(HandFacing(palm: .nan, thumb: 0, fingers: 0)) == nil, "Invalid facing must fail")
    try expect(!ScannerAdapterGeometry.matchesView(HandFacing(palm: 0, thumb: 1, fingers: 0), requested: .thumbSide), "Edge-on side must be rejected")
    try expect(ScannerAdapterGeometry.matchesView(HandFacing(palm: 0.5, thumb: 0.866, fingers: 0), requested: .thumbSide), "Oblique thumb side must be accepted")

    let point = try DepthProjector.project(
        pixel: PixelPoint(x: 420, y: 290),
        depthMeters: 0.5,
        intrinsics: CameraIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240)
    )
    try expect(point == MetricPoint3D(xMm: 100, yMm: 50, zMm: 500), "Depth projection must use camera intrinsics")

    let reflectedPoint = HandCanonicalizer.canonicalize(
        MetricPoint3D(xMm: -12, yMm: 30, zMm: 4),
        handedness: .left
    )
    try expect(reflectedPoint == MetricPoint3D(xMm: 12, yMm: 30, zMm: 4), "Left hands must reflect X only")

    do {
        _ = try DepthProjector.project(
            pixel: PixelPoint(x: 0, y: 0),
            depthMeters: 0.05,
            intrinsics: CameraIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240)
        )
        throw CheckFailure.failed("Out-of-range depth must fail")
    } catch DepthProjectionError.depthOutOfRange(0.05) {
        // Expected.
    }

    let right = fullObservation(view: .palm, handedness: .right)
    let leftLandmarks = right.landmarks.mapValues { landmark in
        NamedLandmark(
            name: landmark.name,
            point: MetricPoint3D(
                xMm: -landmark.point.xMm,
                yMm: landmark.point.yMm,
                zMm: landmark.point.zMm
            ),
            confidence: landmark.confidence
        )
    }
    let left = ScanObservation(
        view: .palm,
        handedness: .left,
        landmarks: leftLandmarks,
        frameConfidence: right.frameConfidence
    )
    let canonicalRight = try right.canonicalized()
    let canonicalLeft = try left.canonicalized()
    for name in HandLandmarkName.allCases {
        let rightPoint = try expectValue(canonicalRight.landmarks[name]?.point, "Missing right landmark")
        let leftPoint = try expectValue(canonicalLeft.landmarks[name]?.point, "Missing left landmark")
        try expect(abs(rightPoint.xMm - leftPoint.xMm) < 0.000_001, "Left and right canonical X must match")
        try expect(abs(rightPoint.yMm - leftPoint.yMm) < 0.000_001, "Left and right canonical Y must match")
        try expect(abs(rightPoint.zMm - leftPoint.zMm) < 0.000_001, "Left and right canonical Z must match")
    }
}

func coverageObservation(view: ScanView, confidence: Double) -> ScanObservation {
    fullObservation(view: view, confidence: confidence)
}

func checkCoverage() throws {
    try expect(
        ScanView.requiredOrder == [.palm, .thumbSide, .back, .pinkySide],
        "Required views must follow one continuous hand rotation"
    )

    var landmarkCoverage = LandmarkCoverageTracker(minimumSamplesPerLandmark: 2)
    landmarkCoverage.record(validLandmarks: [.wrist, .indexMCP], view: .palm)
    landmarkCoverage.record(validLandmarks: [.wrist], view: .palm)
    try expect(landmarkCoverage.snapshot.fraction(for: .wrist) == 1, "Wrist coverage must complete")
    try expect(
        landmarkCoverage.snapshot.fraction(for: .indexMCP) == 0.5,
        "Index coverage must remain partial"
    )
    try expect(
        landmarkCoverage.snapshot.fraction(for: .wrist, in: .back) == 0,
        "Landmark coverage must remain view-specific"
    )

    var tracker = CoverageTracker(minimumFramesPerView: 2, minimumConfidence: 0.8)
    try tracker.accept(coverageObservation(view: .palm, confidence: 0.9))
    try expect(tracker.snapshot.fraction == 0.125, "Coverage must fill within the current view")
    try tracker.accept(coverageObservation(view: .palm, confidence: 0.9))
    try expect(tracker.snapshot.currentView == .thumbSide, "Coverage must advance to the thumb-side view")
    try expect(tracker.snapshot.fraction == 0.25, "One of four views must equal 25 percent")

    do {
        try tracker.accept(coverageObservation(view: .thumbSide, confidence: 0.5))
        throw CheckFailure.failed("Low-confidence frames must fail")
    } catch CoverageError.lowConfidence {
        // Expected.
    }
    try expect(tracker.snapshot.fraction == 0.25, "Rejected frames must not advance coverage")

    var strictTracker = CoverageTracker(minimumFramesPerView: 1, minimumConfidence: 0.8)
    let wristOnly = ScanObservation(
        view: .palm,
        handedness: .right,
        landmarks: [
            .wrist: NamedLandmark(
                name: .wrist,
                point: MetricPoint3D(xMm: 0, yMm: 0, zMm: 500),
                confidence: 1
            ),
        ],
        frameConfidence: 1
    )
    do {
        try strictTracker.accept(wristOnly)
        throw CheckFailure.failed("Partial landmark frames must fail")
    } catch CoverageError.incompleteLandmarks {
        // Expected.
    }

    do {
        try strictTracker.accept(fullObservation(view: .palm, confidence: 1.5))
        throw CheckFailure.failed("Confidence above one must fail")
    } catch CoverageError.invalidConfidence {
        // Expected.
    }

    let valid = fullObservation(view: .palm)
    var nonFiniteLandmarks = valid.landmarks
    nonFiniteLandmarks[.indexTip] = NamedLandmark(
        name: .indexTip,
        point: MetricPoint3D(xMm: .nan, yMm: 1, zMm: 500),
        confidence: 1
    )
    let nonFinite = ScanObservation(
        view: .palm,
        handedness: .right,
        landmarks: nonFiniteLandmarks,
        frameConfidence: 1
    )
    do {
        try strictTracker.accept(nonFinite)
        throw CheckFailure.failed("Non-finite landmark coordinates must fail")
    } catch CoverageError.nonFiniteLandmark(.indexTip) {
        // Expected.
    }
}

func fullObservation(
    view: ScanView,
    scale: Double = 1,
    handedness: Handedness = .right,
    confidence: Double = 0.95,
    offset: (Double, Double, Double) = (0, 0, 0)
) -> ScanObservation {
    let raw: [HandLandmarkName: (Double, Double, Double)] = [
        .wrist: (0, 0, 0),
        .thumbCMC: (25, 18, 2), .thumbMCP: (38, 34, 4), .thumbIP: (48, 48, 6), .thumbTip: (58, 60, 8),
        .indexMCP: (30, 58, 0), .indexPIP: (32, 94, 1), .indexDIP: (33, 118, 1), .indexTip: (34, 137, 1),
        .middleMCP: (10, 62, 0), .middlePIP: (10, 102, 1), .middleDIP: (10, 129, 1), .middleTip: (10, 150, 1),
        .ringMCP: (-12, 60, 0), .ringPIP: (-14, 97, 1), .ringDIP: (-15, 122, 1), .ringTip: (-16, 141, 1),
        .pinkyMCP: (-30, 54, 0), .pinkyPIP: (-34, 83, 1), .pinkyDIP: (-36, 102, 1), .pinkyTip: (-38, 118, 1),
    ]
    let landmarks = Dictionary(uniqueKeysWithValues: raw.map { name, value in
        let point = MetricPoint3D(
            xMm: value.0 * scale + offset.0,
            yMm: value.1 * scale + offset.1,
            zMm: value.2 * scale + offset.2
        )
        return (name, NamedLandmark(name: name, point: point, confidence: confidence))
    })
    return ScanObservation(
        view: view,
        handedness: handedness,
        landmarks: landmarks,
        frameConfidence: confidence
    )
}

func checkAggregationAndSession() throws {
    var stability = MeasurementStabilityGate()
    let steady = fullObservation(view: .palm).landmarks
    try expect(!stability.accept(steady), "One frame must not establish stability")
    try expect(!stability.accept(steady), "Two frames must not establish stability")
    try expect(stability.accept(steady), "Three matching metric frames must settle")
    try expect(!stability.accept(fullObservation(view: .palm, offset: (50, 0, 0)).landmarks), "A moving hand must not advance")
    try expect(!stability.accept([:]), "Missing landmarks must reset stability")

    let measurements = try HandMeasurementAggregator().measure([
        fullObservation(view: .palm, scale: 1),
        fullObservation(view: .palm, scale: 1.02),
        fullObservation(view: .palm, scale: 8),
    ])
    try expect((measurements.palm.widthMm ?? 0) < 100, "Median measurement must reject a large outlier")
    try expect(measurements.fingers.index.segmentsMm.count == 3, "Index finger must have three segments")

    do {
        _ = try HandMeasurementAggregator().measure([
            ScanObservation(view: .palm, handedness: .right, landmarks: [:], frameConfidence: 1),
        ])
        throw CheckFailure.failed("Incomplete measurements must report their missing landmark")
    } catch HandMeasurementError.missingLandmark(.wrist) {
        // Expected.
    }

    var rejected = ScannerSession(minimumFramesPerView: 1)
    let validGeometry = fullObservation(view: .palm)
    var degenerateLandmarks = validGeometry.landmarks
    let pinkyPoint = try expectValue(validGeometry.landmarks[.pinkyMCP]?.point, "Missing pinky MCP")
    degenerateLandmarks[.indexMCP] = NamedLandmark(
        name: .indexMCP,
        point: pinkyPoint,
        confidence: 1
    )
    let degenerate = ScanObservation(
        view: .palm,
        handedness: .right,
        landmarks: degenerateLandmarks,
        frameConfidence: 1
    )
    do {
        try rejected.accept(degenerate)
        throw CheckFailure.failed("Degenerate landmark geometry must fail")
    } catch CoordinateCanonicalizationError.degenerateHandBasis {
        // Expected.
    }
    try expect(rejected.coverage.snapshot.fraction == 0, "Rejected geometry must not advance coverage")

    let incomplete = ScannerSession(minimumFramesPerView: 1)
    do {
        _ = try incomplete.makeProfile(profileId: "profile-1", createdAt: "2026-10-17T00:00:00Z")
        throw CheckFailure.failed("Incomplete sessions must not export")
    } catch ScannerSessionError.incompleteCoverage {
        // Expected.
    }

    var complete = ScannerSession(minimumFramesPerView: 1)
    for view in ScanView.requiredOrder {
        try complete.accept(fullObservation(view: view, offset: (120, -30, 500)))
    }
    let profile = try complete.makeProfile(
        profileId: "profile-1",
        createdAt: "2026-10-17T00:00:00Z"
    )
    try expect(profile.coordinateSystem == "gripit-hand-v1", "Session must export canonical coordinates")
    try expect(profile.capture.coverage.fraction == 1, "Completed session must export full coverage")
    try expect(profile.capture.method == "true-depth-mediapipe", "Session must identify its capture method")
    try expect(profile.landmarks["wrist"]?.xMm == 0, "Canonical wrist X must be the origin")
    try expect(profile.landmarks["wrist"]?.yMm == 0, "Canonical wrist Y must be the origin")
    try expect(profile.landmarks["wrist"]?.zMm == 0, "Canonical wrist Z must be the origin")
}

func expectValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw CheckFailure.failed(message) }
    return value
}

do {
    try checkContracts()
    try checkMetricGeometry()
    try checkCoverage()
    try checkAggregationAndSession()
    print("GripItScannerCore checks passed")
} catch {
    print("GripItScannerCore checks failed: \(error)")
    exit(1)
}
