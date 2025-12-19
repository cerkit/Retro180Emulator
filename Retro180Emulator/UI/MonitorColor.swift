import SwiftUI

public enum MonitorColor: String, CaseIterable, Identifiable {
    case amber
    case green

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .amber:
            return Color(red: 1.0, green: 0.7, blue: 0.0)
        case .green:
            return Color(red: 0.2, green: 1.0, blue: 0.2)
        }
    }
}
