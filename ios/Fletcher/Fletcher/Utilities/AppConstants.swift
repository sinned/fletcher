import Foundation
import CoreLocation

enum AppConstants {
    enum Sync {
        static let batchSize = 100
        static let intervalSeconds: TimeInterval = 300 // 5 minutes
    }
    
    enum Map {
        static let zoomFactor = 2.0
        static let defaultSpanDelta = 0.05
    }
    
    enum Defaults {
        static let retentionDays = 30
    }
}
