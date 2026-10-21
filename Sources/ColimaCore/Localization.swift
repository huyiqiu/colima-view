import Foundation

public enum Localization {
    public static let supportedLanguages = ["en", "zh-Hans"]
    public static var language: String {
        let value = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        return supportedLanguages.contains(value) ? value : "en"
    }

    static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("ColimaDesk_ColimaCore.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
    static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: supportedLanguages.compactMap { language in
        guard let path = resources.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
        return (language, bundle)
    })
}

public struct LocalizedText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<Value>(_ value: Value) {
            key += "{\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
    public func localized(language: String = Localization.language) -> String {
        let translated = Localization.bundles[language]?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
        guard !arguments.isEmpty, let regex = try? NSRegularExpression(pattern: #"\{(\d+)\}"#) else { return translated }
        let result = NSMutableString(string: translated)
        let original = translated as NSString
        for match in regex.matches(in: translated, range: NSRange(location: 0, length: original.length)).reversed() {
            guard let index = Int(original.substring(with: match.range(at: 1))), arguments.indices.contains(index) else { continue }
            result.replaceCharacters(in: match.range, with: arguments[index])
        }
        return result as String
    }
}

public func L(_ text: LocalizedText) -> String { text.localized() }
