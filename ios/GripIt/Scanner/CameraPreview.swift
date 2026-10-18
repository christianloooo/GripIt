import AVFoundation
import GripItScannerCore
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let points: [CGPoint]
    let sensorSize: CGSize

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.accessibilityLabel = "Live TrueDepth camera preview"
        view.set(session: session, points: points, sensorSize: sensorSize)
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {
        view.set(session: session, points: points, sensorSize: sensorSize)
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    private let skeletonLayer = CAShapeLayer()
    private var points: [CGPoint] = []
    private var sensorSize: CGSize = .zero
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        backgroundColor = .black

        previewLayer.videoGravity = .resizeAspectFill
        skeletonLayer.fillColor = UIColor(red: 0.67, green: 1, blue: 0.84, alpha: 1).cgColor
        skeletonLayer.strokeColor = UIColor(red: 0.38, green: 0.96, blue: 0.72, alpha: 1).cgColor
        skeletonLayer.lineCap = .round
        skeletonLayer.lineJoin = .round
        skeletonLayer.lineWidth = 2.5
        skeletonLayer.shadowColor = UIColor.black.cgColor
        skeletonLayer.shadowOpacity = 0.45
        skeletonLayer.shadowRadius = 2
        previewLayer.addSublayer(skeletonLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(session: AVCaptureSession, points: [CGPoint], sensorSize: CGSize) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        self.points = points
        self.sensorSize = sensorSize
        configurePreviewConnection()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        skeletonLayer.frame = bounds
        configurePreviewConnection()
        drawSkeleton()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    private func configurePreviewConnection() {
        guard let connection = previewLayer.connection else { return }

        if let device = previewLayer.session?.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first?.device,
           rotationCoordinator?.device !== device {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]
            ) { [weak self] _, _ in
                DispatchQueue.main.async { self?.setNeedsLayout() }
            }
        }
        if let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview {
            let quarterTurn = (angle / 90).rounded() * 90
            let normalized = quarterTurn.truncatingRemainder(dividingBy: 360)
            if connection.isVideoRotationAngleSupported(normalized),
               connection.videoRotationAngle != normalized {
                connection.videoRotationAngle = normalized
            }
        }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }
    }

    private func drawSkeleton() {
        guard points.count == 21 else {
            skeletonLayer.path = nil
            return
        }

        let converted = points.map { point -> CGPoint? in
            guard point.x.isFinite, point.y.isFinite,
                  (0...1).contains(point.x), (0...1).contains(point.y)
            else { return nil }
            guard let connection = previewLayer.connection,
                  let rotation = SensorImageRotation(clockwiseDegrees: Double(connection.videoRotationAngle)),
                  let projected = ScannerAdapterGeometry.previewPoint(
                    sensorPoint: PixelPoint(x: Double(point.x), y: Double(point.y)),
                    rotation: rotation, mirrored: connection.isVideoMirrored,
                    sourceWidth: Double(sensorSize.width), sourceHeight: Double(sensorSize.height),
                    viewWidth: Double(bounds.width), viewHeight: Double(bounds.height)
                  ) else { return nil }
            return CGPoint(x: projected.x, y: projected.y)
        }

        let path = UIBezierPath()
        for (start, end) in Self.edges {
            guard let first = converted[start], let second = converted[end] else { continue }
            path.move(to: first)
            path.addLine(to: second)
        }
        for point in converted.compactMap({ $0 }) {
            path.append(UIBezierPath(ovalIn: CGRect(
                x: point.x - 3.5,
                y: point.y - 3.5,
                width: 7,
                height: 7
            )))
        }
        skeletonLayer.path = path.cgPath
    }

    private static let edges: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 4),
        (0, 5), (5, 6), (6, 7), (7, 8),
        (5, 9), (9, 10), (10, 11), (11, 12),
        (9, 13), (13, 14), (14, 15), (15, 16),
        (13, 17), (17, 18), (18, 19), (19, 20),
        (0, 17),
    ]
}
