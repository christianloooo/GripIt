import GripItScannerCore
import SwiftUI
import UIKit

@main
struct GripItApp: App {
  var body: some Scene {
    WindowGroup {
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--hand-model-preview"),
          let profile = try? SampleHandProfiles.averageRight()
        {
          HandModelReviewView(
            profile: profile,
            initialCamera: ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--camera=") }
              .flatMap { GripCamera(rawValue: String($0.dropFirst(9))) } ?? .palm,
            initialFlexion: ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--flexion=") }
              .flatMap { Double($0.dropFirst(10)) } ?? 0,
            initialWireframe: ProcessInfo.processInfo.arguments.contains("--wireframe"))
        } else if ProcessInfo.processInfo.arguments.contains("--grip-preview"),
          let sample = SavedHandProfile.latest()
            ?? (ProcessInfo.processInfo.arguments.contains("--sample-hand-preview")
              ? try? SampleHandProfiles.averageRight() : nil)
        {
          let profile =
            ProcessInfo.processInfo.arguments.contains("--left")
            ? HandProfile(
              profileId: sample.profileId, createdAt: sample.createdAt, handedness: .left,
              measurements: sample.measurements, landmarks: sample.landmarks,
              capture: sample.capture) : sample
          let cameraArgument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--camera=") }
          let camera =
            cameraArgument.flatMap { GripCamera(rawValue: String($0.dropFirst(9))) }
            ?? .threeQuarter
          let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--pitch=") }
          GripViewerView(
            profile: profile,
            initialPitch: argument.flatMap { PitchGrip(rawValue: String($0.dropFirst(8))) }
              ?? .fourSeam, initialCamera: camera,
            initialZone: ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--zone=") }
              .flatMap { GripZoneID(rawValue: String($0.dropFirst(7))) })
        } else {
          ScannerView()
        }
      #else
        ScannerView()
      #endif
    }
  }
}

/// Shared presentation tokens. Feedback and grip-effort colors keep their
/// own meanings; this palette only styles the surrounding interface.
enum GripItTheme {
  static let background = Color(red: 13.0 / 255, green: 43.0 / 255, blue: 33.0 / 255)
  static let pine = Color(red: 21.0 / 255, green: 62.0 / 255, blue: 47.0 / 255)
  static let surface = Color(red: 27.0 / 255, green: 63.0 / 255, blue: 49.0 / 255)
  static let raised = Color(red: 42.0 / 255, green: 81.0 / 255, blue: 65.0 / 255)
  static let text = Color(red: 246.0 / 255, green: 250.0 / 255, blue: 246.0 / 255)
  static let secondary = Color(red: 197.0 / 255, green: 216.0 / 255, blue: 204.0 / 255)
  static let accent = Color(red: 182.0 / 255, green: 211.0 / 255, blue: 192.0 / 255)
  static let edge = Color.white.opacity(0.16)
}

struct GripItBackdrop: View {
  var body: some View {
    ZStack {
      GripItTheme.background
      RadialGradient(colors: [Color(red: 0.33, green: 0.52, blue: 0.39).opacity(0.32), .clear],
        center: .topTrailing, startRadius: 0, endRadius: 620)
    }.ignoresSafeArea().allowsHitTesting(false)
  }
}

private struct GripItGlassSurface: ViewModifier {
  let radius: CGFloat
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  func body(content: Content) -> some View {
    content
      .background(GripItTheme.surface.opacity(reduceTransparency ? 1 : 0.62), in: RoundedRectangle(cornerRadius: radius))
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
      .overlay(RoundedRectangle(cornerRadius: radius)
        .stroke(GripItTheme.edge, lineWidth: 1).allowsHitTesting(false))
  }
}

extension View {
  func gripitScreen() -> some View {
    foregroundStyle(GripItTheme.text)
      .tint(GripItTheme.text)
      .background(GripItBackdrop())
      .preferredColorScheme(.dark)
      .toolbarBackground(GripItTheme.pine.opacity(0.94), for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
  }

  func gripitGlassSurface(radius: CGFloat = 24) -> some View {
    modifier(GripItGlassSurface(radius: radius))
  }
}

struct GripItGlassButtonStyle: ButtonStyle {
  enum Kind { case primary, secondary, quiet }
  var kind: Kind = .secondary
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.isEnabled) private var enabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(GripItTheme.text)
      .padding(.horizontal, kind == .quiet ? 4 : 14)
      .padding(.vertical, kind == .quiet ? 4 : 9)
      .background {
        if kind != .quiet {
          RoundedRectangle(cornerRadius: 17)
            .fill((kind == .primary ? GripItTheme.raised : GripItTheme.surface)
              .opacity(reduceTransparency ? 1 : configuration.isPressed ? 0.94 : 0.68))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17)
              .stroke(.white.opacity(configuration.isPressed ? 0.38 : 0.22), lineWidth: 1))
            .overlay(alignment: .top) {
              RoundedRectangle(cornerRadius: 17)
                .fill(LinearGradient(colors: [.white.opacity(0.10), .clear],
                  startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
      }
      .opacity(enabled ? (kind == .quiet && configuration.isPressed ? 0.68 : 1) : 0.42)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
  }
}

struct GripItScanCorners: Shape {
  func path(in rect: CGRect) -> Path {
    let length: CGFloat = 19
    let radius: CGFloat = 8
    var p = Path()
    p.move(to: CGPoint(x: 0, y: length)); p.addLine(to: CGPoint(x: 0, y: radius))
    p.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
    p.addLine(to: CGPoint(x: length, y: 0))
    p.move(to: CGPoint(x: rect.maxX - length, y: 0)); p.addLine(to: CGPoint(x: rect.maxX - radius, y: 0))
    p.addQuadCurve(to: CGPoint(x: rect.maxX, y: radius), control: CGPoint(x: rect.maxX, y: 0))
    p.addLine(to: CGPoint(x: rect.maxX, y: length))
    p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    p.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
    p.move(to: CGPoint(x: length, y: rect.maxY)); p.addLine(to: CGPoint(x: radius, y: rect.maxY))
    p.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - radius), control: CGPoint(x: 0, y: rect.maxY))
    p.addLine(to: CGPoint(x: 0, y: rect.maxY - length))
    return p
  }
}
