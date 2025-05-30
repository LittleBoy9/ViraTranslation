import SwiftUI

public enum VitraLanguageUIMode {
    case picker
    case menu
}

public struct VitraLanguageSelector: View {
    @ObservedObject var translator: VitraTranslator

    @State private var selectedLanguage: String
    @State private var uiMode: VitraLanguageUIMode

    public init(translator: VitraTranslator, mode: VitraLanguageUIMode = .menu) {
        self.translator = translator
        self.uiMode = mode
        self._selectedLanguage = State(initialValue: translator.currentLanguage)
    }

    public var body: some View {
        Group {
            if uiMode == .picker {
                VStack(spacing: 4) {
                    if translator.availableLanguages.isEmpty {
                        ProgressView("Loading languages...")
                    } else {
                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(translator.availableLanguages, id: \.self) { lang in
                                Text(lang.capitalized)
                            }
                        }
                        .onChange(of: selectedLanguage) { newLang in
                            print("🌐 Picker changed to: \(newLang)")
                            translator.setLanguage(newLang)
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
            } else {
                Menu {
                    ForEach(translator.availableLanguages, id: \.self) { lang in
                        Button(action: {
                            selectedLanguage = lang
                            translator.setLanguage(lang)
                            print("🌐 Language switched to: \(lang)")
                        }) {
                            Text(lang.capitalized)
                        }
                    }

                    Divider()
                    Link("Developed by Sounak", destination: URL(string: "https://sounakdas.in")!)
                        .foregroundColor(.gray)
                } label: {
                    Label("Language: \(selectedLanguage.capitalized)", systemImage: "globe")
                        .font(.subheadline)
                }
            }
        }
        .onAppear {
            translator.loadAvailableLanguagesFromAssets()
        }
        .onReceive(translator.$currentLanguage) { newLang in
            if newLang != selectedLanguage {
                selectedLanguage = newLang
            }
        }
    }
}
