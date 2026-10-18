import AVFoundation
import Foundation
import GripItScannerCore
import SwiftUI
import UIKit

@MainActor
struct ScannerView: View {
    @StateObject private var model = ScannerViewModel()
    @Environment(\.scenePhase) private var scenePhase

    private let accent = Color.mint

    var body: some View {
        Group {
            switch model.phase {
            case .chooseHand:
                handSelection
            case .requestingPermission:
                permissionCheck
            case .scanning:
                scanner
            case .complete:
                results
            case .failed:
                failure
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .onChange(of: scenePhase) { _, phase in
            // Permission and share dialogs can make the scene temporarily inactive.
            // End capture only when the app actually moves to the background.
            if phase == .background {
                model.stop()
            }
        }
    }

    private var handSelection: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 58, weight: .light))
                    .foregroundStyle(accent)

                VStack(spacing: 8) {
                    Text("Which hand do you throw with?")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Prop up your phone with the screen facing you. Hold your hand 30–40 cm in front of the selfie camera.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 14) {
                    handButton("Left", hand: .left)
                    handButton("Right", hand: .right)
                }

                Spacer()
                Button("Load sample profile") {
                    model.loadSample()
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.75))
                Text("Sample mode does not use the camera.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
    }

    private func handButton(_ title: String, hand: Handedness) -> some View {
        Button {
            model.start(hand: hand)
        } label: {
            Text(title)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .foregroundStyle(.black)
    }

    private var permissionCheck: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(accent)
                Text("Checking camera…")
                    .font(.title2.bold())
                Text("GripIt uses the front TrueDepth camera to measure your hand. Images and depth data stay on this iPhone.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
    }

    private var scanner: some View {
        ZStack {
            CameraPreview(session: model.captureSession, points: model.points, sensorSize: model.sensorSize)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.78), .clear, .black.opacity(0.84)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                scanHeader
                Spacer()
                instructionCard
                scanFooter
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var scanHeader: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("View \(currentViewNumber) of \(ScanView.requiredOrder.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(viewName(model.currentView))
                        .font(.title2.bold())
                }
                Spacer()
                Button("Start over") {
                    model.reset()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.white)
            }

            HStack(spacing: 6) {
                ForEach(Array(ScanView.requiredOrder.enumerated()), id: \.offset) { index, view in
                    Capsule()
                        .fill(stepColor(index: index, view: view))
                        .frame(height: 5)
                        .accessibilityLabel("\(viewName(view)), step \(index + 1)")
                }
            }
        }
    }

    private var instructionCard: some View {
        HStack(spacing: 14) {
            if let arrow = instructionArrow {
                Image(systemName: arrow)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 38)
                    .accessibilityHidden(true)
            }
            Text(instruction)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan instruction")
        .accessibilityValue(instruction)
    }

    private var scanFooter: some View {
        HStack(alignment: .bottom, spacing: 14) {
            SkeletonCoverageView(fractions: model.jointFractions)
                .frame(width: 150)
                .padding(12)
                .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Overall")
                    Spacer()
                    Text("\(Int(clampedProgress * 100))%")
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))

                ProgressView(value: clampedProgress)
                    .tint(accent)

                Text(diagnosticsSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Accepted \(model.acceptedViewFrames)/8 frames")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    if isSampleProfile {
                        Text("SAMPLE PROFILE")
                            .font(.caption.bold())
                            .foregroundStyle(accent)
                    }
                    Label("Scan complete", systemImage: "checkmark.circle.fill")
                        .font(.largeTitle.bold())
                        .foregroundStyle(accent)
                    Text(isSampleProfile ? "Sample measurements are ready." : "Your hand profile is ready.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Experimental measurements. Check against a ruler. Thickness is unavailable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let profile = model.profile {
                    measurementSection(profile)
                    qualitySection(profile)
                } else {
                    Text("No hand profile is available.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    if let exportURL = model.exportURL {
                        ShareLink(item: exportURL) {
                            actionLabel("Export JSON", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .foregroundStyle(.black)
                    } else {
                        Button {
                            model.exportProfile()
                        } label: {
                            actionLabel("Prepare JSON export", systemImage: "doc.badge.gearshape")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .foregroundStyle(.black)
                        .disabled(model.profile == nil)
                    }

                    Button {
                        model.reset()
                    } label: {
                        actionLabel("Scan again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button("Load sample profile") {
                        model.loadSample()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .padding(24)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if model.profile != nil && model.exportURL == nil {
                model.exportProfile()
            }
        }
    }

    private func measurementSection(_ profile: HandProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Measurements")
                .font(.title2.bold())

            valueCard {
                measurementRow("Palm width", value: profile.measurements.palm.widthMm)
                Divider()
                measurementRow("Palm length", value: profile.measurements.palm.lengthMm)
                Divider()
                measurementRow("Palm thickness", value: profile.measurements.palm.thicknessMm)
            }

            Text("Finger segments")
                .font(.headline)

            valueCard {
                ForEach(Array(fingerResults(profile).enumerated()), id: \.element.id) { index, result in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(result.name)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(segmentText(result.measurement.segmentsMm))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        HStack {
                            Text("Thickness")
                            Spacer()
                            Text(millimeters(result.measurement.diameterMm))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                    if index < fingerResults(profile).count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func qualitySection(_ profile: HandProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan quality")
                .font(.title2.bold())
            valueCard {
                textRow("Views", value: profile.capture.coverage.capturedViews.joined(separator: ", "))
                Divider()
                textRow(
                    "Coverage",
                    value: "\(Int((profile.capture.coverage.fraction * 100).rounded()))%"
                )
                Divider()
                textRow(
                    "Hand label confidence",
                    value: "\(Int((profile.capture.confidence * 100).rounded()))%"
                )
                if !model.diagnostics.isEmpty {
                    Divider()
                    Text(model.diagnostics)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var failure: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.orange)
                Text("Scanner unavailable")
                    .font(.largeTitle.bold())
                Text(model.message.isEmpty ? "GripIt could not start the scanner." : model.message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if isCameraPermissionFailure {
                    Button("Open Settings") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .foregroundStyle(.black)

                    Button("Try again") {
                        model.start(hand: model.selectedHand)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                } else {
                    Button("Try again") {
                        model.start(hand: model.selectedHand)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .foregroundStyle(.black)
                }

                Button("Choose another hand") {
                    model.reset()
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button("Load sample profile") {
                    model.loadSample()
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(28)
        }
    }

    private var currentViewNumber: Int {
        guard let current = model.currentView,
              let index = ScanView.requiredOrder.firstIndex(of: current)
        else { return 1 }
        return index + 1
    }

    private var instruction: String {
        if !model.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return model.message
        }
        switch model.currentView {
        case .palm: return "Face your palm toward the camera."
        case .thumbSide: return "Turn until your thumb side faces the camera."
        case .back: return "Show the back of your hand."
        case .pinkySide: return "Turn until your pinky side faces the camera."
        case nil: return "Center your full hand."
        }
    }

    private var instructionArrow: String? {
        let message = instruction.lowercased()
        if message.contains("rotate left") { return "arrow.left" }
        if message.contains("rotate right") { return "arrow.right" }
        if message.contains("rotate") || model.currentView != .palm {
            return "arrow.triangle.2.circlepath"
        }
        return nil
    }

    private var diagnosticsSummary: String {
        let distance = model.distanceCm.map { " • \(Int($0.rounded())) cm" } ?? ""
        return "Depth \(model.validDepthCount)/21\(distance)"
    }

    private var clampedProgress: Double {
        min(max(model.progress, 0), 1)
    }

    private var isSampleProfile: Bool {
        guard let profile = model.profile else { return false }
        return profile.capture.method.localizedCaseInsensitiveContains("sample")
            || model.diagnostics.localizedCaseInsensitiveContains("sample")
    }

    private var isCameraPermissionFailure: Bool {
        let message = model.message.lowercased()
        return message.contains("camera access") || message.contains("settings")
    }

    private func viewName(_ view: ScanView?) -> String {
        switch view {
        case .palm: return "Palm"
        case .thumbSide: return "Thumb side"
        case .back: return "Back"
        case .pinkySide: return "Pinky side"
        case nil: return "Get ready"
        }
    }

    private func stepColor(index: Int, view: ScanView) -> Color {
        if index < currentViewNumber - 1 { return accent }
        if model.currentView == view { return .white }
        return .white.opacity(0.24)
    }

    private func millimeters(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Unavailable" }
        return String(format: "%.1f mm", value)
    }

    private func segmentText(_ values: [Double]) -> String {
        let valid = values.filter(\.isFinite)
        guard !valid.isEmpty else { return "Unavailable" }
        return valid.map { String(format: "%.1f", $0) }.joined(separator: " / ") + " mm"
    }

    private func fingerResults(_ profile: HandProfile) -> [FingerResult] {
        let fingers = profile.measurements.fingers
        return [
            FingerResult(name: "Thumb", measurement: fingers.thumb),
            FingerResult(name: "Index", measurement: fingers.index),
            FingerResult(name: "Middle", measurement: fingers.middle),
            FingerResult(name: "Ring", measurement: fingers.ring),
            FingerResult(name: "Pinky", measurement: fingers.pinky),
        ]
    }

    @ViewBuilder
    private func valueCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12, content: content)
            .padding(16)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func measurementRow(_ label: String, value: Double?) -> some View {
        textRow(label, value: millimeters(value))
    }

    private func textRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value.isEmpty ? "Unavailable" : value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 42)
    }
}

private struct FingerResult: Identifiable {
    let name: String
    let measurement: FingerMeasurements
    var id: String { name }
}
