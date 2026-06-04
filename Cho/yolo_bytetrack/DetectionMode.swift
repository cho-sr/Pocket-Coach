import Foundation

enum DetectionMode: String, CaseIterable, Identifiable {
    case detect
    case testImage
    case live

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .detect:
            return "Detect"
        case .testImage:
            return "Test Image"
        case .live:
            return "Live"
        }
    }

    var subtitle: String {
        switch self {
        case .detect:
            return "Run one detection on the latest camera frame."
        case .testImage:
            return "Run detection on bundled test_1.jpg through test_3.jpg."
        case .live:
            return "Check real-time model detection without MIDI output."
        }
    }
}
