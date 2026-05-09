import Foundation
import SwiftData

@Model
final class DeviceLink {
    var fromDeviceID: UUID
    var toDeviceID: UUID

    init(from: UUID, to: UUID) {
        self.fromDeviceID = from
        self.toDeviceID = to
    }

    /// 順序を問わず2デバイス間を結ぶリンクかどうか
    func connects(_ a: UUID, _ b: UUID) -> Bool {
        (fromDeviceID == a && toDeviceID == b) ||
        (fromDeviceID == b && toDeviceID == a)
    }
}
