import AVFoundation
import Foundation
import GripItScannerCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct ScannerView: View {
    @StateObject private var model = ScannerViewModel()
    @State private var showGrips = false
    @State private var importProfile = false
    @State private var importError: String?
    @Environment(\.scenePhase) private var scenePhase

    private let accent = Color.mint
    private let pinePrimary = Color(red: 0.106, green: 0.263, blue: 0.196)
    private let pineSecondary = Color(red: 0.176, green: 0.416, blue: 0.310)
    private let pineTint = Color(red: 0.910, green: 0.945, blue: 0.925)
    private let pineTintBorder = Color(red: 0.769, green: 0.851, blue: 0.808)
    private let landingCanvas = Color(red: 0.969, green: 0.976, blue: 0.969)
    private let landingMuted = Color(red: 0.945, green: 0.961, blue: 0.949)
    private let landingBorder = Color(red: 0.886, green: 0.910, blue: 0.894)
    private let landingOutline = Color(red: 0.796, green: 0.835, blue: 0.808)
    private let landingInk = Color(red: 0.059, green: 0.118, blue: 0.086)
    private let landingMutedInk = Color(red: 0.322, green: 0.388, blue: 0.345)

    private var usesLightLandingTheme: Bool {
        model.phase == .chooseHand || model.phase == .requestingPermission
    }

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
        .fileImporter(isPresented: $importProfile, allowedContentTypes: [.json]) { result in
            do { try model.loadProfile(from: result.get()) }
            catch { importError = error.localizedDescription }
        }
        .alert("Could not import hand profile", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
        .fullScreenCover(isPresented: $showGrips) {
            if let profile = model.profile { GripViewerView(profile: profile) }
        }
        .preferredColorScheme(usesLightLandingTheme ? .light : .dark)
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
            landingCanvas.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(pinePrimary)
                                .frame(width: 8, height: 8)
                            Text("gripit.")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundStyle(landingInk)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Image(systemName: "camera.metering.matrix")
                                .font(.system(size: 11, weight: .semibold))
                            Text("TrueDepth Scan")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(pinePrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(pineTint, in: Capsule())
                        .overlay {
                            Capsule().stroke(pineTintBorder, lineWidth: 1)
                        }
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .top) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(pineTint)
                                    .frame(width: 46, height: 46)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(pineTintBorder, lineWidth: 1)
                                    }
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(pinePrimary)
                            }

                            Spacer()

                            Text("STEP 01 · HAND PROFILE")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(landingMutedInk)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(landingMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(landingBorder, lineWidth: 1)
                                }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Which hand do you throw with?")
                                .font(.system(size: 28, weight: .bold))
                                .tracking(-0.6)
                                .foregroundStyle(landingInk)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Select your throwing hand to calibrate your 3D grip model and start the front-camera measurement scan.")
                                .font(.subheadline)
                                .foregroundStyle(landingMutedInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("SETUP CHECKLIST")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(pinePrimary)

                            setupStepRow(
                                icon: "iphone",
                                text: "Prop up your phone with the screen facing you."
                            )
                            setupStepRow(
                                icon: "viewfinder",
                                text: "Hold your hand 30–40 cm in front of the selfie camera."
                            )
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(landingMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(landingBorder, lineWidth: 1)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("CHOOSE THROWING HAND")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(landingMutedInk)

                            HStack(spacing: 12) {
                                handButton("Left", subtitle: "Left-handed", hand: .left)
                                handButton("Right", subtitle: "Right-handed", hand: .right)
                            }
                        }

                        HStack(spacing: 10) {
                            Rectangle()
                                .fill(landingBorder)
                                .frame(height: 1)
                            Text("OR EXPLORE WITHOUT CAMERA")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.7)
                                .foregroundStyle(landingMutedInk)
                                .lineLimit(1)
                                .fixedSize()
                            Rectangle()
                                .fill(landingBorder)
                                .frame(height: 1)
                        }

                        VStack(spacing: 10) {
                            Button {
                                model.loadSample()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "cube.transparent")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(pinePrimary)
                                    Text("Load sample profile")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(landingInk)
                                    Spacer()
                                    Text("Instant")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(pinePrimary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(pineTint, in: Capsule())
                                }
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(landingOutline, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                importProfile = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(pinePrimary)
                                    Text("Import hand profile JSON")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(landingInk)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(landingMutedInk)
                                }
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(landingMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(landingBorder, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(22)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(landingBorder, lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 6)

                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(pinePrimary)
                        Text("Sample mode does not use the camera. All TrueDepth scans stay on-device.")
                            .font(.caption)
                            .foregroundStyle(landingMutedInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func setupStepRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pinePrimary)
                .frame(width: 26, height: 26)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(landingBorder, lineWidth: 1)
                }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(landingInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func handButton(_ title: String, subtitle: String, hand: Handedness) -> some View {
        Button {
            model.start(hand: hand)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 34, height: 34)
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .scaleEffect(x: hand == .left ? -1 : 1, y: 1)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background(pinePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(pineSecondary, lineWidth: 1)
            }
            .shadow(color: pinePrimary.opacity(0.18), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var permissionCheck: some View {
        ZStack {
            landingCanvas.ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(pineTint)
                        .frame(width: 52, height: 52)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(pineTintBorder, lineWidth: 1)
                        }
                    ProgressView()
                        .controlSize(.regular)
                        .tint(pinePrimary)
                }
                Text("Checking camera…")
                    .font(.title3.bold())
                    .foregroundStyle(landingInk)
                Text("GripIt uses the front TrueDepth camera to measure your hand. Images and depth data stay on this iPhone.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(landingMutedInk)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(landingBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 6)
            .padding(24)
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
                if model.showGatePanel { gatePanel }
                Spacer()
                instructionCard
                scanFooter
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    /// Shows which gate is holding the scan and the values it decided on. The
    /// guidance line alone could not distinguish "wrong pose" from "pose fine,
    /// depth missing", which is what made the device stall hard to pin down.
    private var gatePanel: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(model.gate.rows, id: \.0) { label, value in
                HStack(alignment: .top, spacing: 6) {
                    Text(label)
                        .frame(width: 66, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .foregroundStyle(label == "blocked by" ? accent : .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .padding(10)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan gate diagnostics")
        .accessibilityValue(model.gate.rows.map { "\($0.0) \($0.1)" }.joined(separator: ", "))
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
                Button {
                    model.showGatePanel.toggle()
                } label: {
                    Image(systemName: model.showGatePanel
                        ? "stethoscope.circle.fill" : "stethoscope.circle")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .accessibilityLabel(model.showGatePanel
                    ? "Hide scan gate diagnostics" : "Show scan gate diagnostics")
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
                Text(model.trackingStatus)
                    .font(.caption2)
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
                    Button { showGrips = true } label: {
                        actionLabel("Explore my grips", systemImage: "baseball")
                    }
                    .buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
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
                    "Initial hand identity confidence",
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
        case .thumbSide: return "Turn your thumb slightly toward the camera. Keep every finger visible."
        case .back: return "Show the back of your hand."
        case .pinkySide: return "Turn your pinky slightly toward the camera. Keep every finger visible."
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
