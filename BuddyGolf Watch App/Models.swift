import Foundation

struct Course: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var holes: [Hole]

    init(id: UUID = UUID(), name: String, holes: [Hole]) {
        self.id = id
        self.name = name
        self.holes = holes.sorted { $0.holeNumber < $1.holeNumber }
    }
}

struct Hole: Codable, Identifiable, Equatable, Hashable {
    var id: Int { holeNumber }
    let holeNumber: Int
    let greenLatitude: Double
    let greenLongitude: Double
    let par: Int
    let strokeIndex: Int?
    let teeDistancesMeters: [String: Int]?

    init(
        holeNumber: Int,
        greenLatitude: Double,
        greenLongitude: Double,
        par: Int,
        strokeIndex: Int? = nil,
        teeDistancesMeters: [String: Int]? = nil
    ) {
        self.holeNumber = holeNumber
        self.greenLatitude = greenLatitude
        self.greenLongitude = greenLongitude
        self.par = par
        self.strokeIndex = strokeIndex
        self.teeDistancesMeters = teeDistancesMeters
    }
}

struct ShotPoint: Codable, Equatable, Hashable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let holeNumber: Int
    let strokeNumber: Int
}

struct HoleState: Codable, Identifiable, Equatable, Hashable {
    var id: Int { holeNumber }
    let holeNumber: Int
    var playerScores: [Int]
    var myShotPoints: [ShotPoint]

    init(holeNumber: Int, playerScores: [Int] = Array(repeating: 0, count: Round.defaultPlayerCount), myShotPoints: [ShotPoint] = []) {
        self.holeNumber = holeNumber
        self.playerScores = HoleState.normalizedScores(playerScores)
        self.myShotPoints = myShotPoints
    }

    var myScore: Int {
        get { playerScores[safe: 0] ?? 0 }
        set { playerScores[0] = newValue }
    }

    static func normalizedScores(_ scores: [Int]) -> [Int] {
        let clamped = scores.map { max(0, $0) }
        if clamped.count >= Round.maxPlayerCount {
            return Array(clamped.prefix(Round.maxPlayerCount))
        }
        return clamped + Array(repeating: 0, count: Round.maxPlayerCount - clamped.count)
    }

    enum CodingKeys: String, CodingKey {
        case holeNumber
        case playerScores
        case myShotPoints
        case myScore
        case buddyScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holeNumber = try container.decode(Int.self, forKey: .holeNumber)
        myShotPoints = try container.decodeIfPresent([ShotPoint].self, forKey: .myShotPoints) ?? []

        if let playerScores = try container.decodeIfPresent([Int].self, forKey: .playerScores) {
            self.playerScores = HoleState.normalizedScores(playerScores)
        } else {
            let myScore = try container.decodeIfPresent(Int.self, forKey: .myScore) ?? 0
            let buddyScore = try container.decodeIfPresent(Int.self, forKey: .buddyScore) ?? 0
            self.playerScores = HoleState.normalizedScores([myScore, buddyScore])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(holeNumber, forKey: .holeNumber)
        try container.encode(playerScores, forKey: .playerScores)
        try container.encode(myShotPoints, forKey: .myShotPoints)
    }
}

enum TeamSetup: String, Codable, CaseIterable, Identifiable {
    case individual
    case teams

    var id: String { rawValue }

    var title: String {
        switch self {
        case .individual:
            return "Individual"
        case .teams:
            return "Teams"
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable, Identifiable {
    case meters
    case yards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meters:
            return "Meters"
        case .yards:
            return "Yards"
        }
    }

    var symbol: String {
        switch self {
        case .meters:
            return "m"
        case .yards:
            return "yd"
        }
    }

    func displayDistance(fromMeters meters: Int) -> Int {
        switch self {
        case .meters:
            return meters
        case .yards:
            return Int((Double(meters) * 1.0936133).rounded())
        }
    }
}

enum ScoringMode: String, Codable, CaseIterable, Identifiable {
    case strokePlay
    case matchPlay
    case pointsMatch
    case stableford

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strokePlay:
            return "Stroke Play"
        case .matchPlay:
            return "Match Play"
        case .pointsMatch:
            return "Points Match"
        case .stableford:
            return "Stableford"
        }
    }

