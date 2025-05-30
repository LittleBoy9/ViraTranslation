import SwiftUI
import ViraTranslation

public struct VitraRootView<Content: View>: View {
    @ObservedObject var translator: VitraTranslator
    let content: () -> Content

    public init(translator: VitraTranslator = .shared, @ViewBuilder content: @escaping () -> Content) {
        self.translator = translator
        self.content = content
    }

    public var body: some View {
        content()
            .id(translator.currentLanguage) // 👈 force re-init view when lang changes
           .environment(\.layoutDirection, translator.isRTLLanguage ? .rightToLeft : .leftToRight)
//            .environmentObject(translator)
           .environmentObject(VitraTranslator.shared)
    }
}

