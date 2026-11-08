import Foundation

enum YummySlug {
    static func make(_ query: String) -> String {
        let letters = Array("абвгдежзийклмнопрстуфхцчшщъыьэюя")
        let values = ["a","b","v","g","d","e","zh","z","i","i","k","l","m","n","o","p","r","s","t","u","f","h","ts","ch","sh","sch","","y","","e","yu","ya"]
        let table = Dictionary(uniqueKeysWithValues: zip(letters, values))
        let text = query.lowercased().replacingOccurrences(of: "ё", with: "е").map { table[$0] ?? String($0) }.joined()
        return text.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
