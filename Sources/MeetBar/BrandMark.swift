import SwiftUI

struct MeetBarBrandMark: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.42, blue: 0.98),
                            Color(red: 0.38, green: 0.24, blue: 0.91)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "video.fill")
                .font(.system(size: size * 0.39, weight: .semibold))
                .foregroundStyle(.white)

            Image(systemName: "sparkle")
                .font(.system(size: size * 0.20, weight: .bold))
                .foregroundStyle(Color(red: 0.36, green: 0.96, blue: 0.76))
                .offset(x: size * 0.25, y: -size * 0.25)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct MeetBarMenuBarMark: View {
    var body: some View {
        ZStack {
            Image(systemName: "video.fill")
                .font(.system(size: 13, weight: .semibold))
            Image(systemName: "sparkle")
                .font(.system(size: 6, weight: .bold))
                .offset(x: 8, y: -6)
        }
        .frame(width: 22, height: 18)
        .accessibilityLabel("MeetBar")
    }
}
