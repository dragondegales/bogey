import SwiftUI
import WatchKit

private enum SettingsDestination: Hashable {
    case course
    case playerName(Int)
    case playerHandicap(Int)
    case export
}

struct SettingsView: View {
    @EnvironmentObject private var roundStore: RoundStore
    @EnvironmentObject private var locationManager: LocationManager

    @State private var confirmationMessage: String?
    @State private var navigationPath: [SettingsDestination] = []
    @State private var isReportingMissingCourse = false
    @State private var selectedMissingCourse = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Course")
                    courseCard()

                    sectionTitle("Players")
                    playerCountCircles()
                    ForEach(Array(0..<roundStore.playerCount), id: \.self) { playerIndex in
                        playerRow(for: playerIndex)
                    }

                    sectionTitle("Scoring")
                    scoringToggles()

                    sectionTitle("Distance")
                    distanceUnitToggles()

                    sectionTitle("Round")
                    actionButton(title: "Reset Hole", role: .destructive) {
                        roundStore.resetCurrentHole()
                    }
                    actionButton(title: "Reset Round", role: .destructive) {
                        roundStore.startNewRound()
                    }
                    actionButton(title: "Reset Players", role: .destructive) {
                        roundStore.resetPlayers()
                    }
                    selectionCard(title: "Export", value: "Scores + GPS JSON") {
                        navigationPath.append(.export)
                    }
                }
                .frame(maxWidth: 168, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .background(Color.black)
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .course:
                    CourseSelectionView(selectedMissingCourse: selectedMissingCourse) { courseID in
                        selectedMissingCourse = false
                        roundStore.selectCourse(id: courseID)
                    } onSelectMissingCourse: {
                        selectedMissingCourse = true
                    }
                    .environmentObject(roundStore)
                    .environmentObject(locationManager)
                case .playerName(let playerIndex):
                    PlayerNameView(playerIndex: playerIndex)
                        .environmentObject(roundStore)
                case .playerHandicap(let playerIndex):
                    PlayerHandicapView(playerIndex: playerIndex)
                        .environmentObject(roundStore)
                case .export:
                    ExportRoundView()
                        .environmentObject(roundStore)
                }
            }
            .overlay(alignment: .bottom) {
                if let confirmationMessage {
                    Text(confirmationMessage)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .onAppear {
            locationManager.requestAuthorizationIfNeeded()
            if !selectedMissingCourse {
                roundStore.selectNearestAvailableCourse(to: locationManager.currentLocation)
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            if !selectedMissingCourse {
                roundStore.selectNearestAvailableCourse(to: newLocation)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var courseSelectionValue: String {
        if selectedMissingCourse {
            return "Missing Course"
        }

        if let closest = roundStore.closestCourse(to: locationManager.currentLocation) {
            if closest.distanceMeters <= 10_000 {
                return "\(closest.course.name) · \(formatDistance(closest.distanceMeters))"
            }
            return "Course not available"
        }

        return locationManager.currentLocation == nil ? "Finding nearby courses..." : "Course not available"
    }

    private var courseStatusValue: String {
        if locationManager.currentLocation == nil {
            return "Waiting for GPS"
        }

        let nearbyCount = roundStore.nearbyCourses(to: locationManager.currentLocation).count
        if nearbyCount > 0 {
            return nearbyCount == 1 ? "1 nearby course" : "\(nearbyCount) nearby courses"
        }

        if let closest = roundStore.closestCourse(to: locationManager.currentLocation) {
            return "Closest is \(formatDistance(closest.distanceMeters)) away"
        }

        return "No course catalog"
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 2)
    }

    private func selectionCard(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))

                HStack(spacing: 8) {
                    Text(value)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func courseCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                navigationPath.append(.course)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nearby Course")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))

                        Text(courseSelectionValue)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .buttonStyle(.plain)

            if selectedMissingCourse {
                Button {
                    reportMissingCourse()
                } label: {
                    Text(isReportingMissingCourse ? "Sending..." : "Inform")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(locationManager.currentLocation == nil ? .white.opacity(0.48) : Color(red: 0.75, green: 0.95, blue: 0.48))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isReportingMissingCourse || locationManager.currentLocation == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func playerCountCircles() -> some View {
        HStack(spacing: 4) {
            ForEach(1...4, id: \.self) { count in
                Button {
                    roundStore.updatePlayerCount(count)
                } label: {
                    Text("\(count)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(roundStore.playerCount == count ? .black : .white.opacity(0.76))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(roundStore.playerCount == count ? Color(red: 0.68, green: 0.92, blue: 0.45) : Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func playerRow(for playerIndex: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                navigationPath.append(.playerName(playerIndex))
            } label: {
                HStack(spacing: 4) {
                    Text(roundStore.playerName(for: playerIndex))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Spacer(minLength: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                navigationPath.append(.playerHandicap(playerIndex))
            } label: {
                HStack(spacing: 4) {
                    Spacer(minLength: 2)

                    Text(handicapTitle(for: playerIndex))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(width: 68, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func scoringToggles() -> some View {
        VStack(spacing: 8) {
            toggleRow(
                leftTitle: "Single",
                rightTitle: "Team",
                isRightSelected: roundStore.teamSetup == .teams,
                isRightEnabled: roundStore.playerCount >= 4
            ) { useRight in
                let nextValue: TeamSetup = useRight ? .teams : .individual
                roundStore.updateTeamSetup(nextValue)
            }

            toggleRow(
                leftTitle: "Gross",
                rightTitle: "Net",
                isRightSelected: roundStore.scoreBasis == .net,
                isRightEnabled: true
            ) { useRight in
                let nextValue: ScoreBasis = useRight ? .net : .gross
                roundStore.updateScoreBasis(nextValue)
            }
        }
    }

    private func distanceUnitToggles() -> some View {
        toggleRow(
            leftTitle: "Meters",
            rightTitle: "Yards",
            isRightSelected: roundStore.distanceUnit == .yards,
            isRightEnabled: true
        ) { useRight in
            roundStore.updateDistanceUnit(useRight ? .yards : .meters)
        }
    }

    private func toggleRow(leftTitle: String, rightTitle: String, isRightSelected: Bool, isRightEnabled: Bool, onSelect: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 6) {
            togglePill(title: leftTitle, isSelected: !isRightSelected, isEnabled: true) {
                onSelect(false)
            }

            togglePill(title: rightTitle, isSelected: isRightSelected, isEnabled: isRightEnabled) {
                onSelect(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func togglePill(title: String, isSelected: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .black : .white.opacity(isEnabled ? 0.78 : 0.38))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(isSelected ? Color(red: 0.68, green: 0.92, blue: 0.45) : Color.white.opacity(0.07))
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func actionButton(title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        actionButton(title: title, role: role, isDisabled: false, action: action)
    }

    private func actionButton(title: String, role: ButtonRole? = nil, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(isDisabled ? .white.opacity(0.48) : .white)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.white.opacity(isDisabled ? 0.06 : (role == .destructive ? 0.14 : 0.1)))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func statusCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func showConfirmation(_ message: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            confirmationMessage = message
        }
        WKInterfaceDevice.current().play(.success)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            guard confirmationMessage == message else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                confirmationMessage = nil
            }
        }
    }

    private func handicapTitle(for playerIndex: Int) -> String {
        if let handicap = roundStore.playerHandicap(for: playerIndex) {
            return "HCP \(handicap)"
        }
        return "HCP --"
    }

    private func reportMissingCourse() {
        guard !isReportingMissingCourse else { return }
        isReportingMissingCourse = true

        Task { @MainActor in
            let result = await roundStore.reportMissingCourse(location: locationManager.currentLocation)
            isReportingMissingCourse = false

            switch result {
            case .sent:
                showConfirmation("Admin notified")
            case .failed(let message):
                showConfirmation(message)
            }
        }
    }

    private func formatDistance(_ meters: Int) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km", Double(meters) / 1_000)
        }

        return "\(meters) m"
    }
}

private struct ExportRoundView: View {
    @EnvironmentObject private var roundStore: RoundStore
    @State private var isUploading = false
    @State private var uploadMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if roundStore.currentRoundExport != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your email")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))

                        TextField("you@example.com", text: Binding(
                            get: { roundStore.roundOwnerEmail },
                            set: { roundStore.updateRoundOwnerEmail($0) }
                        ))
                        .textContentType(.emailAddress)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        uploadRound()
                    } label: {
                        Text(isUploading ? "Exporting..." : "Export Round")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color(red: 0.75, green: 0.95, blue: 0.48))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploading)

                    if let uploadMessage {
                        Text(uploadMessage)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(uploadMessage == "Uploaded. Check email." ? Color(red: 0.75, green: 0.95, blue: 0.48) : .white.opacity(0.68))
                    }
                } else {
                    Text("No round data available.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.black)
        .navigationTitle("Export")
    }

    private func uploadRound() {
        guard !isUploading else { return }
        isUploading = true
        uploadMessage = nil

        Task { @MainActor in
            let result = await roundStore.uploadCurrentRound()
            switch result {
            case .uploaded:
                uploadMessage = "Uploaded. Check email."
                WKInterfaceDevice.current().play(.success)
            case .failed(let message):
                uploadMessage = message
                WKInterfaceDevice.current().play(.failure)
            }
            isUploading = false
        }
    }
}

private struct TeamSetupSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roundStore: RoundStore

    let onSelect: (TeamSetup) -> Void

    var body: some View {
        List(availableTeamSetups) { teamSetup in
            Button {
                onSelect(teamSetup)
                dismiss()
            } label: {
                HStack {
                    Text(teamSetup.title)

                    Spacer(minLength: 8)

                    if roundStore.teamSetup == teamSetup {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Teams")
    }

    private var availableTeamSetups: [TeamSetup] {
        roundStore.playerCount >= 4 ? TeamSetup.allCases : [.individual]
    }
}

private struct ScoringModeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roundStore: RoundStore

    let onSelect: (ScoringMode) -> Void

    var body: some View {
        List(roundStore.availableScoringModes) { scoringMode in
            Button {
                onSelect(scoringMode)
                dismiss()
            } label: {
                HStack {
                    Text(scoringMode.title)

                    Spacer(minLength: 8)

                    if roundStore.scoringMode == scoringMode {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Mode")
    }

}

private struct ScoreBasisSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roundStore: RoundStore

    let onSelect: (ScoreBasis) -> Void

    var body: some View {
        List(ScoreBasis.allCases) { scoreBasis in
            Button {
                onSelect(scoreBasis)
                dismiss()
            } label: {
                HStack {
                    Text(scoreBasis.title)

                    Spacer(minLength: 8)

                    if roundStore.scoreBasis == scoreBasis {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Basis")
    }
}

private struct PlayerNameView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roundStore: RoundStore

    let playerIndex: Int

    @State private var displayName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Player Initials")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))

                TextField(defaultLabel, text: $displayName)
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.done)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onSubmit {
                        save()
                    }

                actionButton(title: "Done") {
                    save()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.black)
        .navigationTitle("Player")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            displayName = roundStore.playerName(for: playerIndex) == defaultLabel ? "" : roundStore.playerName(for: playerIndex)
        }
    }

    private var defaultLabel: String {
        switch playerIndex {
        case 0: return "A"
        case 1: return "B"
        case 2: return "C"
        case 3: return "D"
        default: return "P\(playerIndex + 1)"
        }
    }

    private func save() {
        roundStore.updatePlayerDisplayName(displayName, for: playerIndex)
        dismiss()
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerHandicapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roundStore: RoundStore

    let playerIndex: Int

    @State private var handicapSelection = -1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(roundStore.playerName(for: playerIndex)) Handicap")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))

                Picker("Handicap", selection: $handicapSelection) {
                    Text("None").tag(-1)
                    ForEach(0...54, id: \.self) { handicap in
                        Text("\(handicap)").tag(handicap)
                    }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(height: 96)
                .onChange(of: handicapSelection) { _, newValue in
                    roundStore.updatePlayerHandicap(newValue >= 0 ? newValue : nil, for: playerIndex)
                }

                actionButton(title: "Done") {
                    dismiss()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.black)
        .navigationTitle("HCP")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            handicapSelection = roundStore.playerHandicap(for: playerIndex) ?? -1
        }
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerCountSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roundStore: RoundStore

    let onSelect: (Int) -> Void

    var body: some View {
        List([1, 2, 3, 4], id: \.self) { playerCount in
            Button {
                onSelect(playerCount)
                dismiss()
            } label: {
                HStack {
                    Text(playerCount == 1 ? "1 Player" : "\(playerCount) Players")

                    Spacer(minLength: 8)

                    if roundStore.playerCount == playerCount {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Players")
    }
}

private struct CourseSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roundStore: RoundStore
    @EnvironmentObject private var locationManager: LocationManager

    let selectedMissingCourse: Bool
    let onSelect: (UUID) -> Void
    let onSelectMissingCourse: () -> Void

    @State private var searchText = ""

    var body: some View {
        List {
            if searchText.isEmpty {
                if nearbyCourses.isEmpty {
                    Text(locationManager.currentLocation == nil ? "Finding nearby courses..." : "No nearby courses")
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    ForEach(nearbyCourses) { nearbyCourse in
                        Button {
                            onSelect(nearbyCourse.course.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(nearbyCourse.course.name)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.75)

                                    Text(formatDistance(nearbyCourse.distanceMeters))
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.58))
                                }

                                Spacer(minLength: 8)

                                if !selectedMissingCourse && roundStore.selectedCourse?.id == nearbyCourse.course.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Button {
                    onSelectMissingCourse()
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Missing Course")
                                .lineLimit(1)

                            Text("Report this GPS location")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        Spacer(minLength: 8)

                        if selectedMissingCourse {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } else {
                if searchResults.isEmpty {
                    Text("No courses found")
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    ForEach(searchResults) { course in
                        Button {
                            onSelect(course.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(course.name)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.75)

                                Spacer(minLength: 8)

                                if roundStore.selectedCourse?.id == course.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Course")
        .searchable(text: $searchText, prompt: "Search all courses")
    }

    private var nearbyCourses: [RoundStore.NearbyCourse] {
        roundStore.nearbyCourses(to: locationManager.currentLocation)
    }

    private var searchResults: [Course] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return roundStore.courses
            .filter { $0.name.lowercased().contains(query) }
            .sorted { $0.name < $1.name }
    }

    private func formatDistance(_ meters: Int) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km", Double(meters) / 1_000)
        }

        return "\(meters) m"
    }
}

private struct HoleSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roundStore: RoundStore

    let onSelect: (Int) -> Void

    var body: some View {
        List(availableHoleNumbers, id: \.self) { holeNumber in
            Button {
                onSelect(holeNumber)
                dismiss()
            } label: {
                HStack {
                    Text("Hole \(holeNumber)")

                    Spacer(minLength: 8)

                    if roundStore.currentRound?.currentHoleNumber == holeNumber {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Hole")
    }

    private var availableHoleNumbers: [Int] {
        roundStore.selectedCourse?.holes.map(\.holeNumber) ?? Array(1...18)
    }
}

#Preview {
    SettingsView()
        .environmentObject({
            let store = RoundStore()
            store.bootstrapIfNeeded()
            return store
        }())
        .environmentObject(LocationManager())
}
