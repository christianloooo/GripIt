import Foundation

/// Short display cues paraphrased from handInstructions.md. The full plan
/// stays available in Details; these strings never change the fitted grip.
public enum GripGuideCopy {
  public static func instruction(pitch: PitchGrip, zone: GripZoneID) -> String {
    switch (pitch, zone) {
    case (.fourSeam, .indexPad):
      "Place your index fingertip across the raised seam."
    case (.fourSeam, .middlePad):
      "Place your middle fingertip across the seam beside your index finger."
    case (.twoSeam, .indexPad):
      "Rest your index fingertip along the seam nearest your thumb."
    case (.twoSeam, .middlePad):
      "Rest your middle fingertip along the other close seam."
    case (.slider, .indexPad):
      "Rest your index finger lightly beside your middle finger, off the seam."
    case (.slider, .middlePad):
      "Hold the seam nearest your pinky with your middle fingertip."
    case (.circleChange, .indexPad):
      "Curl your index finger around the side of the ball near your thumb."
    case (.circleChange, .middlePad):
      "Rest your middle fingertip along the seam nearest your thumb."
    case (.circleChange, .ringSide):
      "Rest your ring fingertip along the other seam, beside your middle finger."
    case (.circleChange, .pinky):
      "Curl your pinky around the other side of the ball for light support."
    case (.circleChange, .thumbPad):
      "Wrap your thumb around the lower side of the ball to support it."
    case (.slider, .thumbPad):
      "Rest your thumb under the ball without pinching hard."
    case (_, .thumbPad):
      "Rest your thumb under the ball, below the gap between your index and middle fingers."
    case (_, .ringSide):
      "Rest the side of your ring finger against the ball for light support."
    case (_, .pinky):
      "Keep your pinky relaxed beside your ring finger, off the ball."
    case (.circleChange, .palm):
      "Let the ball sit comfortably in your hand without squeezing."
    case (.slider, .palm):
      "Hold the ball at a depth that feels comfortable."
    case (_, .palm):
      "Leave a little space between the ball and your palm."
    case (_, .wrist):
      "Keep your wrist steady while you hold the ball."
    }
  }
}
