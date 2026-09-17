public import Foundation

extension UserDefaults {
    public func decodedArray<Element: Decodable>(of type: Element.Type, forKey key: String) -> [Element] {
        guard let items = array(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        return items.compactMap { item in
            guard let text = item as? String else { return nil }
            return try? decoder.decode(Element.self, from: Data(text.utf8))
        }
    }

    public func setEncodedArray<Element: Encodable>(_ elements: [Element], forKey key: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let items = elements.compactMap { element in
            (try? encoder.encode(element)).map { String(decoding: $0, as: UTF8.self) }
        }
        set(items, forKey: key)
    }

    public func decodedValue<Value: Decodable>(of type: Value.Type, forKey key: String) -> Value? {
        guard let text = string(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: Data(text.utf8))
    }

    public func setEncodedValue<Value: Encodable>(_ value: Value?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(value) else { return }
        set(String(decoding: data, as: UTF8.self), forKey: key)
    }

    public func stringDictionary(forKey key: String) -> [String: String] {
        dictionary(forKey: key) as? [String: String] ?? [:]
    }

    public func integerSet(forKey key: String) -> Set<Int> {
        Set(array(forKey: key) as? [Int] ?? [])
    }
}
