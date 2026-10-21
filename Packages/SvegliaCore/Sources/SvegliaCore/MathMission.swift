import Foundation

/// How hard the wake-up mission is. Stored as its raw value on each alarm.
public enum MissionDifficulty: Int, CaseIterable, Sendable, Codable {
    case easy = 0
    case medium = 1
    case hard = 2

    /// The level of the first problem; each next problem is one level up.
    var firstLevel: Int {
        switch self {
        case .easy: 1
        case .medium: 3
        case .hard: 5
        }
    }
}

/// One arithmetic problem, e.g. "12 × 7 − 4 × 9".
public struct MathProblem: Equatable, Sendable {
    /// Ready to show: operators are `+`, `−` (minus sign) and `×`.
    public let text: String
    /// Always a whole number between 0 and `MathProblem.maxAnswer`.
    public let answer: Int
    /// 1 (easiest) … `MathProblem.maxLevel`.
    public let level: Int
    /// How many numbers appear in the expression.
    public let terms: Int
    public let hasMultiplication: Bool

    public static let maxLevel = 7
    /// Fits a 4-digit numeric keypad entry.
    public static let maxAnswer = 9_999

    public func isCorrect(_ answer: Int) -> Bool { answer == self.answer }

    /// A random problem of `level` (clamped to 1…`maxLevel`).
    ///
    /// 1. two-digit + one-digit (34 + 8)
    /// 2. two-digit ± two-digit (57 − 23)
    /// 3. bigger two-digit sums and differences with carries (78 + 65, 91 − 47)
    /// 4. times tables (7 × 8)
    /// 5. two-digit × one-digit (14 × 6)
    /// 6. three terms with precedence (45 + 6 × 7, 9 × 8 − 27)
    /// 7. two products (12 × 7 − 4 × 9)
    public static func random(level: Int, using generator: inout some RandomNumberGenerator) -> MathProblem {
        let level = min(max(level, 1), maxLevel)
        func n(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &generator) }
        func coin() -> Bool { Bool.random(using: &generator) }

        switch level {
        case 1:
            let a = n(10...49), b = n(2...9)
            return MathProblem(text: "\(a) + \(b)", answer: a + b, level: level, terms: 2, hasMultiplication: false)
        case 2:
            let a = n(10...89), b = n(10...89)
            if coin() {
                return MathProblem(text: "\(a) + \(b)", answer: a + b, level: level, terms: 2, hasMultiplication: false)
            }
            let (big, small) = (max(a, b), min(a, b))
            return MathProblem(text: "\(big) − \(small)", answer: big - small, level: level, terms: 2, hasMultiplication: false)
        case 3:
            if coin() {
                // Units add up to 10 or more: a carry is needed.
                let unitsA = n(1...9), unitsB = n((10 - unitsA)...9)
                let a = n(2...9) * 10 + unitsA, b = n(2...9) * 10 + unitsB
                return MathProblem(text: "\(a) + \(b)", answer: a + b, level: level, terms: 2, hasMultiplication: false)
            }
            // The minuend's units are smaller: a borrow is needed.
            let tensA = n(5...9), unitsA = n(0...4)
            let tensB = n(1...(tensA - 1)), unitsB = n((unitsA + 1)...9)
            let a = tensA * 10 + unitsA, b = tensB * 10 + unitsB
            return MathProblem(text: "\(a) − \(b)", answer: a - b, level: level, terms: 2, hasMultiplication: false)
        case 4:
            let a = n(3...9), b = n(3...9)
            return MathProblem(text: "\(a) × \(b)", answer: a * b, level: level, terms: 2, hasMultiplication: true)
        case 5:
            let a = n(11...29), b = n(3...9)
            let text = coin() ? "\(a) × \(b)" : "\(b) × \(a)"
            return MathProblem(text: text, answer: a * b, level: level, terms: 2, hasMultiplication: true)
        case 6:
            let a = n(3...9), b = n(4...12), c = n(10...60)
            switch n(0...2) {
            case 0:
                return MathProblem(text: "\(c) + \(a) × \(b)", answer: c + a * b, level: level, terms: 3, hasMultiplication: true)
            case 1:
                return MathProblem(text: "\(a) × \(b) + \(c)", answer: a * b + c, level: level, terms: 3, hasMultiplication: true)
            default:
                // Keep the result positive: subtract less than the product.
                let d = min(c, a * b - 1)
                return MathProblem(text: "\(a) × \(b) − \(d)", answer: a * b - d, level: level, terms: 3, hasMultiplication: true)
            }
        default:
            let a = n(11...19), b = n(3...9), c = n(3...9), d = n(3...9)
            if coin() {
                return MathProblem(text: "\(a) × \(b) + \(c) × \(d)", answer: a * b + c * d, level: level, terms: 4, hasMultiplication: true)
            }
            // a × b ≥ 33 and c × d ≤ 81: swap the products if needed so the result stays positive.
            let (first, second) = a * b > c * d ? ("\(a) × \(b)", "\(c) × \(d)") : ("\(c) × \(d)", "\(a) × \(b)")
            let answer = abs(a * b - c * d)
            return MathProblem(text: "\(first) − \(second)", answer: answer, level: level, terms: 4, hasMultiplication: true)
        }
    }
}

/// The wake-up mission: a short series of problems, each one level harder than the one before.
/// A wrong answer swaps the current problem for a new one of the same level; solved ones stay solved.
public struct MathMission<Generator: RandomNumberGenerator> {
    public static var defaultLength: Int { 3 }

    public let difficulty: MissionDifficulty
    public let length: Int
    /// How many problems are solved so far.
    public private(set) var solved = 0
    /// The problem to solve now; nil once the mission is complete.
    public private(set) var current: MathProblem?
    /// Wrong answers so far (for feedback only).
    public private(set) var mistakes = 0

    private var generator: Generator

    public init(difficulty: MissionDifficulty, length: Int = Self.defaultLength, generator: Generator) {
        precondition(length > 0)
        self.difficulty = difficulty
        self.length = length
        self.generator = generator
        current = MathProblem.random(level: difficulty.firstLevel, using: &self.generator)
    }

    public var isComplete: Bool { current == nil }

    /// Checks the answer to the current problem. Right: moves on (or completes the mission).
    /// Wrong: a fresh problem of the same level replaces it.
    @discardableResult
    public mutating func submit(_ answer: Int) -> Bool {
        guard let problem = current else { return false }
        if problem.isCorrect(answer) {
            solved += 1
            current = solved < length
                ? MathProblem.random(level: difficulty.firstLevel + solved, using: &generator)
                : nil
            return true
        }
        mistakes += 1
        var replacement = MathProblem.random(level: problem.level, using: &generator)
        // Never show the same problem twice in a row.
        while replacement.text == problem.text {
            replacement = MathProblem.random(level: problem.level, using: &generator)
        }
        current = replacement
        return false
    }
}

extension MathMission where Generator == SystemRandomNumberGenerator {
    public init(difficulty: MissionDifficulty, length: Int = Self.defaultLength) {
        self.init(difficulty: difficulty, length: length, generator: SystemRandomNumberGenerator())
    }
}
