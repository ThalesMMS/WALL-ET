import SwiftUI

struct ModernTheme {
    
    // MARK: - Colors
    struct Colors {
        static let primary = Color("BitcoinOrange", bundle: .main)
            .opacity(1.0)
        static let primaryGradient = LinearGradient(
            colors: [Color(hex: "#F7931A"), Color(hex: "#FFA500")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let background = Color(light: .white, dark: Color(hex: "#0A0A0A"))
        static let secondaryBackground = Color(light: Color(hex: "#F8F9FA"), dark: Color(hex: "#1A1A1A"))
        static let tertiaryBackground = Color(light: Color(hex: "#FFFFFF"), dark: Color(hex: "#2A2A2A"))
        
        static let cardBackground = Color(light: .white, dark: Color(hex: "#1E1E1E"))
        static let cardBorder = Color(light: Color.gray.opacity(0.1), dark: Color.gray.opacity(0.2))
        
        static let success = Color(hex: "#34C759")
        static let warning = Color(hex: "#FF9500")
        static let error = Color(hex: "#FF3B30")
        static let info = Color(hex: "#007AFF")
        
        static let textPrimary = Color(light: Color(hex: "#000000"), dark: Color(hex: "#FFFFFF"))
        static let textSecondary = Color(light: Color(hex: "#6C7581"), dark: Color(hex: "#9CA3AF"))
        static let textTertiary = Color(light: Color(hex: "#9CA3AF"), dark: Color(hex: "#6B7280"))
        
        static let positive = Color(hex: "#10B981")
        static let negative = Color(hex: "#EF4444")
    }
    
    // MARK: - Typography
    struct Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let callout = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
        
        // Custom styles
        static let balance = Font.system(size: 48, weight: .bold, design: .rounded)
        static let price = Font.system(size: 24, weight: .semibold, design: .rounded)
        static let button = Font.system(size: 17, weight: .semibold, design: .rounded)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    // MARK: - Radius
    struct Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xlarge: CGFloat = 24
        static let full: CGFloat = 9999
    }
    
    // MARK: - Shadows
    struct Shadow {
        static let small = ShadowStyle(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        static let medium = ShadowStyle(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        static let large = ShadowStyle(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        static let card = ShadowStyle(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
    
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - View Modifiers
struct ModernCardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(ModernTheme.Colors.cardBackground)
            .cornerRadius(ModernTheme.Radius.large)
            .shadow(
                color: ModernTheme.Shadow.card.color,
                radius: ModernTheme.Shadow.card.radius,
                x: ModernTheme.Shadow.card.x,
                y: ModernTheme.Shadow.card.y
            )
    }
}

struct GlassCardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: ModernTheme.Radius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: ModernTheme.Radius.large)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ModernTheme.Typography.button)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, ModernTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ModernTheme.Radius.medium)
                    .fill(ModernTheme.Colors.primaryGradient)
                    .opacity(isEnabled ? 1 : 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ModernTheme.Typography.button)
            .foregroundColor(ModernTheme.Colors.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, ModernTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ModernTheme.Radius.medium)
                    .stroke(ModernTheme.Colors.primary, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Extensions
extension View {
    func modernCard() -> some View {
        modifier(ModernCardStyle())
    }
    
    func glassCard() -> some View {
        modifier(GlassCardStyle())
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let rgbValue = UInt32(hex, radix: 16) ?? 0
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255
        let b = Double(rgbValue & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
    
    init(light: Color, dark: Color) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}