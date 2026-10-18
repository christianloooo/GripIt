import Foundation
import JavaScriptCore

/// A fresh, thread-confined JS context evaluates the existing shared code.
/// No browser, network, API key, or second implementation of the rules is used.
public enum NativeFocusEngine {
  private static let script: Result<String, Error> = Result {
    guard let url = Bundle.module.url(forResource: "focus-engine", withExtension: "js") else {
      throw GripError.invalid("The feedback engine is missing. Please rebuild GripIt.")
    }
    return try String(contentsOf: url, encoding: .utf8)
  }

  public static func validate(_ draft: ThrowDraft) throws -> ThrowValidation {
    try call("validateJSON", input: draft)
  }

  public static func records(_ session: ThrowSessionDraft, pitch: PitchGrip,
    profileId: String, recordedAt: String = ISO8601DateFormatter().string(from: Date())) throws -> [ThrowRecord]
  {
    struct Options: Encodable { let handProfileId: String; let recordedAt: String }
    struct Input: Encodable { let session: ThrowSessionDraft; let pitchId: String; let options: Options }
    return try call("recordsJSON", input: Input(session: session, pitchId: pitch.rawValue,
      options: Options(handProfileId: profileId, recordedAt: recordedAt)))
  }

  public static func assess(pitch: PitchGrip, records: [ThrowRecord], zones: [GripZonePlan],
    gripPlanId: String) throws -> FocusAssessment
  {
    guard !records.isEmpty, records.allSatisfy({ $0.pitchId == pitch.rawValue && $0.schemaVersion.hasPrefix("1.") }) else {
      throw GripError.invalid("Enter at least one valid throw for this pitch.")
    }
    struct Input: Encodable {
      let pitchId: String
      let `throws`: [ThrowRecord]
      let zones: [GripZonePlan]
      let gripPlanId: String
    }
    return try call("assessJSON", input: Input(pitchId: pitch.rawValue, throws: records,
      zones: zones, gripPlanId: gripPlanId))
  }

  private static func call<Input: Encodable, Output: Decodable>(_ function: String, input: Input) throws -> Output {
    guard let context = JSContext() else { throw GripError.invalid("Could not start feedback. Please try again.") }
    var failure: String?
    context.exceptionHandler = { _, exception in failure = exception?.toString() ?? "Invalid feedback input." }
    context.evaluateScript(try script.get())
    guard failure == nil else { throw GripError.invalid(failure!) }
    let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
    let result = context.objectForKeyedSubscript("GripItFocus")?.forProperty(function)?.call(withArguments: [json])
    if let failure { throw GripError.invalid(failure) }
    guard let output = result?.toString(), let data = output.data(using: .utf8) else {
      throw GripError.invalid("Could not read feedback. Please try again.")
    }
    return try JSONDecoder().decode(Output.self, from: data)
  }
}
