import Foundation

public enum SampleHandProfileError: Error, Equatable, Sendable {
    case missingBundledProfile(String)
}

public enum SampleHandProfiles {
    public static func averageRight() throws -> HandProfile {
        let name = "hand-profile-average-right"
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw SampleHandProfileError.missingBundledProfile(name)
        }
        return try HandProfileCodec.decode(Data(contentsOf: url))
    }
}
