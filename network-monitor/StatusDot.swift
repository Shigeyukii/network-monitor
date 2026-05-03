import SwiftUI

struct StatusDot: View {
    var isUp: Bool?
    var size: CGFloat = 10

    private var color: Color {
        guard let isUp else { return .gray }
        return isUp ? .green : .red
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.6), radius: isUp == true ? 3 : 0)
    }
}
