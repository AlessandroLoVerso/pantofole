import Foundation
import Testing
@testable import SvegliaCore

/// SplitMix64: a tiny deterministic generator, so every run sees the same problems.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Evaluates "a op b op c …" with × before + and −, independently of the generator.
private func evaluate(_ text: String) -> Int {
    let tokens = text.split(separator: " ").map(String.init)
    var sums: [Int] = []
    var sign = 1
    var product = Int(tokens[0])!
    var index = 1
    while index < tokens.count {
        let op = tokens[index], value = Int(tokens[index + 1])!
        switch op {
        case "×": product *= value
        case "+", "−":
            sums.append(sign * product)
            sign = op == "+" ? 1 : -1
            product = value
        default: Issue.record("Unexpected operator \(op)")
        }
        index += 2
    }
    sums.append(sign * product)
    return sums.reduce(0, +)
}

@Suite struct MathProblemTests {
    @Test(arguments: 1...MathProblem.maxLevel)
    func answersAreCorrectAndFitTheKeypad(level: Int) {
        var generator = SeededGenerator(state: UInt64(level))
        for _ in 0..<500 {
            let problem = MathProblem.random(level: level, using: &generator)
            #expect(problem.level == level)
            #expect(evaluate(problem.text) == problem.answer, "\(problem.text)")
            #expect((0...MathProblem.maxAnswer).contains(problem.answer), "\(problem.text)")
            #expect(problem.isCorrect(problem.answer))
            #expect(!problem.isCorrect(problem.answer + 1))
        }
    }

    @Test func noIntermediateResultIsNegative() {
        var generator = SeededGenerator(state: 99)
        for level in 1...MathProblem.maxLevel {
            for _ in 0..<300 {
                let problem = MathProblem.random(level: level, using: &generator)
                #expect(!problem.text.contains("-"), "uses the real minus sign")
                #expect(problem.answer >= 0)
            }
        }
    }

    @Test func easyLevelsOnlyAddAndSubtract() {
        var generator = SeededGenerator(state: 7)
        for level in 1...3 {
            for _ in 0..<200 {
                let problem = MathProblem.random(level: level, using: &generator)
                #expect(!problem.hasMultiplication)
                #expect(problem.terms == 2)
            }
        }
    }

    @Test func hardestLevelsUsePrecedence() {
        var generator = SeededGenerator(state: 11)
        for level in 6...7 {
            for _ in 0..<200 {
                let problem = MathProblem.random(level: level, using: &generator)
                #expect(problem.hasMultiplication)
                #expect(problem.terms >= 3)
                #expect(problem.text.contains("+") || problem.text.contains("−"))
            }
        }
    }

    @Test func levelIsClamped() {
        var generator = SeededGenerator(state: 1)
        #expect(MathProblem.random(level: 0, using: &generator).level == 1)
        #expect(MathProblem.random(level: 42, using: &generator).level == MathProblem.maxLevel)
    }
}

@Suite struct MathMissionTests {
    @Test(arguments: MissionDifficulty.allCases)
    func eachProblemIsOneLevelHarder(difficulty: MissionDifficulty) {
        var mission = MathMission(difficulty: difficulty, generator: SeededGenerator(state: 3))
        var levels: [Int] = []
        while let problem = mission.current {
            levels.append(problem.level)
            let right = mission.submit(problem.answer)
            #expect(right)
        }
        #expect(levels.count == MathMission<SeededGenerator>.defaultLength)
        #expect(zip(levels, levels.dropFirst()).allSatisfy { $1 == $0 + 1 })
        #expect(mission.isComplete)
        #expect(mission.solved == levels.count)
    }

    @Test func harderDifficultiesStartHigher() {
        let first = MissionDifficulty.allCases.map {
            MathMission(difficulty: $0, generator: SeededGenerator(state: 5)).current!.level
        }
        #expect(first == first.sorted())
        #expect(Set(first).count == first.count)
        #expect(first.first == 1)
    }

    @Test func wrongAnswerReplacesTheProblemWithoutLosingProgress() {
        var mission = MathMission(difficulty: .medium, generator: SeededGenerator(state: 8))
        let first = mission.current!
        mission.submit(first.answer)
        let second = mission.current!

        let wrong = mission.submit(second.answer + 1)
        #expect(!wrong)
        let replacement = mission.current!
        #expect(mission.solved == 1)
        #expect(mission.mistakes == 1)
        #expect(replacement.level == second.level)
        #expect(replacement.text != second.text)

        let right = mission.submit(replacement.answer)
        #expect(right)
        #expect(mission.solved == 2)
        #expect(mission.current?.level == second.level + 1)
    }

    @Test func completeMissionIgnoresFurtherAnswers() {
        var mission = MathMission(difficulty: .easy, length: 1, generator: SeededGenerator(state: 2))
        mission.submit(mission.current!.answer)
        #expect(mission.isComplete)
        let accepted = mission.submit(0)
        #expect(!accepted)
        #expect(mission.solved == 1)
    }

    @Test func sameSeedSameProblems() {
        func texts(seed: UInt64) -> [String] {
            var mission = MathMission(difficulty: .hard, generator: SeededGenerator(state: seed))
            var result: [String] = []
            while let problem = mission.current {
                result.append(problem.text)
                mission.submit(problem.answer)
            }
            return result
        }
        #expect(texts(seed: 42) == texts(seed: 42))
        #expect(texts(seed: 42) != texts(seed: 43))
    }
}
