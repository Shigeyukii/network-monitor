import Foundation
import SwiftData

@Model
final class DevicePosition {
    var deviceID: UUID
    var normalizedX: Double
    var normalizedY: Double

    init(deviceID: UUID) {
        self.deviceID = deviceID
        // ランダムな初期位置（画面端から少し内側）
        self.normalizedX = Double.random(in: 0.1...0.9)
        self.normalizedY = Double.random(in: 0.1...0.9)
    }
}