    var shortTitle: String {
        switch self {
        case .strokePlay:
            return "Stroke"
        case .matchPlay:
            return "Match"
        case .pointsMatch:
            return "Points"
        case .stableford:
            return "Stable"
        }
    }
}

enum ScoreBasis: String, Codable, CaseIterable, Identifiable {
    case gross
    case net

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gross:
            return "Gross"
        case .net:
            return "Net"
        }
    }

    var shortTitle: String {
        title
    }
}

struct PlayerConfiguration: Codable, Equatable, Hashable {
    var displayName: String?
    var handicap: Int?

    init(displayName: String? = nil, handicap: Int? = nil) {
        self.displayName = PlayerConfiguration.normalizedName(displayName)
        self.handicap = PlayerConfiguration.normalizedHandicap(handicap)
    }

    var effectiveHandicap: Int {
        handicap ?? 0
    }

    func resolvedName(defaultLabel: String) -> String {
        PlayerConfiguration.normalizedName(displayName) ?? defaultLabel
    }

    static func normalizedList(_ players: [PlayerConfiguration]) -> [PlayerConfiguration] {
        let normalized = players.prefix(Round.maxPlayerCount).map {
            PlayerConfiguration(displayName: $0.displayName, handicap: $0.handicap)
        }
        if normalized.count >= Round.maxPlayerCount {
            return Array(normalized)
        }
        return normalized + Array(repeating: PlayerConfiguration(), count: Round.maxPlayerCount - normalized.count)
    }

    static func normalizedName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func normalizedHandicap(_ handicap: Int?) -> Int? {
        guard let handicap else { return nil }
        return min(max(handicap, 0), 54)
    }
}

struct Round: Codable, Equatable, Hashable {
    static let minPlayerCount = 1
    static let defaultPlayerCount = 2
    static let maxPlayerCount = 4

    let id: UUID
    let startedAt: Date
    var courseID: UUID
    var currentHoleNumber: Int
    var playerCount: Int
    var players: [PlayerConfiguration]
    var teamSetup: TeamSetup
    var scoringMode: ScoringMode
    var scoreBasis: ScoreBasis
    var distanceUnit: DistanceUnit
    var holeStates: [HoleState]

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        courseID: UUID,
        currentHoleNumber: Int = 1,
        playerCount: Int = Round.defaultPlayerCount,
        players: [PlayerConfiguration] = Array(repeating: PlayerConfiguration(), count: Round.maxPlayerCount),
        teamSetup: TeamSetup = .individual,
        scoringMode: ScoringMode = .strokePlay,
        scoreBasis: ScoreBasis = .gross,
        distanceUnit: DistanceUnit = .meters,
        holeStates: [HoleState]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.courseID = courseID
        self.currentHoleNumber = currentHoleNumber
        self.playerCount = min(max(playerCount, Round.minPlayerCount), Round.maxPlayerCount)
        self.players = PlayerConfiguration.normalizedList(players)
        self.teamSetup = teamSetup
        self.scoringMode = scoringMode
        self.scoreBasis = scoreBasis
        self.distanceUnit = distanceUnit
        self.holeStates = holeStates
            .map { HoleState(holeNumber: $0.holeNumber, playerScores: $0.playerScores, myShotPoints: $0.myShotPoints) }
            .sorted { $0.holeNumber < $1.holeNumber }
        sanitizeFormat()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case courseID
        case currentHoleNumber
        case playerCount
        case players
        case teamSetup
        case scoringMode
        case scoreBasis
        case distanceUnit
        case holeStates
        case gameMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        courseID = try container.decode(UUID.self, forKey: .courseID)
        currentHoleNumber = try container.decode(Int.self, forKey: .currentHoleNumber)
        playerCount = min(max(try container.decodeIfPresent(Int.self, forKey: .playerCount) ?? Round.defaultPlayerCount, Round.minPlayerCount), Round.maxPlayerCount)
        players = PlayerConfiguration.normalizedList(try container.decodeIfPresent([PlayerConfiguration].self, forKey: .players) ?? [])
        holeStates = try container.decode([HoleState].self, forKey: .holeStates)

