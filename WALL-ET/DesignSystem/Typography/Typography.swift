import SwiftUI

struct Typography {
    enum FontSize: CGFloat {
        case largeTitle = 34
        case title1 = 28
        case title2 = 22
        case title3 = 20
        case headline = 18
        case body = 17
        case callout = 16
        case subheadline = 15
        case footnote = 13
        case caption1 = 12
        case caption2 = 11
    }
    
    enum FontWeight {
        case ultraLight
        case thin
        case light
        case regular
        case medium
        case semibold
        case bold
        case heavy
        case black
        
        var swiftUIWeight: Font.Weight {
            switch self {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            }
        }
    }
}

extension View {
    func walletFont(_ size: Typography.FontSize, weight: Typography.FontWeight = .regular) -> some View {
        self.font(.system(size: size.rawValue, weight: weight.swiftUIWeight))
    }
}

extension Text {
    func largeTitle() -> Text {
        self.font(.largeTitle)
    }
    
    func title() -> Text {
        self.font(.title)
    }
    
    func headline() -> Text {
        self.font(.headline).bold()
    }
    
    func body() -> Text {
        self.font(.body)
    }
    
    func caption() -> Text {
        self.font(.caption)
    }
    
    func bitcoinAmount() -> Text {
        self.font(.system(size: 24, weight: .semibold, design: .monospaced))
    }
    
    func fiatAmount() -> Text {
        self.font(.system(size: 18, weight: .medium))
    }
}