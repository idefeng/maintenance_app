import SwiftUI

// MARK: - GlassCard Modifier
public struct GlassCardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

public extension View {
    func glassCard() -> some View {
        self.modifier(GlassCardModifier())
    }
}

// MARK: - Hover Scale Effect
public struct HoverScaleModifier: ViewModifier {
    @State private var isHovered = false
    
    public func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 0.99 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6, blendDuration: 0), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

public extension View {
    func hoverScale() -> some View {
        self.modifier(HoverScaleModifier())
    }
}

// MARK: - Pulse Glow Indicator (呼吸状态指示灯)
public struct PulseGlowIndicator: View {
    let color: Color
    let active: Bool
    
    @State private var isPulsing = false
    
    public init(color: Color, active: Bool = true) {
        self.color = color
        self.active = active
    }
    
    public var body: some View {
        ZStack {
            if active {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 2.0 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                    .onAppear {
                        withAnimation(
                            Animation.easeInOut(duration: 1.8)
                                .repeatForever(autoreverses: false)
                        ) {
                            isPulsing = true
                        }
                    }
            }
            
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.4), radius: active ? 4 : 0)
        }
        .frame(width: 16, height: 16)
    }
}