        if let teamSetup = try container.decodeIfPresent(TeamSetup.self, forKey: .teamSetup) {
            self.teamSetup = teamSetup
        } else {
            let legacyGameMode = try container.decodeIfPresent(GameMode.self, forKey: .gameMode) ?? .singles
            self.teamSetup = legacyGameMode == .teamFourBall ? .teams : .individual
        }

        if let scoringMode = try container.decodeIfPresent(ScoringMode.self, forKey: .scoringMode) {
            self.scoringMode = scoringMode
        } else {
            let legacyGameMode = try container.decodeIfPresent(GameMode.self, forKey: .gameMode) ?? .singles
            if legacyGameMode == .teamFourBall {
                self.scoringMode = .matchPlay
            } else {
                self.scoringMode = playerCount > 2 ? .pointsMatch : .matchPlay
            }
        }

        scoreBasis = try container.decodeIfPresent(ScoreBasis.self, forKey: .scoreBasis) ?? .gross
        distanceUnit = try container.decodeIfPresent(DistanceUnit.self, forKey: .distanceUnit) ?? .meters
        sanitizeFormat()
    }

    mutating func sanitizeFormat() {
        if playerCount < 4, teamSetup == .teams {
            teamSetup = .individual
        }
        if !scoringMode.isAvailable(for: playerCount, teamSetup: teamSetup) {
            scoringMode = ScoringMode.defaultMode(for: playerCount, teamSetup: teamSetup)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(courseID, forKey: .courseID)
        try container.encode(currentHoleNumber, forKey: .currentHoleNumber)
        try container.encode(playerCount, forKey: .playerCount)
        try container.encode(players, forKey: .players)
        try container.encode(teamSetup, forKey: .teamSetup)
        try container.encode(scoringMode, forKey: .scoringMode)
        try container.encode(scoreBasis, forKey: .scoreBasis)
        try container.encode(distanceUnit, forKey: .distanceUnit)
        try container.encode(holeStates, forKey: .holeStates)
    }
}

enum GameMode: String, Codable, CaseIterable, Identifiable {
    case singles
    case teamFourBall

    var id: String { rawValue }
}

enum LastScoreAction: Equatable {
    case playerScore(holeNumber: Int, playerIndex: Int)
}

struct PersistedRoundState: Codable {
    var selectedCourseID: UUID
    var round: Round
}

extension Round {
    static func fresh(for course: Course) -> Round {
        Round(
            courseID: course.id,
            currentHoleNumber: 1,
            playerCount: defaultPlayerCount,
            players: Array(repeating: PlayerConfiguration(), count: maxPlayerCount),
            teamSetup: .individual,
            scoringMode: .strokePlay,
            scoreBasis: .gross,
            holeStates: course.holes.map { HoleState(holeNumber: $0.holeNumber) }
        )
    }
}

extension ScoringMode {
    func isAvailable(for playerCount: Int, teamSetup: TeamSetup) -> Bool {
        switch self {
        case .strokePlay, .stableford:
            return playerCount >= 1
        case .pointsMatch:
            return teamSetup == .individual && playerCount >= 2
        case .matchPlay:
            return (teamSetup == .individual && playerCount == 2) || (teamSetup == .teams && playerCount == 4)
        }
    }

