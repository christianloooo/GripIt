import GripItScannerCore
import SwiftUI

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
