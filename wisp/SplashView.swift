import SwiftUI

private let avatarSize: CGFloat = 44
private let avatarGap: CGFloat = 4

struct SplashView: View {
    @State private var viewModel = SplashViewModel()

    var onSignUp: () -> Void = {}
    var onLogIn: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let cols = max(1, Int((geo.size.width + avatarGap) / (avatarSize + avatarGap)))
            let maxVisibleRows = Int((geo.size.height + avatarGap) / (avatarSize + avatarGap)) + 1
            let maxVisibleCount = maxVisibleRows * cols
            let pics: [String] = {
                if viewModel.profilePictures.isEmpty {
                    return Array(repeating: "", count: maxVisibleCount)
                }
                return Array(viewModel.profilePictures.prefix(maxVisibleCount))
            }()
            let rows = (pics.count + cols - 1) / cols

            ZStack {
                // Avatar grid pinned to top, clipped to screen bounds
                VStack(spacing: avatarGap) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: avatarGap) {
                            ForEach(0..<cols, id: \.self) { col in
                                let idx = row * cols + col
                                if idx < pics.count {
                                    AvatarCircle(url: pics[idx])
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()

                // Gradient fades the collage into the background
                LinearGradient(
                    colors: [.clear, Color.wispBackground],
                    startPoint: UnitPoint(x: 0.5, y: 0.25),
                    endPoint: UnitPoint(x: 0.5, y: 0.72)
                )

                // Logo, title, and action buttons pinned to bottom
                VStack(spacing: 0) {
                    Spacer()

                    AnimatedLogo()

                    Text("wisp")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(.white)

                    if let online = viewModel.onlineCount {
                        OnlineCard(count: online)
                            .padding(.top, 16)
                    }

                    Spacer().frame(height: 32)

                    Button(action: onSignUp) {
                        Text("Create Account")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.wispPrimary)
                    .controlSize(.large)

                    Spacer().frame(height: 8)

                    Button(action: onLogIn) {
                        Text("Log In")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.wispPrimary)
                    .controlSize(.large)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .background(Color.wispBackground)
        .ignoresSafeArea()
        .onDisappear { viewModel.cancel() }
    }
}

private struct AvatarCircle: View {
    let url: String

    var body: some View {
        if url.isEmpty {
            Circle()
                .fill(Color.wispSurfaceVariant)
                .frame(width: avatarSize, height: avatarSize)
        } else {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Circle().fill(Color.wispSurfaceVariant)
                default:
                    Circle().fill(Color.wispSurfaceVariant)
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
        }
    }
}

private struct OnlineCard: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0x4C/255.0, green: 0xAF/255.0, blue: 0x50/255.0))
                .frame(width: 8, height: 8)
            Text("\(formatCount(count)) people online now")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.wispSurface, in: RoundedRectangle(cornerRadius: 24))
    }

    private func formatCount(_ n: Int) -> String {
        switch n {
        case 1_000_000...: String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: String(format: "%.1fk", Double(n) / 1_000)
        default: "\(n)"
        }
    }
}

private struct AnimatedLogo: View {
    @State private var bob = false
    @State private var sway = false

    var body: some View {
        Image("WispLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .offset(y: bob ? -8 : 0)
            .rotationEffect(.degrees(sway ? 3 : -3))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    bob = true
                }
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: true)) {
                    sway = true
                }
            }
    }
}

// Legacy palette accessors. Prefer `@Environment(\.theme)` and `theme.palette.*` /
// `theme.primary` directly in new code — these globals reflect the active theme by
// reading `AppSettings.shared.resolveTheme(...)` synchronously. They live on for the
// many existing call sites that haven't been migrated yet.
extension Color {
    @MainActor static var wispBackground: Color { ResolvedThemeProxy.current.palette.background }
    @MainActor static var wispSurface: Color { ResolvedThemeProxy.current.palette.surface }
    @MainActor static var wispSurfaceVariant: Color { ResolvedThemeProxy.current.palette.surfaceVariant }
    @MainActor static var wispPrimary: Color { ResolvedThemeProxy.current.primary }
    @MainActor static var wispZapColor: Color { ResolvedThemeProxy.current.palette.zap }
    @MainActor static var wispRepostColor: Color { ResolvedThemeProxy.current.palette.repost }
    @MainActor static var wispBookmarkColor: Color { ResolvedThemeProxy.current.palette.bookmark }
    @MainActor static var wispPaidColor: Color { ResolvedThemeProxy.current.palette.paid }
    @MainActor static var wispOnSurface: Color { ResolvedThemeProxy.current.palette.onSurface }
    @MainActor static var wispOnSurfaceVariant: Color { ResolvedThemeProxy.current.palette.onSurfaceVariant }
    @MainActor static var wispOutline: Color { ResolvedThemeProxy.current.palette.outline }
}

@MainActor
enum ResolvedThemeProxy {
    /// Last-resolved theme. Updated by the root view via `update(_:)` whenever
    /// `AppSettings` or the system color scheme change. Reads from this proxy do
    /// not subscribe to settings changes — but each `View.body` re-evaluation
    /// reads fresh, which is enough for SwiftUI's normal redraw cycle.
    static var current: ResolvedTheme = AppSettings.shared.resolveTheme(systemColorScheme: nil)

    static func update(_ theme: ResolvedTheme) {
        current = theme
    }
}

#Preview {
    SplashView()
}
