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
    @State private var showProfileDetails = false
    @State private var importError: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = GripItTheme.accent
    private let pinePrimary = GripItTheme.text
    private let pineSecondary = GripItTheme.secondary
    private let pineTint = GripItTheme.surface
    private let pineTintBorder = GripItTheme.edge
    private let landingCanvas = GripItTheme.background
    private let landingBorder = GripItTheme.edge
    private let landingInk = GripItTheme.text
    private let landingMutedInk = GripItTheme.secondary

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
            if let profile = model.profile { GripViewerView(profile: profile).id(try? HandProfileCodec.encode(profile)) }
        }
        .sheet(isPresented: $showProfileDetails) { profileDetails }
        .preferredColorScheme(.dark)
        .foregroundStyle(GripItTheme.text).tint(GripItTheme.text)
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--scan-results-preview"), model.phase == .chooseHand {
                model.loadSample()
                showProfileDetails = ProcessInfo.processInfo.arguments.contains("--profile-details-preview")
            }
        }
        #endif
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.phase)
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
            GripItBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 36) {
                    pageHeader
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Find your\ngrip.")
                            .font(.system(size: 44, weight: .semibold))
                            .tracking(-1.5).foregroundStyle(landingInk)
                        Text("Scan your throwing hand to get started.")
                            .font(.subheadline).foregroundStyle(landingMutedInk)
                            .lineLimit(1).minimumScaleFactor(0.65).allowsTightening(true)
                            .padding(.top, 16)
                        handIllustration
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 34)
                            .accessibilityHidden(true)
                        Text("Your throwing hand")
                            .font(.subheadline.weight(.medium)).foregroundStyle(landingInk)
                            .padding(.bottom, 12)
                        HStack(spacing: 4) {
                            handChoice("Left", hand: .left)
                            handChoice("Right", hand: .right)
                        }
                        .padding(5)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(landingBorder, lineWidth: 1))
                    }
                    .padding(24).gripitGlassSurface(radius: 26)
                }
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
                .frame(maxWidth: 500).frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Button { model.start(hand: model.selectedHand) } label: {
                    primaryLabel("Scan my hand", icon: "arrow-right")
                }
                .buttonStyle(GripItGlassButtonStyle(kind: .primary))
                .accessibilityIdentifier("start-hand-scan")
                Button { model.loadSample() } label: {
                    Text("Try a sample hand").font(.subheadline).frame(minHeight: 36)
                }
                .buttonStyle(GripItGlassButtonStyle(kind: .quiet))
                .accessibilityIdentifier("load-sample-hand")
                Label("Your scan stays on your phone", systemImage: "lock")
                    .font(.caption).foregroundStyle(landingMutedInk)
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: 500).frame(maxWidth: .infinity)
            .background(GripItTheme.background.opacity(0.88))
        }
    }

    private var pageHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Text("gripit.").font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(landingInk)
            }
            Spacer()
            Menu {
                Button("Import saved hand", systemImage: "square.and.arrow.down") {
                    importProfile = true
                }
                if model.phase == .complete {
                    if let url = model.exportURL {
                        ShareLink(item: url) { Label("Export hand profile", systemImage: "square.and.arrow.up") }
                    }
                    Button("Scan again", systemImage: "arrow.clockwise") { model.reset() }
                }
            } label: {
                lucide("ellipsis", size: 22)
                    .foregroundStyle(landingMutedInk)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(landingBorder, lineWidth: 1))
            }
            .accessibilityLabel("Hand profile options")
        }
    }

    private var handIllustration: some View {
        ZStack {
            GripItScanCorners().stroke(GripItTheme.accent.opacity(0.7), lineWidth: 2)
            lucide("hand", size: 68)
                .foregroundStyle(GripItTheme.text)
                .rotationEffect(.degrees(-20))
        }.frame(width: 90, height: 90)
    }

    private func handChoice(_ title: String, hand: Handedness) -> some View {
        let selected = model.selectedHand == hand
        return Button { model.selectedHand = hand } label: {
            HStack(spacing: 8) {
                lucide("hand", size: 18).scaleEffect(x: hand == .left ? -1 : 1, y: 1)
                Text(title).font(.subheadline.weight(.semibold))
                if selected { lucide("check", size: 16) }
            }
            .foregroundStyle(selected ? landingInk : landingMutedInk)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selected ? GripItTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(selected ? 0.24 : 0), lineWidth: 1))
            .shadow(color: .black.opacity(selected ? 0.04 : 0), radius: 3, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(GripItGlassButtonStyle(kind: .quiet))
        .accessibilityLabel("\(title) throwing hand")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("select-\(hand.rawValue)-hand")
    }

    private func lucide(_ name: String, size: CGFloat = 20) -> some View {
        Image("lucide-\(name)").renderingMode(.template)
            .resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private func primaryLabel(_ title: String, icon: String = "arrow-right") -> some View {
        HStack(spacing: 12) {
            Text(title).font(.headline)
            Spacer(minLength: 8)
            lucide(icon)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
    }

    private var permissionCheck: some View {
        ZStack {
            GripItBackdrop()
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
                Text("Allow camera access to scan your hand.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(landingMutedInk)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .gripitGlassSurface(radius: 18)
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
                Menu {
                    Button("Start over", systemImage: "arrow.counterclockwise") {
                        model.reset()
                    }
                    Toggle("Scan details", isOn: $model.showGatePanel)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .tint(.white)
                .accessibilityLabel("Scan options")
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
        .gripitGlassSurface(radius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan instruction")
        .accessibilityValue(instruction)
    }

    private var scanFooter: some View {
        HStack(alignment: .bottom, spacing: 12) {
            SkeletonCoverageView(fractions: model.jointFractions)
                .frame(width: 64)
                .padding(8)
                .gripitGlassSurface(radius: 12)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Scan progress")
                    Spacer()
                    Text("\(Int(clampedProgress * 100))%")
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))

                ProgressView(value: clampedProgress)
                    .tint(accent)

            }
            .padding(14)
            .gripitGlassSurface(radius: 16)
        }
    }

    private var results: some View {
        ZStack {
            GripItBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    pageHeader
                    VStack(alignment: .leading, spacing: 16) {
                        lucide("check", size: 28)
                            .foregroundStyle(pinePrimary)
                            .frame(width: 60, height: 60)
                            .background(pineTint, in: RoundedRectangle(cornerRadius: 18))
                        if isSampleProfile {
                            Text("SAMPLE HAND").font(.caption2.weight(.semibold))
                                .tracking(1).foregroundStyle(pineSecondary)
                        }
                        Text(isSampleProfile ? "Meet your sample hand." : "Your hand is ready.")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .tracking(-0.8).foregroundStyle(landingInk)
                        Text("Next, find a grip that fits.")
                            .font(.body).foregroundStyle(landingMutedInk)
                    }
                    if let profile = model.profile {
                        VStack(alignment: .leading, spacing: 22) {
                            HStack(spacing: 10) {
                                lucide("hand").foregroundStyle(pinePrimary)
                                Text("\(profile.handedness.rawValue.capitalized) hand")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(isSampleProfile ? "Sample" : "Profile ready")
                                    .font(.caption).foregroundStyle(landingMutedInk)
                            }
                            Divider().overlay(landingBorder)
                            HStack(alignment: .top, spacing: 20) {
                                summaryMetric("Palm span", value: profile.measurements.palm.widthMm)
                                summaryMetric("Palm length", value: profile.measurements.palm.lengthMm)
                            }
                        }
                        .padding(22)
                        .gripitGlassSurface(radius: 20)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(landingBorder, lineWidth: 1))
                        Button { showProfileDetails = true } label: {
                            HStack(spacing: 10) {
                                lucide("ruler", size: 18)
                                Text("View measurements").font(.subheadline.weight(.medium))
                                Spacer()
                                lucide("chevron-right", size: 18)
                            }
                            .foregroundStyle(landingMutedInk)
                            .frame(minHeight: 48).contentShape(Rectangle())
                        }
                        .buttonStyle(GripItGlassButtonStyle(kind: .quiet))
                        .accessibilityIdentifier("view-hand-measurements")
                        if isSampleProfile {
                            Text("Example measurements, not a scan of your hand.")
                                .font(.footnote).foregroundStyle(landingMutedInk)
                        }
                    } else {
                        Text("No hand profile is available.").foregroundStyle(landingMutedInk)
                    }
                }
                .padding(24)
                .frame(maxWidth: 500).frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button { showGrips = true } label: { primaryLabel("Explore my grips") }
                    .buttonStyle(GripItGlassButtonStyle(kind: .primary))
                    .disabled(model.profile == nil)
                    .accessibilityIdentifier("explore-my-grips")
                Button("Scan again") { model.reset() }
                    .buttonStyle(GripItGlassButtonStyle(kind: .quiet))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(landingMutedInk).frame(minHeight: 44)
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: 500).frame(maxWidth: .infinity).background(landingCanvas)
        }
        .onAppear {
            if model.profile != nil && model.exportURL == nil { model.exportProfile() }
        }
    }

    private func summaryMetric(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(landingMutedInk)
            Text(millimeters(value)).font(.title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(landingInk)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileDetails: some View {
        NavigationStack {
            ScrollView {
                if let profile = model.profile {
                    VStack(alignment: .leading, spacing: 24) {
                        if isSampleProfile {
                            Label("Sample hand", systemImage: "info.circle")
                                .font(.subheadline).foregroundStyle(pineSecondary)
                        }
                        Text("Approximate measurements. Check against a ruler. Thickness is estimated in the grip model.")
                            .font(.footnote).foregroundStyle(landingMutedInk)
                        measurementSection(profile)
                        qualitySection(profile)
                        if let url = model.exportURL {
                            ShareLink(item: url) {
                                primaryLabel("Export hand profile", icon: "upload")
                            }
                            .buttonStyle(GripItGlassButtonStyle(kind: .primary))
                        } else {
                            Button("Prepare export") { model.exportProfile() }
                                .buttonStyle(GripItGlassButtonStyle())
                        }
                    }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(landingInk)
            .background(GripItBackdrop())
            .navigationTitle("Hand measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showProfileDetails = false }.tint(pinePrimary)
                }
            }
        }
        .gripitScreen()
        .presentationDragIndicator(.visible)
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
            GripItBackdrop()
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
                    .buttonStyle(GripItGlassButtonStyle(kind: .primary))
                    .tint(accent)
                    .foregroundStyle(GripItTheme.text)

                    Button("Try again") {
                        model.start(hand: model.selectedHand)
                    }
                    .buttonStyle(GripItGlassButtonStyle())
                    .tint(.white)
                } else {
                    Button("Try again") {
                        model.start(hand: model.selectedHand)
                    }
                    .buttonStyle(GripItGlassButtonStyle(kind: .primary))
                    .tint(accent)
                    .foregroundStyle(GripItTheme.text)
                }

                Button("Choose another hand") {
                    model.reset()
                }
                .buttonStyle(GripItGlassButtonStyle())
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
            .gripitGlassSurface(radius: 16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(landingBorder, lineWidth: 1))
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