    static func defaultMode(for playerCount: Int, teamSetup: TeamSetup) -> ScoringMode {
        if ScoringMode.matchPlay.isAvailable(for: playerCount, teamSetup: teamSetup) {
            return .matchPlay
        }
        if ScoringMode.pointsMatch.isAvailable(for: playerCount, teamSetup: teamSetup) {
            return .pointsMatch
        }
        return .strokePlay
    }
}

struct MatchStatus {
    let text: String
    let colorName: String
    let symbol: String
}

struct ScoredHoleValue: Equatable {
    let grossScore: Int
    let effectiveScore: Int
    let netScore: Int
    let handicapStrokes: Int
    let usedFallbackToGross: Bool
}

struct LeaderboardEntry: Equatable {
    let playerIndex: Int
    let value: Double
    let displayText: String
    let colorName: String
}

struct AlternativeScoringResult: Equatable {
    let scoringMode: ScoringMode
    let scoreBasis: ScoreBasis
    let entries: [LeaderboardEntry]
    let netUnavailableHoleNumbers: [Int]
}

enum RoundScoringCalculator {
    static func handicapStrokes(playerHandicap: Int?, holeStrokeIndex: Int?, basis: ScoreBasis) -> Int {
        guard basis == .net,
              let holeStrokeIndex,
              holeStrokeIndex > 0 else {
            return 0
        }

        let handicap = PlayerConfiguration.normalizedHandicap(playerHandicap) ?? 0
        let fullCycles = handicap / 18
        let remainder = handicap % 18
        return fullCycles + (holeStrokeIndex <= remainder ? 1 : 0)
    }

    static func netScore(grossScore: Int, playerHandicap: Int?, holeStrokeIndex: Int?, basis: ScoreBasis) -> Int {
        let strokes = handicapStrokes(playerHandicap: playerHandicap, holeStrokeIndex: holeStrokeIndex, basis: basis)
        return max(0, grossScore - strokes)
    }

    static func scoredHoleValue(
        playerIndex: Int,
        holeState: HoleState,
        hole: Hole,
        round: Round,
        basisOverride: ScoreBasis? = nil
    ) -> ScoredHoleValue? {
        guard holeState.playerScores.indices.contains(playerIndex) else {
            return nil
        }

        let grossScore = holeState.playerScores[playerIndex]
        guard grossScore > 0 else {
            return nil
        }

        let basis = basisOverride ?? round.scoreBasis
        let playerHandicap = round.players[safe: playerIndex]?.handicap

        if basis == .net, hole.strokeIndex == nil {
            return ScoredHoleValue(
                grossScore: grossScore,
                effectiveScore: grossScore,
                netScore: grossScore,
                handicapStrokes: 0,
                usedFallbackToGross: true
            )
        }

        let handicapStrokes = handicapStrokes(
            playerHandicap: playerHandicap,
            holeStrokeIndex: hole.strokeIndex,
            basis: basis
        )
        let netScore = max(0, grossScore - handicapStrokes)

        return ScoredHoleValue(
            grossScore: grossScore,
            effectiveScore: basis == .net ? netScore : grossScore,
            netScore: netScore,
            handicapStrokes: handicapStrokes,
            usedFallbackToGross: false
        )
    }

    static func strokePlayLeaderboard(round: Round, course: Course, basis: ScoreBasis? = nil) -> [LeaderboardEntry] {
        leaderboard(
            round: round,
            course: course,
            basis: basis ?? round.scoreBasis,
            ascending: true,
            totalizer: totalStrokeScores
        )
    }

    static func stablefordLeaderboard(round: Round, course: Course, basis: ScoreBasis? = nil) -> [LeaderboardEntry] {
        leaderboard(
            round: round,
            course: course,
            basis: basis ?? round.scoreBasis,
            ascending: false,
            totalizer: totalStablefordPoints
        )
    }

