import XCTest
@testable import ViraTranslation

final class ViraTranslationTests: XCTestCase {
    
    var translator: ViraTranslation!
    
    override func setUp() {
        super.setUp()
        translator = ViraTranslation()
    }
    
    override func tearDown() {
        translator = nil
        super.tearDown()
    }
    
    func testLanguageEnum() {
        // Test that all languages have proper display names
        for language in ViraTranslation.Language.allCases {
            XCTAssertFalse(language.displayName.isEmpty, "Language \(language) should have a display name")
        }
        
        // Test specific language codes and display names
        XCTAssertEqual(ViraTranslation.Language.english.rawValue, "en")
        XCTAssertEqual(ViraTranslation.Language.spanish.displayName, "Spanish")
    }
    
    func testTranslate() {
        // Create an expectation for asynchronous testing
        let expectation = XCTestExpectation(description: "Translate text")
        
        // Test a simple translation from English to Spanish
        translator.translate(
            text: "Hello world",
            from: .english,
            to: .spanish,
            completion: { result in
                switch result {
                case .success(let translatedText):
                    // In our mock implementation, we expect the translated text to be prefixed with the target language
                    XCTAssertEqual(translatedText, "[Spanish] Hello world")
                    expectation.fulfill()
                case .failure(let error):
                    XCTFail("Translation should not fail: \(error)")
                }
            }
        )
        
        // Wait for the expectation to be fulfilled
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testDetectLanguage() {
        // Create an expectation for asynchronous testing
        let expectation = XCTestExpectation(description: "Detect language")
        
        // Test language detection
        translator.detectLanguage(for: "Hello world") { result in
            switch result {
            case .success(let language):
                // In our mock implementation, we always expect English
                XCTAssertEqual(language, .english)
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Language detection should not fail: \(error)")
            }
        }
        
        // Wait for the expectation to be fulfilled
        wait(for: [expectation], timeout: 1.0)
    }
}

