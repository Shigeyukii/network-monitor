import SwiftUI

struct StatusDot: View {
    var isUp: Bool?
    var isInMaintenance: Bool = false
    var size: CGFloat = 10

    private var color: Color {
        guard let isUp else { return .gray }
        return isUp ? .green : .red
    }

    var body: some View {
        if isInMaintenance {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: size * 1.1))
                .foregroundStyle(.orange)
        } else {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.6), radius: isUp == true ? 3 : 0)
        }
    }
}