    static func pointsMatchLeaderboard(round: Round, course: Course, basis: ScoreBasis? = nil) -> [LeaderboardEntry] {
        let basis = basis ?? round.scoreBasis
        let totals = pointsMatchTotals(round: round, course: course, basis: basis)
        let leader = totals.prefix(round.playerCount).max() ?? 0

        return Array(0..<round.playerCount).map { playerIndex in
            let value = totals[playerIndex]
            return LeaderboardEntry(
                playerIndex: playerIndex,
                value: value,
                displayText: formattedPoints(value),
                colorName: value >= leader - 0.0001 ? "up" : "score"
            )
        }
    }

    static func alternativeResults(round: Round, course: Course) -> [AlternativeScoringResult] {
        var results: [AlternativeScoringResult] = []
        let bases: [ScoreBasis] = [.gross, .net]

        for mode in ScoringMode.allCases {
            guard mode.isAvailable(for: round.playerCount, teamSetup: round.teamSetup) else {
                continue
            }

            for basis in bases {
                let entries: [LeaderboardEntry]
                switch mode {
                case .strokePlay:
                    entries = strokePlayLeaderboard(round: round, course: course, basis: basis)
                case .matchPlay:
                    entries = Array(liveBoardStatuses(round: round, course: course, scoringMode: mode, basis: basis).prefix(round.playerCount))
                        .enumerated()
                        .map {
                            LeaderboardEntry(playerIndex: $0.offset, value: 0, displayText: $0.element.text, colorName: $0.element.colorName)
                        }
                case .pointsMatch:
                    entries = pointsMatchLeaderboard(round: round, course: course, basis: basis)
                case .stableford:
                    entries = stablefordLeaderboard(round: round, course: course, basis: basis)
                }

                results.append(
                    AlternativeScoringResult(
                        scoringMode: mode,
                        scoreBasis: basis,
                        entries: entries,
                        netUnavailableHoleNumbers: netUnavailableHoleNumbers(course: course, round: round, basis: basis)
                    )
                )
            }
        }

        return results
    }

    static func liveBoardStatuses(round: Round, course: Course, scoringMode: ScoringMode? = nil, basis: ScoreBasis? = nil) -> [MatchStatus] {
        let mode = scoringMode ?? round.scoringMode
        let basis = basis ?? round.scoreBasis

        switch mode {
        case .strokePlay:
            return strokePlayStatuses(round: round, course: course, basis: basis)
        case .matchPlay:
            return matchPlayStatuses(round: round, course: course, basis: basis)
        case .pointsMatch:
            return pointsMatchStatuses(round: round, course: course, basis: basis)
        case .stableford:
            return stablefordStatuses(round: round, course: course, basis: basis)
        }
    }

    private static func leaderboard(
        round: Round,
        course: Course,
        basis: ScoreBasis,
        ascending: Bool,
        totalizer: (Round, Course, ScoreBasis) -> [Double]
    ) -> [LeaderboardEntry] {
        let totals = totalizer(round, course, basis)
        let bestValue = ascending ? (totals.prefix(round.playerCount).min() ?? 0) : (totals.prefix(round.playerCount).max() ?? 0)

        return Array(0..<round.playerCount).map { playerIndex in
            let value = totals[playerIndex]
            return LeaderboardEntry(
                playerIndex: playerIndex,
                value: value,
                displayText: formattedNumber(value),
                colorName: ascending
                    ? (value <= bestValue + 0.0001 ? "up" : "score")
                    : (value >= bestValue - 0.0001 ? "up" : "score")
            )
        }
    }

