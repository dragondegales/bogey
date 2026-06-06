import SwiftUI
import WatchKit

struct ContentView: View {
    @EnvironmentObject private var roundStore: RoundStore
    @EnvironmentObject private var locationManager: LocationManager

    @State private var isShowingSettings = false
    @State private var crownPageValue = 1.0
    @FocusState private var crownFocused: Bool

    private var currentPageIndex: Int {
        max(0, min(1, Int(round(crownPageValue))))
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 230
            let isTight = geometry.size.height < 200
            let isNarrow = geometry.size.width < 185
            let verticalPadding: CGFloat = isTight ? 5 : 7
            let fixedRailHeight = max(geometry.size.height - (verticalPadding * 2), 120)

            ZStack {
                Color.black.ignoresSafeArea()

                HStack(spacing: contentSpacing(isTight: isTight, isNarrow: isNarrow)) {
                    currentHoleRail(isCompact: isCompact, isTight: isTight, isNarrow: isNarrow)
                        .frame(
                            width: railSlotWidth(isCompact: isCompact, isTight: isTight, isNarrow: isNarrow),
                            height: fixedRailHeight,
                            alignment: .center
                        )

                    VStack(spacing: isTight ? 6 : 10) {
                        switch currentPageIndex {
                        case 0:
                            infoPage(isCompact: isCompact, isTight: isTight)
                        default:
                            boardPage(isCompact: isCompact, isTight: isTight, isNarrow: isNarrow)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, isNarrow ? 7 : (isTight ? 6 : 8))
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(pageAndHoleNavigationGesture)
                .focusable(true)
                .focused($crownFocused)
                .digitalCrownRotation(
                    $crownPageValue,
                    from: 0,
                    through: 1,
                    by: 1,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )

                pageSwitchIndicator(isTight: isTight, isNarrow: isNarrow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environmentObject(roundStore)
                .environmentObject(locationManager)
        }
        .onAppear {
            crownFocused = true
        }
        .preferredColorScheme(.dark)
    }

    private func infoPage(isCompact: Bool, isTight: Bool) -> some View {
        Text(distanceText)
            .font(.system(size: isTight ? 42 : (isCompact ? 46 : 58), weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.45)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func railSlotWidth(isCompact: Bool, isTight: Bool, isNarrow: Bool) -> CGFloat {
        railWidth(isCompact: isCompact, isTight: isTight, isNarrow: isNarrow) + 4
    }

    private func railWidth(isCompact: Bool, isTight: Bool, isNarrow: Bool) -> CGFloat {
        isNarrow ? 26 : (isTight ? 28 : (isCompact ? 30 : 32))
    }

    private func contentSpacing(isTight: Bool, isNarrow: Bool) -> CGFloat {
        isNarrow ? 3 : (isTight ? 4 : 5)
    }

    private func pageSwitchIndicator(isTight: Bool, isNarrow: Bool) -> some View {
        Button {
            togglePage()
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: isNarrow ? 11 : (isTight ? 12 : 13), weight: .bold))
                .foregroundStyle(Color(red: 0.68, green: 0.92, blue: 0.45).opacity(0.88))
                .frame(width: 34, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch screen")
    }

    private func boardPage(isCompact: Bool, isTight: Bool, isNarrow: Bool) -> some View {
        GeometryReader { geometry in
            let headerHeight: CGFloat = isNarrow ? 19 : (isTight ? 21 : 23)
            let playerCount = max(roundStore.playerCount, 1)
            let rowSpacing: CGFloat = isTight ? 1 : (isCompact ? 2 : 4)
            let availableRowsHeight = max(geometry.size.height - headerHeight - (rowSpacing * CGFloat(playerCount - 1)), 40)
            let rowHeight = availableRowsHeight / CGFloat(playerCount)

            VStack(alignment: .leading, spacing: rowSpacing) {
                boardHeaderRow(isTight: isTight, isNarrow: isNarrow)
                    .frame(height: headerHeight, alignment: .bottom)

                ForEach(Array(0..<roundStore.playerCount), id: \.self) { playerIndex in
                    combinedBoardRow(for: playerIndex, rowHeight: rowHeight, isCompact: isCompact, isTight: isTight, isNarrow: isNarrow)
                        .frame(height: rowHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func currentHoleRail(isCompact: Bool, isTight: Bool, isNarrow: Bool) -> some View {
        let holeNumber = roundStore.currentRound?.currentHoleNumber ?? 1
        let width = railWidth(isCompact: isCompact, isTight: isTight, isNarrow: isNarrow)
        let circleSize: CGFloat = isNarrow ? 23 : (isTight ? 25 : (isCompact ? 27 : 30))
        let parNumberText = roundStore.currentHole.map { "\($0.par)" } ?? "--"
        let hcpNumberText = roundStore.currentHole?.strokeIndex.map { "\($0)" }

        return VStack(spacing: isNarrow ? 3 : 4) {
            Spacer(minLength: isNarrow ? 14 : (isTight ? 16 : 18))

            VStack(spacing: -1) {
                Text("Hole")
                    .font(.system(size: isNarrow ? 6 : 7, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black.opacity(0.72))

                Text("\(holeNumber)")
                    .font(.system(size: isNarrow ? 13 : (isTight ? 14 : (isCompact ? 15 : 16)), weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
            }
            .frame(width: circleSize + 2, height: circleSize + 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 0.68, green: 0.92, blue: 0.45))
                    .shadow(color: Color(red: 0.68, green: 0.92, blue: 0.45).opacity(0.22), radius: 7, x: 0, y: 0)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.black.opacity(0.45), lineWidth: 2)
            )

            VStack(spacing: 0) {
                Text("Par")
                    .font(.system(size: isNarrow ? 7 : 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))

                Text(parNumberText)
                    .font(.system(size: isNarrow ? 13 : (isTight ? 14 : 15), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width + 6)

            if let hcpNumberText {
                VStack(spacing: 0) {
                    Text("HCP")
                        .font(.system(size: isNarrow ? 7 : 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))

                    Text(hcpNumberText)
                        .font(.system(size: isNarrow ? 13 : (isTight ? 14 : 15), weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.76))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: width + 6)
            }

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: isNarrow ? 16 : (isTight ? 17 : 18), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: width, height: isNarrow ? 24 : 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, isNarrow ? 1 : 2)

            Spacer(minLength: 0)
        }
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                    .fill(.white.opacity(0.025))
            )
            .contentShape(RoundedRectangle(cornerRadius: width / 2, style: .continuous))
            .onTapGesture {
                goToPreviousHole()
            }
            .accessibilityLabel("Hole \(holeNumber)")
    }

    private func boardHeaderRow(isTight: Bool, isNarrow: Bool) -> some View {
        let headerSize: CGFloat = isNarrow ? 10 : (isTight ? 11 : 12)

        return HStack(spacing: isNarrow ? 3 : 4) {
            Color.clear
                .frame(width: playerColumnWidth(isTight: isTight, isNarrow: isNarrow))

            Color.clear
                .frame(width: shotsColumnWidth(isTight: isTight, isNarrow: isNarrow))

            Spacer(minLength: 0)

            Button {
                roundStore.cycleScoringMode()
                playHaptic(.click)
            } label: {
                Text(roundStore.scoringMode.shortTitle)
                    .frame(width: scoringColumnWidth(isTight: isTight, isNarrow: isNarrow), height: isNarrow ? 18 : 20)
                    .contentShape(Rectangle())
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.07))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color(red: 0.68, green: 0.92, blue: 0.45).opacity(0.55), lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: headerSize, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(0.72))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .allowsTightening(true)
        .padding(.bottom, isNarrow ? 1 : (isTight ? 2 : 3))
    }

    private func combinedBoardRow(for playerIndex: Int, rowHeight: CGFloat, isCompact: Bool, isTight: Bool, isNarrow: Bool) -> some View {
        let sizeBoost = CGFloat(max(0, 4 - roundStore.playerCount))
        let markerSize: CGFloat = min((isNarrow ? 11 : (isTight ? 12 : (isCompact ? 13 : 14))) + (sizeBoost * 2), 20)
        let matchSize: CGFloat = min((isNarrow ? 13 : (isTight ? 14 : (isCompact ? 16 : 18))) + (sizeBoost * 3), 26)
        let shotSize: CGFloat = min((isNarrow ? 16 : (isTight ? 18 : (isCompact ? 20 : 22))) + (sizeBoost * 5), 34)
        let status = boardStatus(for: playerIndex)

        return VStack(spacing: 0) {
            HStack(spacing: isNarrow ? 3 : (isTight ? 4 : 5)) {
                playerMarker(for: playerIndex, size: markerSize)
                    .frame(width: playerColumnWidth(isTight: isTight, isNarrow: isNarrow), alignment: .leading)

                scoreCell(for: playerIndex, fontSize: shotSize, rowHeight: rowHeight, isTight: isTight, isNarrow: isNarrow)

                Spacer(minLength: 0)

                scoringModeCell(for: status, fontSize: matchSize, width: scoringColumnWidth(isTight: isTight, isNarrow: isNarrow))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        goToNextHole()
                    }
            }
            .padding(.horizontal, 0)
            .padding(.vertical, isNarrow ? 0 : (isTight ? 1 : (isCompact ? 2 : 3)))
            .frame(maxHeight: .infinity)

            if playerIndex < roundStore.playerCount - 1 {
                Rectangle()
                    .fill(.white.opacity(isTight ? 0.08 : 0.12))
                    .frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func playerColumnWidth(isTight: Bool, isNarrow: Bool) -> CGFloat {
        isNarrow ? 28 : (isTight ? 31 : 34)
    }

    private func scoringColumnWidth(isTight: Bool, isNarrow: Bool) -> CGFloat {
        isNarrow ? 36 : (isTight ? 39 : 43)
    }

    private func shotsColumnWidth(isTight: Bool, isNarrow: Bool) -> CGFloat {
        isNarrow ? 28 : (isTight ? 31 : 34)
    }

    private func scoringModeCell(for status: MatchStatus?, fontSize: CGFloat, width: CGFloat) -> some View {
        Text(matchStatusDisplayText(for: status))
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(matchStatusColor(for: status))
            .frame(width: width, height: 27, alignment: .trailing)
            .minimumScaleFactor(0.7)
    }

    private func scoreCell(for playerIndex: Int, fontSize: CGFloat, rowHeight: CGFloat, isTight: Bool, isNarrow: Bool) -> some View {
        let baseCircleSize: CGFloat = isNarrow ? 24 : (isTight ? 25 : 27)
        let circleSize = min(max(baseCircleSize, rowHeight * 0.48), isNarrow ? 34 : 42)

        return Text("\(roundStore.score(for: playerIndex))")
            .font(.system(size: min(fontSize, circleSize - 8), weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .contentTransition(.numericText())
            .frame(width: circleSize, height: circleSize)
            .background(
                Circle()
                    .fill(.white.opacity(0.92))
            )
            .overlay(
                Circle()
                    .stroke(Color(red: 0.68, green: 0.92, blue: 0.45).opacity(0.75), lineWidth: 1)
            )
            .contentShape(Circle())
            .onTapGesture {
                incrementScore(for: playerIndex)
            }
            .onLongPressGesture(minimumDuration: 0.55) {
                decrementScore(for: playerIndex)
            }
            .frame(width: max(shotsColumnWidth(isTight: isTight, isNarrow: isNarrow), circleSize), height: max(isNarrow ? 27 : (isTight ? 29 : 31), circleSize), alignment: .center)
    }

    private func incrementScore(for playerIndex: Int) {
        if playerIndex == 0 {
            roundStore.incrementMyScore(using: locationManager.bestAvailableLocation())
        } else {
            roundStore.incrementBuddyScore(at: playerIndex)
        }
        playHaptic(.click)
    }

    private func decrementScore(for playerIndex: Int) {
        if playerIndex == 0 {
            roundStore.decrementMyScore()
        } else {
            roundStore.decrementBuddyScore(at: playerIndex)
        }
        playHaptic(.directionDown)
    }

    private func playerMarker(for playerIndex: Int, size: CGFloat) -> some View {
        Text(String(roundStore.playerName(for: playerIndex).uppercased().prefix(3)))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(tileStrokeColor(for: playerIndex))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var distanceText: String {
        let unit = roundStore.distanceUnit
        guard let distanceMeters = locationManager.currentDistanceMeters(to: roundStore.currentHole) else {
            return "-- \(unit.symbol)"
        }
        return "\(unit.displayDistance(fromMeters: distanceMeters)) \(unit.symbol)"
    }

    private var pageAndHoleNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                let absHorizontalDistance = abs(horizontalDistance)
                let absVerticalDistance = abs(verticalDistance)

                if absVerticalDistance > absHorizontalDistance,
                   absVerticalDistance >= 22 {
                    let targetPage = currentPageIndex == 0 ? 1.0 : 0.0
                    guard crownPageValue != targetPage else {
                        return
                    }

                    crownPageValue = targetPage
                    playHaptic(verticalDistance < 0 ? .directionUp : .directionDown)
                    return
                }

                guard absHorizontalDistance >= 22 else {
                    return
                }

                if horizontalDistance < 0 {
                    goToNextHole()
                } else {
                    goToPreviousHole()
                }
            }
    }

    private func togglePage() {
        crownPageValue = currentPageIndex == 0 ? 1.0 : 0.0
        playHaptic(.click)
    }

    private func goToNextHole() {
        roundStore.goToNextHole()
        playHaptic(.directionUp)
    }

    private func goToPreviousHole() {
        roundStore.goToPreviousHole()
        playHaptic(.directionDown)
    }

    private func tileStrokeColor(for playerIndex: Int) -> Color {
        if roundStore.teamSetup == .teams && roundStore.scoringMode == .matchPlay {
            return playerIndex < 2 ? Color(red: 0.25, green: 0.55, blue: 0.95) : Color(red: 0.95, green: 0.78, blue: 0.22)
        }

        switch playerIndex {
        case 0:
            return Color(red: 0.25, green: 0.55, blue: 0.95)
        case 1:
            return Color(red: 0.95, green: 0.78, blue: 0.22)
        case 2:
            return Color(red: 0.40, green: 0.68, blue: 1.0)
        case 3:
            return Color(red: 1.0, green: 0.85, blue: 0.40)
        default:
            return .white.opacity(0.2)
        }
    }

    private func matchStatusDisplayText(for status: MatchStatus?) -> String {
        guard let status else { return "—" }

        switch status.colorName {
        case "up":
            return status.text
        case "down":
            return status.text
        case "neutral":
            return status.text == "0" ? "AS" : status.text
        default:
            return status.text
        }
    }

    private func matchStatusColor(for status: MatchStatus?) -> Color {
        guard let status else { return .white.opacity(0.6) }

        switch status.colorName {
        case "up":
            return Color(red: 0.50, green: 0.92, blue: 0.32)
        case "down":
            return Color(red: 1.0, green: 0.35, blue: 0.32)
        case "score":
            return .white.opacity(0.9)
        default:
            return .white.opacity(0.9)
        }
    }

    private func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    private func boardStatus(for playerIndex: Int) -> MatchStatus? {
        roundStore.boardStatus(for: playerIndex)
    }
}

#Preview {
    ContentView()
        .environmentObject({
            let store = RoundStore()
            store.bootstrapIfNeeded()
            return store
        }())
        .environmentObject(LocationManager())
}
