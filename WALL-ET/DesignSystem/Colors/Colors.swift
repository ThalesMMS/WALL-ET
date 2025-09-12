import SwiftUI

extension Color {
    struct Wallet {
        // Primary Colors
        static let primary = Color("Primary", bundle: nil)
        static let secondary = Color("Secondary", bundle: nil)
        
        // Bitcoin Orange
        static let bitcoinOrange = Color(red: 247/255, green: 147/255, blue: 26/255)
        
        // Background Colors
        static let background = Color(UIColor.systemBackground)
        static let secondaryBackground = Color(UIColor.secondarySystemBackground)
        static let tertiaryBackground = Color(UIColor.tertiarySystemBackground)
        
        // Text Colors
        static let primaryText = Color(UIColor.label)
        static let secondaryText = Color(UIColor.secondaryLabel)
        static let tertiaryText = Color(UIColor.tertiaryLabel)
        
        // Status Colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
        
        // Transaction Colors
        static let receive = Color.green
        static let send = Color.red
        static let pending = Color.orange
    }
}

struct ThemeColors {
    let primary: Color
    let secondary: Color
    let background: Color
    let surface: Color
    let text: Color
    let textSecondary: Color
    
    static let light = ThemeColors(
        primary: Color.Wallet.bitcoinOrange,
        secondary: Color.blue,
        background: Color.white,
        surface: Color(UIColor.systemGray6),
        text: Color.black,
        textSecondary: Color.gray
    )
    
    static let dark = ThemeColors(
        primary: Color.Wallet.bitcoinOrange,
        secondary: Color.blue,
        background: Color.black,
        surface: Color(UIColor.systemGray5),
        text: Color.white,
        textSecondary: Color.gray
    )
}