    private static func strokePlayStatuses(round: Round, course: Course, basis: ScoreBasis) -> [MatchStatus] {
        let totals = totalStrokeScores(round: round, course: course, basis: basis)
        let parTotals = cumulativeParTotals(round: round, course: course)

        return Array(0..<round.playerCount).map { playerIndex in
            let total = Int(totals[playerIndex])
            let parTotal = parTotals[playerIndex]
            let diff = total - parTotal

            if parTotal > 0 {
                if diff == 0 {
                    return MatchStatus(text: "E", colorName: "score", symbol: "strokes")
                }
                return MatchStatus(
                    text: diff > 0 ? "+\(diff)" : "\(diff)",
                    colorName: diff < 0 ? "up" : "down",
                    symbol: "strokes"
                )
            }

            return MatchStatus(text: "\(total)", colorName: "score", symbol: "strokes")
        }
    }

    private static func stablefordStatuses(round: Round, course: Course, basis: ScoreBasis) -> [MatchStatus] {
        let totals = totalStablefordPoints(round: round, course: course, basis: basis)
        let leader = totals.prefix(round.playerCount).max() ?? 0

        return Array(0..<round.playerCount).map { playerIndex in
            let value = totals[playerIndex]
            return MatchStatus(
                text: formattedNumber(value),
                colorName: value >= leader - 0.0001 ? "up" : "score",
                symbol: "stableford"
            )
        }
    }

    private static func pointsMatchStatuses(round: Round, course: Course, basis: ScoreBasis) -> [MatchStatus] {
        let totals = pointsMatchTotals(round: round, course: course, basis: basis)
        let leader = totals.prefix(round.playerCount).max() ?? 0

        return Array(0..<round.playerCount).map { playerIndex in
            let value = totals[playerIndex]
            return MatchStatus(
                text: formattedPoints(value),
                colorName: value >= leader - 0.0001 ? "up" : "score",
                symbol: "points"
            )
        }
    }

    private static func matchPlayStatuses(round: Round, course: Course, basis: ScoreBasis) -> [MatchStatus] {
        if round.teamSetup == .teams, round.playerCount == 4 {
            return fourballMatchStatuses(round: round, course: course, basis: basis)
        }
        return individualMatchStatuses(round: round, course: course, basis: basis)
    }

    private static func individualMatchStatuses(round: Round, course: Course, basis: ScoreBasis) -> [MatchStatus] {
        guard round.playerCount >= 2 else {
            return Array(repeating: MatchStatus(text: "—", colorName: "score", symbol: "match"), count: Round.maxPlayerCount)
        }

        var differential = 0
        for (hole, holeState) in zip(course.holes, round.holeStates.sorted { $0.holeNumber < $1.holeNumber }) {
            guard let playerA = scoredHoleValue(playerIndex: 0, holeState: holeState, hole: hole, round: round, basisOverride: basis)?.effectiveScore,
                  let playerB = scoredHoleValue(playerIndex: 1, holeState: holeState, hole: hole, round: round, basisOverride: basis)?.effectiveScore else {
                continue
            }

            if playerA < playerB {
                differential += 1
            } else if playerB < playerA {
                differential -= 1
            }
        }

        var statuses = Array(repeating: MatchStatus(text: "—", colorName: "score", symbol: "match"), count: Round.maxPlayerCount)
        statuses[0] = matchPlayStatus(from: differential)
        statuses[1] = matchPlayStatus(from: -differential)
        return statuses
    }

    private static func fourballMatchStatuses(round: Round, course: Course, basis: ScoreBasis) -> [MatchStatus] {
        var differential = 0
        for (hole, holeState) in zip(course.holes, round.holeStates.sorted { $0.holeNumber < $1.holeNumber }) {
            let teamA = [0, 1].compactMap { scoredHoleValue(playerIndex: $0, holeState: holeState, hole: hole, round: round, basisOverride: basis)?.effectiveScore }.min()
            let teamB = [2, 3].compactMap { scoredHoleValue(playerIndex: $0, holeState: holeState, hole: hole, round: round, basisOverride: basis)?.effectiveScore }.min()
            guard let teamA, let teamB else { continue }

            if teamA < teamB {
                differential += 1
            } else if teamB < teamA {
                differential -= 1
            }
        }

        let teamAStatus = matchPlayStatus(from: differential)
        let teamBStatus = matchPlayStatus(from: -differential)
        return [teamAStatus, teamAStatus, teamBStatus, teamBStatus]
    }

