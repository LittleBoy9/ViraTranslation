import Combine
import Foundation

struct RequestPayload: Codable {
    let sourceText: [String]
    let targetLanguage: String
}

public class VitraTranslator: ObservableObject {
    public static let shared = VitraTranslator()  // instance

    private var glossaryId: String?  // fk_glossaryId
    private var apiKey: String?  // api key
    private var packageName: String? = nil  // package name
    private var sourceLanguage: String? = nil
    
    @Published public var availableLanguages: [String] = []

    private var alltargetLanguages: [String] = []

    @Published public var currentLanguage: String = "english"
    @Published private var translations: [String: String] = [:]

    private var onDemandTextList: [String: [String]] = [:]
    private var vitraAssetsPath: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("vitra-assets", isDirectory: true)
    }

    var timer: Timer?

    private var pollingTimer: DispatchSourceTimer?

    private init() {
        loadTranslations(for: currentLanguage)
    }

    // ✅ Call this from app to inject the API key
    public func configure(apiKey: String, glossaryId: String?) {
        print("🔐 API Key set: \(apiKey)")
        self.apiKey = apiKey
        self.glossaryId = glossaryId
        if apiKey.isEmpty || glossaryId == nil {
            print("❌ Missing congifuration parameters")
            return
        }
        // ✅ Restore previously selected language
            restoreLastUsedLanguage()

            // Or fallback to English if nothing found
            if currentLanguage.isEmpty {
                setLanguage("english")
            }
        fetchProject()
    }

    private func fetchProject() {
        // let url = URL(string: "https://cdn.translate.website/631fa1f6-b980-4d35-ab44-223bedd4f8a7/?lang=vitra.n7HDW9w4VjF7pL0Ou9A5rG5Y9EAGgf&sourceOrigin=config")!

        guard
            let apiKey = self.apiKey?.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ),
            let glossaryId = self.glossaryId?.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ),
            let url = URL(
                string:
                    "https://cdn.translate.website/\(glossaryId)/?lang=\(apiKey)&sourceOrigin=config"
            )
        else {
            print("❌ Invalid API key or glossary ID")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ failed:", error)
                return
            }
            guard let data = data else {
                print("❌ No data in API response")
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(
                    with: data,
                    options: []
                ) as? [String: Any] {
                    print("✅ API Response: \(json)")
                    if let domain = json["domain"] as? String,
                        let sourceLang: String = json["sourceLanguage"]
                            as? String,
                        let allTargetLangs: [String] = json["targetLanguages"]
                            as? [String]
                    {
                        self.packageName = domain
                        self.sourceLanguage = sourceLang
                        self.alltargetLanguages = allTargetLangs

                        print("📦 Package name: \(self.packageName!)")
                        print("📈 Source language: \(self.sourceLanguage!)")
                        print(" target languages: \(self.alltargetLanguages)")
                    }
                    // Save to file
                    try self.saveDataToAppFile(data: data)
                }

            } catch {
                print("❌ Failed to parse JSON: \(error)")
                return
            }

        }.resume()

    }

    private func saveDataToAppFile(data: Data) throws {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = appSupport.appendingPathComponent(
            "VitraTranslation",
            isDirectory: true
        )
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
        }
        let fileURL = folder.appendingPathComponent(
            "project_data.json"
        )
        try data.write(to: fileURL, options: [.atomicWrite])
        print("📁 Saved API response to: \(fileURL.path)")
        // ✅ Decode JSON and extract dropdownData
        do {
            let json =
                try JSONSerialization.jsonObject(with: data, options: [])
                as? [String: Any]

            if let dropdownData = json?["dropdownData"]
                as? [String: [String: Any]]
            {
                for (langCode, info) in dropdownData {
                    let label = info["label"] as? String ?? "-"
                    let flag = info["flag"] as? String ?? "unknown.png"
                    print("🌐 \(langCode): \(label), flag: \(flag)")
                }

                // ✅ Call your file creation function
                let languageCodes = Array(dropdownData.keys)
                createEmptyLanguageFiles(from: languageCodes)
            } else {
                print("❌ Failed to extract dropdownData")
            }
        } catch {
            print("❌ Error parsing saved JSON: \(error)")
        }
        print("callling start pollibg")
        self.startPolling()
    }
    
    
    
    /// Merges new translations with existing in-memory + file
    func mergeWithPreviousTranslations(
        newTranslations: [String: String],
        lang: String
    ) {
        DispatchQueue.main.async {
            // 1. Merge into in-memory state
            self.translations.merge(newTranslations) { _, new in new }

            // 2. Persist merged translations to disk
            self.saveMergedTranslations(for: lang)
        }
        print("✅ Merged \(newTranslations.count) new translations for [\(lang)]")
    }

    /// Calls on-demand translation API and merges results
    func callOnDemandTranslation(
        filteredTextList: Set<String>,
        lang: String,
        apiKey: String,
        origin: String
    ) async {
        let reqData = RequestPayload(
            sourceText: Array(filteredTextList),
            targetLanguage: lang
        )

        print("📤 Request Data for \(lang): \(reqData)")

        guard let url = URL(string: "https://api.translate.website/v1/project/translate-app-on-demand-bulk") else {
            print("❌ Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(origin, forHTTPHeaderField: "x-package-key")

        do {
            request.httpBody = try JSONEncoder().encode(reqData)

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Response is not valid JSON")
                return
            }

            if let newTranslations = jsonObject["translation"] as? [String: String] {
                mergeWithPreviousTranslations(newTranslations: newTranslations, lang: lang)
            } else {
                print("⚠️ No 'translation' dictionary found in API response")
            }

        } catch {
            print("❌ Network or decoding error: \(error)")
        }
    }

   
    private func saveMergedTranslations(for language: String) {
        guard let vitraAssetsFolder = vitraAssetsPath else {
            print("❌ Could not resolve vitra-assets path")
            return
        }
        let fileURL = vitraAssetsFolder.appendingPathComponent("\(language.lowercased()).json")
        do {
            let data = try JSONEncoder().encode(self.translations)
            try data.write(to: fileURL, options: [.atomicWrite])
            print("💾 Merged translations saved to \(fileURL.lastPathComponent)")
        } catch {
            print("❌ Failed to save merged translation file: \(error)")
        }
    }
    private func fetchTranslations() async {
        if onDemandTextList.isEmpty { return }
        let temp: [String: [String]] = onDemandTextList
        onDemandTextList = [:]
        for (key, value) in temp {
            await self.callOnDemandTranslation(
                filteredTextList: Set(value),
                lang: key,
                apiKey: self.apiKey ?? "",
                origin: self.packageName ?? ""
            )
        }

    }
    public func loadAvailableLanguagesFromAssets() {
        let fileManager = FileManager.default
        do {
            let folder = try self.getVitraAssetsFolder(createIfNeeded: false)
            let contents = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            let jsonFiles = contents
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent.lowercased() }
            DispatchQueue.main.async {
                self.availableLanguages = jsonFiles.sorted()
            }
        } catch {
            print("❌ Failed to list vitra-assets files: \(error)")
            DispatchQueue.main.async {
                self.availableLanguages = []
            }
        }
    }
    private func createEmptyLanguageFiles(from languageCodes: [String]) {
        let fileManager = FileManager.default
        var createdOrExisting: [String] = []
        do {
            var vitraAssetsFolder = try self.getVitraAssetsFolder()
            if !fileManager.fileExists(atPath: vitraAssetsFolder.path) {
                try fileManager.createDirectory(at: vitraAssetsFolder, withIntermediateDirectories: true)
                print("📁 Created folder: \(vitraAssetsFolder.path)")
            }
            // Step 1: Create missing files, and track all valid ones
            for langCode in languageCodes {
                let fileURL = vitraAssetsFolder.appendingPathComponent("\(langCode).json")
                if !fileManager.fileExists(atPath: fileURL.path) {
                    fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
                    print("✅ Created empty file: \(fileURL.lastPathComponent)")
                } else {
                    print("ℹ️ File already exists: \(fileURL.lastPathComponent)")
                }
                createdOrExisting.append(langCode.lowercased())
            }
            // Step 2: Remove any language file not in the provided list
            let contents = try fileManager.contentsOfDirectory(at: vitraAssetsFolder, includingPropertiesForKeys: nil)
            let allJSONFiles = contents.filter { $0.pathExtension == "json" }
            for file in allJSONFiles {
                let lang = file.deletingPathExtension().lastPathComponent.lowercased()
                if !createdOrExisting.contains(lang) {
                    try fileManager.removeItem(at: file)
                    print("🗑️ Deleted extra file: \(file.lastPathComponent)")
                }
            }
            // Step 3: Update published list
            DispatchQueue.main.async {
                self.availableLanguages = createdOrExisting.sorted()
            }
        } catch {
            print("❌ Failed to create, update, or clean vitra-assets: \(error)")
        }
    }
    public func setLanguage(_ language: String) {
        print("🌐 Changing language to: \(language)")
        currentLanguage = language
        loadTranslations(for: language)
        saveCurrentLanguage(language)
        Task {
            await fetchFromCDN(lang: currentLanguage)
        }
    }
    private func saveCurrentLanguage(_ language: String) {
        let fileManager = FileManager.default
        do {
            let appSupportDir = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let dataFolder = appSupportDir.appendingPathComponent("VitraTranslation", isDirectory: true)
            

            if !fileManager.fileExists(atPath: dataFolder.path) {
                try fileManager.createDirectory(at: dataFolder, withIntermediateDirectories: true)
            }
            let fileURL = dataFolder.appendingPathComponent("data.json")
            var existingData: [String: Any] = [:]
            if fileManager.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    existingData = json
                }
            }
            // ✅ Update or insert currentLanguage
            existingData["currentLanguage"] = language.lowercased()
            let updatedData = try JSONSerialization.data(withJSONObject: existingData, options: [.prettyPrinted])
            try updatedData.write(to: fileURL, options: [.atomicWrite])
            print("💾 Saved current language and preserved existing keys: \(fileURL.path)")
        } catch {
            print("❌ Failed to save current language: \(error)")
        }
    }
    public func restoreLastUsedLanguage() {
        let fileManager = FileManager.default
        do {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let fileURL = appSupport.appendingPathComponent("VitraTranslation/data.json")
            guard fileManager.fileExists(atPath: fileURL.path) else {
                print("ℹ️ No saved language file found")
                return
            }
            let data = try Data(contentsOf: fileURL)
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String],
               let lang = json["currentLanguage"] {
                print("🔁 Restoring last used language: \(lang)")
                setLanguage(lang)
            }
        } catch {
            print("❌ Failed to restore language: \(error)")
        }
    }
    public func localize(key: String) -> String {
        let value = translations[key]
        if value == nil, self.currentLanguage != self.sourceLanguage {
            if self.onDemandTextList[self.currentLanguage] != nil {
                self.onDemandTextList[self.currentLanguage]?.append(key)
            } else {
                self.onDemandTextList[self.currentLanguage] = [key]
            }
        }
       // print("🔤 Translating : \"\(key)\" → \"\(value ?? key)\"")
        return value ?? key
    }
    func startPolling() {
        print("📡 Starting polling...")

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 2, repeating: 2)

        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task {
                await self.fetchTranslations()
            }
        }

        timer.resume()
        pollingTimer = timer
    }

    private func loadTranslations(for language: String) {
        let fileName = language.lowercased()
        //        print("📥 Attempting to load translations for: \(fileName)")
        let fileManager = FileManager.default
        do {
            // 1. Get app's Application Support directory
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            // 2. Construct path to vitra-assets/<language>.json
            let fileURL =
                appSupport
                .appendingPathComponent("vitra-assets", isDirectory: true)
                .appendingPathComponent("\(fileName).json")
            print("FILE URL IS: \(fileURL.path)")
            guard fileManager.fileExists(atPath: fileURL.path) else {
                print("❌ File not found at: \(fileURL.path)")
                translations = [:]
                return
            }
            // 3. Load and decode
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(
                [String: String].self,
                from: data
            )
            print(
                "✅ Loaded \(decoded.count) translation entries from: \(fileURL.lastPathComponent)"
            )
            self.translations = decoded
        } catch {
            print("❌ Failed to load/parse \(fileName).json: \(error)")
            translations = [:]
        }
    }
    
    
   
    private func fetchFromCDN(lang: String) async {
        guard
            let glossaryId = self.glossaryId?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let encodedLang = lang.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else {
            print("❌ Invalid glossaryId or language")
            return
        }

        let sourceOrigin = packageName ?? "com.ios"
        let urlString = "https://cdn.translate.website/\(glossaryId)/?lang=\(encodedLang)&sourceOrigin=\(sourceOrigin)"

        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            // Parse JSON response
            guard let data = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                print("⚠️ Response is not valid JSON")
                return
            }

            print("✅ Fetched CDN data for \(lang):", data)

            // Extract translations (assuming it's under "translation" key)
            if let newTranslations = data as? [String: String] {
                DispatchQueue.main.async {
                    self.translations.merge(newTranslations) { _, new in new }
                    self.saveMergedTranslations(for: lang)
                    print("✅ CDN translations applied to UI and saved for: \(lang)")
                }
            } else {
                print("⚠️ No 'translation' key found in CDN response")
            }

        } catch {
            print("❌ Error fetching CDN data: \(error)")
        }
    }

    private func getVitraAssetsFolder(createIfNeeded: Bool = true) throws -> URL {
        let appSupportDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createIfNeeded
        )
        let vitraAssetsFolder = appSupportDir.appendingPathComponent("vitra-assets", isDirectory: true)
        if createIfNeeded, !FileManager.default.fileExists(atPath: vitraAssetsFolder.path) {
            try FileManager.default.createDirectory(at: vitraAssetsFolder, withIntermediateDirectories: true)
        }
        return vitraAssetsFolder
    }
    
    public var isRTLLanguage: Bool {
        return currentLanguage.lowercased() == "arabic"
    }
}
