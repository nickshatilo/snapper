import AppKit

struct BackgroundTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var type: BackgroundType
    var padding: CGFloat = 60
    var cornerRadius: CGFloat = 12
    var shadowRadius: CGFloat = 20
    var aspectRatio: AspectRatio = .auto

    enum BackgroundType: Codable {
        case gradient(startColor: CodableColor, endColor: CodableColor, angle: CGFloat)
        case solid(color: CodableColor)
        case image(imagePath: String)
    }

    enum AspectRatio: String, Codable, CaseIterable {
        case auto = "Auto"
        case sixteenNine = "16:9"
        case fourThree = "4:3"
        case oneOne = "1:1"
        case instagram = "4:5"

        var ratio: CGFloat? {
            switch self {
            case .auto: return nil
            case .sixteenNine: return 16.0 / 9.0
            case .fourThree: return 4.0 / 3.0
            case .oneOne: return 1.0
            case .instagram: return 4.0 / 5.0
            }
        }
    }

    static let builtIn: [BackgroundTemplate] = [
        BackgroundTemplate(name: "Ocean", type: .gradient(startColor: CodableColor(r: 0.1, g: 0.4, b: 0.8), endColor: CodableColor(r: 0.05, g: 0.2, b: 0.6), angle: 135)),
        BackgroundTemplate(name: "Sunset", type: .gradient(startColor: CodableColor(r: 1.0, g: 0.4, b: 0.3), endColor: CodableColor(r: 0.8, g: 0.2, b: 0.5), angle: 135)),
        BackgroundTemplate(name: "Forest", type: .gradient(startColor: CodableColor(r: 0.2, g: 0.8, b: 0.4), endColor: CodableColor(r: 0.1, g: 0.5, b: 0.3), angle: 135)),
        BackgroundTemplate(name: "Night", type: .gradient(startColor: CodableColor(r: 0.15, g: 0.15, b: 0.3), endColor: CodableColor(r: 0.05, g: 0.05, b: 0.15), angle: 135)),
        BackgroundTemplate(name: "White", type: .solid(color: CodableColor(r: 1, g: 1, b: 1))),
        BackgroundTemplate(name: "Dark", type: .solid(color: CodableColor(r: 0.12, g: 0.12, b: 0.12))),
    ]
}

struct CodableColor: Codable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    var nsColor: NSColor {
        NSColor(red: r, green: g, blue: b, alpha: a)
    }

    var cgColor: CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }
}
