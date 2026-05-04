import CoreLocation
import Foundation

@MainActor
final class RoundStore: ObservableObject {
    enum CourseSyncResult: Equatable {
        case updated(courseCount: Int)
        case failed(message: String)
        case skipped
    }

    enum RoundUploadResult: Equatable {
        case uploaded
        case failed(message: String)
    }

    enum CourseReportResult: Equatable {
        case sent
        case failed(message: String)
    }

    struct NearbyCourse: Identifiable, Equatable {
        let course: Course
        let distanceMeters: Int

        var id: UUID { course.id }
    }

    @Published private(set) var courses: [Course] = []
    @Published private(set) var selectedCourseID: UUID?
    @Published private(set) var currentRound: Round?
    @Published private(set) var isSyncingCourses = false
    @Published private(set) var lastCoursesSyncAt: Date?
    @Published private(set) var roundOwnerEmail = UserDefaults.standard.string(forKey: "roundOwnerEmail") ?? ""

    private(set) var lastAction: LastScoreAction?
    private var hasBootstrapped = false

    private let coursesURL = URL(string: "https://just-golf.pages.dev/api/courses")!
    private let roundUploadURL = URL(string: "https://just-golf.pages.dev/api/rounds/upload")!
    private let courseReportURL = URL(string: "https://just-golf.pages.dev/api/course-requests")!
    private static let roundOwnerEmailKey = "roundOwnerEmail"
    private static let nearbyCourseRadiusMeters = 10_000
    private static let automaticCourseSelectionRadiusMeters = nearbyCourseRadiusMeters

    var selectedCourse: Course? {
        guard let selectedCourseID else { return courses.first }
        return courses.first(where: { $0.id == selectedCourseID }) ?? courses.first
    }

    var currentHole: Hole? {
        guard let round = currentRound, let course = selectedCourse else { return nil }
        return course.holes.first(where: { $0.holeNumber == round.currentHoleNumber })
    }

    var currentHoleState: HoleState? {
        guard let round = currentRound else { return nil }
        return round.holeStates.first(where: { $0.holeNumber == round.currentHoleNumber })
    }

    var currentRoundExport: RoundExport? {
        guard let round = currentRound, let course = selectedCourse else {
            return nil
        }

        return RoundExport(
            exportedAt: .now,
            note: "Shot GPS points are only recorded when player A score is incremented live on the watch. If strokes were added later in a batch, those saved GPS points reflect the later entry location rather than the original shot locations.",
            ownerEmail: normalizedRoundOwnerEmail.isEmpty ? nil : normalizedRoundOwnerEmail,
            course: RoundExport.ExportCourse(
                id: course.id,
                name: course.name,
                holes: course.holes.map {
                    RoundExport.ExportHole(
                        holeNumber: $0.holeNumber,
                        par: $0.par,
                        greenLatitude: $0.greenLatitude,
                        greenLongitude: $0.greenLongitude
                    )
                }
            ),
            round: RoundExport.ExportRound(
                id: round.id,
                startedAt: round.startedAt,
                currentHoleNumber: round.currentHoleNumber,
                playerCount: round.playerCount,
                teamSetup: round.teamSetup.rawValue,
                scoringMode: round.scoringMode.rawValue,
                scoreBasis: round.scoreBasis.rawValue,
                players: Array(0..<round.playerCount).map { playerIndex in
                    RoundExport.ExportPlayer(
                        index: playerIndex,
                        displayName: playerName(for: playerIndex),
                        handicap: round.players.indices.contains(playerIndex) ? round.players[playerIndex].handicap : nil
                    )
                },
                holeStates: round.holeStates.map {
                    RoundExport.ExportHoleState(
                        holeNumber: $0.holeNumber,
                        playerScores: Array($0.playerScores.prefix(round.playerCount)),
                        myShotPoints: $0.myShotPoints
                    )
                }
            )
        )
    }