    private static func matchPlayStatus(from differential: Int) -> MatchStatus {
        if differential == 0 {
            return MatchStatus(text: "AS", colorName: "score", symbol: "match")
        }

        if differential > 0 {
            return MatchStatus(text: "\(differential)UP", colorName: "up", symbol: "match")
        }

        return MatchStatus(text: "\(abs(differential))DN", colorName: "down", symbol: "match")
    }

    private static func totalStrokeScores(round: Round, course: Course, basis: ScoreBasis) -> [Double] {
        totals(round: round, course: course, basis: basis) { value, hole in
            _ = hole
            return Double(value.effectiveScore)
        }
    }

    private static func totalStablefordPoints(round: Round, course: Course, basis: ScoreBasis) -> [Double] {
        totals(round: round, course: course, basis: basis) { value, hole in
            let points = max(0, min(5, hole.par - value.effectiveScore + 2))
            return Double(points)
        }
    }

    private static func pointsMatchTotals(round: Round, course: Course, basis: ScoreBasis) -> [Double] {
        var totals = Array(repeating: 0.0, count: Round.maxPlayerCount)
        for (hole, holeState) in zip(course.holes, round.holeStates.sorted { $0.holeNumber < $1.holeNumber }) {
            let entered = Array(0..<round.playerCount).compactMap { playerIndex -> (Int, Int)? in
                guard let value = scoredHoleValue(playerIndex: playerIndex, holeState: holeState, hole: hole, round: round, basisOverride: basis) else {
                    return nil
                }
                return (playerIndex, value.effectiveScore)
            }
            guard entered.count >= 2 else { continue }

            let lowest = entered.map(\.1).min() ?? 0
            let winners = entered.filter { $0.1 == lowest }.map(\.0)
            let share = 1.0 / Double(winners.count)
            for winner in winners {
                totals[winner] += share
            }
        }
        return totals
    }

    private static func totals(
        round: Round,
        course: Course,
        basis: ScoreBasis,
        valueForHole: (ScoredHoleValue, Hole) -> Double
    ) -> [Double] {
        var totals = Array(repeating: 0.0, count: Round.maxPlayerCount)
        for (hole, holeState) in zip(course.holes, round.holeStates.sorted { $0.holeNumber < $1.holeNumber }) {
            for playerIndex in 0..<round.playerCount {
                guard let value = scoredHoleValue(playerIndex: playerIndex, holeState: holeState, hole: hole, round: round, basisOverride: basis) else {
                    continue
                }
                totals[playerIndex] += valueForHole(value, hole)
            }
        }
        return totals
    }

    private static func cumulativeParTotals(round: Round, course: Course) -> [Int] {
        var totals = Array(repeating: 0, count: Round.maxPlayerCount)
        for (hole, holeState) in zip(course.holes, round.holeStates.sorted { $0.holeNumber < $1.holeNumber }) {
            for playerIndex in 0..<round.playerCount where holeState.playerScores[playerIndex] > 0 {
                totals[playerIndex] += hole.par
            }
        }
        return totals
    }

    private static func netUnavailableHoleNumbers(course: Course, round: Round, basis: ScoreBasis) -> [Int] {
        guard basis == .net else { return [] }
        return course.holes.compactMap { $0.strokeIndex == nil ? $0.holeNumber : nil }
    }

    private static func formattedNumber(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if abs(rounded.rounded(.towardZero) - rounded) < 0.0001 {
            return String(Int(rounded))
        }
        if abs((rounded * 10).rounded() - (rounded * 10)) < 0.0001 {
            return String(format: "%.1f", rounded)
        }
        return String(format: "%.2f", rounded)
    }

    private static func formattedPoints(_ value: Double) -> String {
        formattedNumber(value)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