    var normalizedRoundOwnerEmail: String {
        roundOwnerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var alternativeScoringResults: [AlternativeScoringResult] {
        guard let round = currentRound, let course = selectedCourse else {
            return []
        }
        return RoundScoringCalculator.alternativeResults(round: round, course: course)
    }

    var playerCount: Int {
        currentRound?.playerCount ?? Round.defaultPlayerCount
    }

    var teamSetup: TeamSetup {
        currentRound?.teamSetup ?? .individual
    }

    var scoringMode: ScoringMode {
        currentRound?.scoringMode ?? .strokePlay
    }

    var scoreBasis: ScoreBasis {
        currentRound?.scoreBasis ?? .gross
    }

    var distanceUnit: DistanceUnit {
        currentRound?.distanceUnit ?? .meters
    }

    var availableScoringModes: [ScoringMode] {
        ScoringMode.allCases.filter { $0.isAvailable(for: playerCount, teamSetup: teamSetup) }
    }

    var courseCatalogStatusText: String {
        if isSyncingCourses {
            return "Syncing courses..."
        }

        if let lastCoursesSyncAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let relative = formatter.localizedString(for: lastCoursesSyncAt, relativeTo: .now)
            return "\(courses.count) courses · Updated \(relative)"
        }

        return "\(courses.count) courses · Local catalog"
    }

    func nearbyCourses(to location: CLLocation?, limit: Int = 5) -> [NearbyCourse] {
        guard let location else { return [] }

        return courses
            .compactMap { course -> NearbyCourse? in
                guard let distance = distanceMeters(from: location, to: course) else { return nil }
                guard distance <= Self.nearbyCourseRadiusMeters else { return nil }
                return NearbyCourse(course: course, distanceMeters: distance)
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .prefix(limit)
            .map { $0 }
    }

    func closestCourse(to location: CLLocation?) -> NearbyCourse? {
        guard let location else { return nil }

        return courses
            .compactMap { course -> NearbyCourse? in
                guard let distance = distanceMeters(from: location, to: course) else { return nil }
                return NearbyCourse(course: course, distanceMeters: distance)
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .first
    }

    @discardableResult
    func selectNearestAvailableCourse(to location: CLLocation?) -> Bool {
        guard let closest = closestCourse(to: location),
              closest.distanceMeters <= Self.automaticCourseSelectionRadiusMeters,
              selectedCourseID != closest.course.id else {
            return false
        }

        selectCourse(id: closest.course.id)
        return true
    }

    func playerName(for index: Int) -> String {
        guard let round = currentRound, round.players.indices.contains(index) else {
            return defaultPlayerLabel(for: index)
        }
        return round.players[index].resolvedName(defaultLabel: defaultPlayerLabel(for: index))
    }

    func isPlayerEnabled(_ index: Int) -> Bool {
        index < playerCount
    }

    func playerHandicap(for index: Int) -> Int? {
        guard let round = currentRound, round.players.indices.contains(index) else { return nil }
        return round.players[index].handicap
    }

    func updateRoundOwnerEmail(_ email: String) {
        roundOwnerEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(roundOwnerEmail, forKey: Self.roundOwnerEmailKey)
    }

    func uploadCurrentRound() async -> RoundUploadResult {
        guard let export = currentRoundExport else {
            return .failed(message: "No round data")
        }

        let email = normalizedRoundOwnerEmail
        guard email.contains("@"), email.contains(".") else {
            return .failed(message: "Add email first")
        }

        do {
            var request = URLRequest(url: roundUploadURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "content-type")

            let upload = RoundUploadRequest(
                email: email,
                courseId: export.course.id,
                title: "\(export.course.name) · \(Self.shortDateFormatter.string(from: export.round.startedAt))",
                roundJson: export
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(upload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed(message: "Upload failed")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if let payload = try? JSONDecoder().decode(RoundUploadErrorResponse.self, from: data) {
                    return .failed(message: payload.error)
                }
                return .failed(message: "Upload \(httpResponse.statusCode)")
            }

            return .uploaded
        } catch {
            #if DEBUG
            print("Failed to upload round: \(error.localizedDescription)")
            #endif
            return .failed(message: "Upload failed")
        }
    }

    func reportMissingCourse(location: CLLocation?) async -> CourseReportResult {
        guard let location else {
            return .failed(message: "Waiting for GPS")
        }

        do {
            var request = URLRequest(url: courseReportURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "content-type")

            let closest = closestCourse(to: location)
            let payload = CourseReportRequest(
                email: normalizedRoundOwnerEmail.isEmpty ? nil : normalizedRoundOwnerEmail,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
                closestCourseId: closest?.course.id,
                closestCourseName: closest?.course.name,
                closestCourseDistanceMeters: closest?.distanceMeters
            )
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed(message: "Report failed")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if let payload = try? JSONDecoder().decode(RoundUploadErrorResponse.self, from: data) {
                    return .failed(message: payload.error)
                }
                return .failed(message: "Report \(httpResponse.statusCode)")
            }

            return .sent
        } catch {
            #if DEBUG
            print("Failed to report missing course: \(error.localizedDescription)")
            #endif
            return .failed(message: "Report failed")
        }
    }

    func score(for playerIndex: Int) -> Int {
        guard let scores = currentHoleState?.playerScores, scores.indices.contains(playerIndex) else { return 0 }
        return scores[playerIndex]
    }

    func boardStatus(for playerIndex: Int) -> MatchStatus? {
        guard let round = currentRound, let course = selectedCourse, playerIndex < round.playerCount else {
            return nil
        }
        let statuses = RoundScoringCalculator.liveBoardStatuses(round: round, course: course)
        guard statuses.indices.contains(playerIndex) else { return nil }
        return statuses[playerIndex]
    }

    func bootstrapIfNeeded() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        courses = loadInitialCourses()
        loadState()

        if currentRound == nil, let defaultCourse = courses.first {
            selectedCourseID = defaultCourse.id
            currentRound = Round.fresh(for: defaultCourse)
            saveState()
        }

        Task {
            _ = await refreshCoursesFromRemote()
        }
    }

    func refreshCoursesFromRemote() async -> CourseSyncResult {
        guard !isSyncingCourses else {
            return .skipped
        }

        isSyncingCourses = true
        defer { isSyncingCourses = false }

        do {
            var request = URLRequest(url: coursesURL)
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return .failed(message: "Sync failed")
            }

            let decoder = JSONDecoder()
            let payload = try decoder.decode(CoursesResponse.self, from: data)
            let remoteCourses = try payload.courses.compactMap { try $0.asCourse() }.sorted { $0.name < $1.name }

            guard !remoteCourses.isEmpty else {
                return .failed(message: "No courses found")
            }

            applyCourses(remoteCourses)
            saveCoursesCache(remoteCourses)
            lastCoursesSyncAt = .now
            return .updated(courseCount: remoteCourses.count)
        } catch {
            #if DEBUG
            print("Failed to sync courses: \(error.localizedDescription)")
            #endif
            return .failed(message: "Using local courses")
        }
    }

    func incrementMyScore(using location: CLLocation?) {
        incrementScore(for: 0, using: location)
    }

    func incrementBuddyScore(at index: Int = 1) {
        incrementScore(for: index, using: nil)
    }

    private func incrementScore(for playerIndex: Int, using location: CLLocation?) {
        guard var round = currentRound,
              playerIndex < round.playerCount,
              let holeStateIndex = round.holeStates.firstIndex(where: { $0.holeNumber == round.currentHoleNumber }) else {
            return
        }

        round.holeStates[holeStateIndex].playerScores[playerIndex] += 1

        if playerIndex == 0, let location {
            let strokeNumber = round.holeStates[holeStateIndex].playerScores[playerIndex]
            let shot = ShotPoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: .now,
                holeNumber: round.currentHoleNumber,
                strokeNumber: strokeNumber
            )
            round.holeStates[holeStateIndex].myShotPoints.append(shot)
        }

        currentRound = round
        lastAction = .playerScore(holeNumber: round.currentHoleNumber, playerIndex: playerIndex)
        saveState()
    }

    func decrementMyScore() {
        decrementScore(for: 0)
    }

    func decrementBuddyScore(at index: Int = 1) {
        decrementScore(for: index)
    }

    private func decrementScore(for playerIndex: Int) {
        guard var round = currentRound,
              let holeStateIndex = round.holeStates.firstIndex(where: { $0.holeNumber == round.currentHoleNumber }),
              round.holeStates[holeStateIndex].playerScores.indices.contains(playerIndex),
              round.holeStates[holeStateIndex].playerScores[playerIndex] > 0 else {
            return
        }

        round.holeStates[holeStateIndex].playerScores[playerIndex] -= 1
        if playerIndex == 0, !round.holeStates[holeStateIndex].myShotPoints.isEmpty {
            round.holeStates[holeStateIndex].myShotPoints.removeLast()
        }
        currentRound = round
        lastAction = nil
        saveState()
    }

    func undoLastAction() {
        guard let lastAction, var round = currentRound else { return }

        switch lastAction {
        case .playerScore(let holeNumber, let playerIndex):
            guard let holeStateIndex = round.holeStates.firstIndex(where: { $0.holeNumber == holeNumber }),
                  round.holeStates[holeStateIndex].playerScores.indices.contains(playerIndex),
                  round.holeStates[holeStateIndex].playerScores[playerIndex] > 0 else {
                break
            }

            round.holeStates[holeStateIndex].playerScores[playerIndex] -= 1
            if playerIndex == 0, !round.holeStates[holeStateIndex].myShotPoints.isEmpty {
                round.holeStates[holeStateIndex].myShotPoints.removeLast()
            }
        }

        currentRound = round
        self.lastAction = nil
        saveState()
    }

    func startNewRound() {
        guard let course = selectedCourse else { return }
        let playerCount = currentRound?.playerCount ?? Round.defaultPlayerCount
        currentRound = Round(
            courseID: course.id,
            currentHoleNumber: 1,
            playerCount: playerCount,
            players: currentRound?.players ?? Array(repeating: PlayerConfiguration(), count: Round.maxPlayerCount),
            teamSetup: currentRound?.teamSetup ?? .individual,
            scoringMode: currentRound?.scoringMode ?? .strokePlay,
            scoreBasis: currentRound?.scoreBasis ?? .gross,
            holeStates: course.holes.map { HoleState(holeNumber: $0.holeNumber) }
        )
        lastAction = nil
        saveState()
    }

    func resetCurrentHole() {
        guard var round = currentRound,
              let holeStateIndex = round.holeStates.firstIndex(where: { $0.holeNumber == round.currentHoleNumber }) else {
            return
        }

        round.holeStates[holeStateIndex].playerScores = Array(repeating: 0, count: Round.maxPlayerCount)
        round.holeStates[holeStateIndex].myShotPoints.removeAll()
        currentRound = round
        lastAction = nil
        saveState()
    }

    func selectCourse(id: UUID) {
        guard id != selectedCourseID, let course = courses.first(where: { $0.id == id }) else { return }
        selectedCourseID = course.id
        let playerCount = currentRound?.playerCount ?? Round.defaultPlayerCount
        currentRound = Round(
            courseID: course.id,
            currentHoleNumber: 1,
            playerCount: playerCount,
            players: currentRound?.players ?? Array(repeating: PlayerConfiguration(), count: Round.maxPlayerCount),
            teamSetup: currentRound?.teamSetup ?? .individual,
            scoringMode: currentRound?.scoringMode ?? .strokePlay,
            scoreBasis: currentRound?.scoreBasis ?? .gross,
            holeStates: course.holes.map { HoleState(holeNumber: $0.holeNumber) }
        )
        lastAction = nil
        saveState()
    }

    func updatePlayerCount(_ newValue: Int) {
        guard var round = currentRound else { return }
        let playerCount = min(max(newValue, Round.minPlayerCount), Round.maxPlayerCount)
        guard round.playerCount != playerCount else { return }

        round.playerCount = playerCount
        round.holeStates = round.holeStates.map { holeState in
            var updated = holeState
            updated.playerScores = HoleState.normalizedScores(holeState.playerScores)
            return updated
        }
        round.sanitizeFormat()
        currentRound = round
        lastAction = nil
        saveState()
    }

    func updateTeamSetup(_ newValue: TeamSetup) {
        guard var round = currentRound, round.teamSetup != newValue else { return }
        round.teamSetup = newValue
        round.sanitizeFormat()
        currentRound = round
        lastAction = nil
        saveState()
    }

    func updateScoringMode(_ newValue: ScoringMode) {
        guard var round = currentRound, round.scoringMode != newValue else { return }
        round.scoringMode = newValue
        round.sanitizeFormat()
        currentRound = round
        lastAction = nil
        saveState()
    }

    func cycleScoringMode() {
        let modes = availableScoringModes
        guard !modes.isEmpty else { return }

        let currentIndex = modes.firstIndex(of: scoringMode) ?? modes.startIndex
        let nextIndex = modes.index(after: currentIndex)
        updateScoringMode(modes[nextIndex == modes.endIndex ? modes.startIndex : nextIndex])
    }

    func updateScoreBasis(_ newValue: ScoreBasis) {
        guard var round = currentRound, round.scoreBasis != newValue else { return }
        round.scoreBasis = newValue
        currentRound = round
        lastAction = nil
        saveState()
    }

    func toggleScoreBasis() {
        updateScoreBasis(scoreBasis == .gross ? .net : .gross)
    }

    func updateDistanceUnit(_ newValue: DistanceUnit) {
        guard var round = currentRound, round.distanceUnit != newValue else { return }
        round.distanceUnit = newValue
        currentRound = round
        saveState()
    }

    func updatePlayerDisplayName(_ newValue: String?, for playerIndex: Int) {
        guard var round = currentRound, round.players.indices.contains(playerIndex) else { return }
        round.players[playerIndex].displayName = PlayerConfiguration.normalizedName(newValue)
        currentRound = round
        saveState()
    }

    func updatePlayerHandicap(_ newValue: Int?, for playerIndex: Int) {
        guard var round = currentRound, round.players.indices.contains(playerIndex) else { return }
        round.players[playerIndex].handicap = PlayerConfiguration.normalizedHandicap(newValue)
        currentRound = round
        saveState()
    }

    func resetPlayers() {
        guard var round = currentRound else { return }
        round.players = Array(repeating: PlayerConfiguration(), count: Round.maxPlayerCount)
        currentRound = round
        saveState()
    }

    func jumpToHole(_ holeNumber: Int) {
        guard var round = currentRound,
              let course = selectedCourse,
              course.holes.contains(where: { $0.holeNumber == holeNumber }) else {
            return
        }

        round.currentHoleNumber = holeNumber
        currentRound = round
        lastAction = nil
        saveState()
    }

    func completeCurrentHoleAndAdvance() {
        guard var round = currentRound, let course = selectedCourse else {
            return
        }

        if let nextHole = course.holes.first(where: { $0.holeNumber > round.currentHoleNumber }) {
            round.currentHoleNumber = nextHole.holeNumber
        } else if let firstHole = course.holes.first {
            round.currentHoleNumber = firstHole.holeNumber
        }

        currentRound = round
        lastAction = nil
        saveState()
    }

    func goToPreviousHole() {
        guard var round = currentRound, let course = selectedCourse else {
            return
        }

        if let previousHole = course.holes.last(where: { $0.holeNumber < round.currentHoleNumber }) {
            round.currentHoleNumber = previousHole.holeNumber
        } else if let lastHole = course.holes.last {
            round.currentHoleNumber = lastHole.holeNumber
        }

        currentRound = round
        lastAction = nil
        saveState()
    }

    func goToNextHole() {
        completeCurrentHoleAndAdvance()
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateFileURL) else {
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let persistedState = try decoder.decode(PersistedRoundState.self, from: data)
            selectedCourseID = persistedState.selectedCourseID

            if courses.contains(where: { $0.id == persistedState.round.courseID }) {
                currentRound = persistedState.round
            } else if let fallbackCourse = courses.first(where: { $0.id == persistedState.selectedCourseID }) ?? courses.first {
                currentRound = Round.fresh(for: fallbackCourse)
                selectedCourseID = fallbackCourse.id
            }
        } catch {
            if let fallbackCourse = courses.first {
                selectedCourseID = fallbackCourse.id
                currentRound = Round.fresh(for: fallbackCourse)
            }
        }
    }

    private func saveState() {
        guard let selectedCourseID, let currentRound else { return }

        do {
            try FileManager.default.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(PersistedRoundState(selectedCourseID: selectedCourseID, round: currentRound))
            try data.write(to: stateFileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("Failed to save round state: \(error.localizedDescription)")
            #endif
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private func loadInitialCourses() -> [Course] {
        if let cachedCourses = loadCachedCourses(), !cachedCourses.isEmpty {
            return cachedCourses
        }

        return SampleCourseLoader.loadCourses()
    }

    private func loadCachedCourses() -> [Course]? {
        guard let data = try? Data(contentsOf: coursesCacheFileURL) else {
            return nil
        }

        do {
            return try JSONDecoder().decode([Course].self, from: data)
        } catch {
            #if DEBUG
            print("Failed to decode cached courses: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private func saveCoursesCache(_ courses: [Course]) {
        do {
            try FileManager.default.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(courses)
            try data.write(to: coursesCacheFileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("Failed to cache courses: \(error.localizedDescription)")
            #endif
        }
    }

    private func applyCourses(_ newCourses: [Course]) {
        let previousSelectedCourseID = selectedCourseID
        let previousRound = currentRound

        courses = newCourses

        if let previousSelectedCourseID,
           let selectedCourse = courses.first(where: { $0.id == previousSelectedCourseID }) {
            selectedCourseID = selectedCourse.id
        } else {
            selectedCourseID = courses.first?.id
        }

        if let previousRound,
           let matchingCourse = courses.first(where: { $0.id == previousRound.courseID }) {
            currentRound = normalizedRound(previousRound, for: matchingCourse)
        } else if let selectedCourse {
            currentRound = Round.fresh(for: selectedCourse)
        }

        saveState()
    }

    private func normalizedRound(_ round: Round, for course: Course) -> Round {
        let existingByHole = Dictionary(uniqueKeysWithValues: round.holeStates.map { ($0.holeNumber, $0) })
        let holeStates = course.holes.map { hole -> HoleState in
            if let existingState = existingByHole[hole.holeNumber] {
                return HoleState(
                    holeNumber: hole.holeNumber,
                    playerScores: existingState.playerScores,
                    myShotPoints: existingState.myShotPoints.filter { $0.holeNumber == hole.holeNumber }
                )
            }

            return HoleState(holeNumber: hole.holeNumber)
        }

        let currentHoleNumber = course.holes.contains(where: { $0.holeNumber == round.currentHoleNumber })
            ? round.currentHoleNumber
            : (course.holes.first?.holeNumber ?? 1)

        return Round(
            id: round.id,
            startedAt: round.startedAt,
            courseID: course.id,
            currentHoleNumber: currentHoleNumber,
            playerCount: round.playerCount,
            players: round.players,
            teamSetup: round.teamSetup,
            scoringMode: round.scoringMode,
            scoreBasis: round.scoreBasis,
            holeStates: holeStates
        )
    }

    private func distanceMeters(from location: CLLocation, to course: Course) -> Int? {
        let greenLocations = course.holes.map {
            CLLocation(latitude: $0.greenLatitude, longitude: $0.greenLongitude)
        }
        return greenLocations
            .map { Int(location.distance(from: $0).rounded()) }
            .min()
    }

    private func defaultPlayerLabel(for index: Int) -> String {
        switch index {
        case 0: return "A"
        case 1: return "B"
        case 2: return "C"
        case 3: return "D"
        default: return "P\(index + 1)"
        }
    }

    private var storageDirectoryURL: URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return baseDirectory.appendingPathComponent("Bogey", isDirectory: true)
    }

    private var stateFileURL: URL {
        storageDirectoryURL.appendingPathComponent("round-state.json")
    }

    private var coursesCacheFileURL: URL {
        storageDirectoryURL.appendingPathComponent("courses-cache.json")
    }
}

private struct RoundUploadRequest: Encodable {
    let email: String
    let courseId: UUID
    let title: String
    let roundJson: RoundExport
}

private struct CourseReportRequest: Encodable {
    let email: String?
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double?
    let closestCourseId: UUID?
    let closestCourseName: String?
    let closestCourseDistanceMeters: Int?
}

private struct RoundUploadErrorResponse: Decodable {
    let error: String
}

private struct CoursesResponse: Decodable {
    let courses: [RemoteCourse]
}

private struct RemoteCourse: Decodable {
    let id: String
    let name: String
    let holes: [RemoteHole]

    func asCourse() throws -> Course? {
        guard let uuid = UUID(uuidString: id) else {
            return nil
        }

        return Course(
            id: uuid,
            name: name,
            holes: holes.map {
                Hole(
                    holeNumber: $0.holeNumber,
                    greenLatitude: $0.greenLatitude,
                    greenLongitude: $0.greenLongitude,
                    par: $0.par,
                    strokeIndex: $0.strokeIndex,
                    teeDistancesMeters: $0.teeDistancesMeters
                )
            }
        )
    }
}

private struct RemoteHole: Decodable {
    let holeNumber: Int
    let par: Int
    let strokeIndex: Int?
    let greenLatitude: Double
    let greenLongitude: Double
    let teeDistancesMeters: [String: Int]
}
