import SwiftUI

// MARK: - Night harbor palette and type scale

enum CRTheme {
    static let cream = Color(red: 0.035, green: 0.065, blue: 0.105)
    static let creamEdge = Color(red: 0.065, green: 0.115, blue: 0.170)
    static let ink = Color(red: 0.930, green: 0.967, blue: 1.000)
    static let coral = Color(red: 1.000, green: 0.380, blue: 0.190)
    static let gold = Color(red: 1.000, green: 0.770, blue: 0.360)
    static let mint = Color(red: 0.390, green: 0.910, blue: 0.740)
    static let sea = Color(red: 0.360, green: 0.820, blue: 1.000)
    static func inkSoft(_ opacity: Double = 0.66) -> Color { ink.opacity(opacity) }
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .default).italic() }
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .default) }
    static func label(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .default) }
}

enum CRFormat {
    private static let grouped: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func count(_ value: Int) -> String {
        grouped.string(from: NSNumber(value: max(0, value))) ?? "\(max(0, value))"
    }

    static func meters(_ value: Double) -> String {
        count(Int(value.isFinite ? max(0, value) : 0)) + "m"
    }

    static func seconds(_ value: Double) -> String {
        "\(Int(max(0, value.isFinite ? value : 0).rounded(.up)))s"
    }
}

/// Springy press feedback with a guaranteed 44pt touch area.
struct CRPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

// MARK: - Root

struct GameRootView: View {
    @ObservedObject var controller: GameController
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    private var reduceMotion: Bool { controller.profile.reducedMotion || systemReducedMotion }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > 760

            ZStack {
                GameSurface(controller: controller, controlMode: controller.run.phase == .menu ? controller.selectedMode : controller.run.mode)
                    .ignoresSafeArea()

                legibilityWash
                    .allowsHitTesting(false)
                    .ignoresSafeArea()

                phaseLayer(wide: wide)
                    .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
                               value: controller.run.phase)

                CRToastLayer(message: controller.toast)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(CRTheme.cream.ignoresSafeArea())
        .tint(CRTheme.coral)
        .preferredColorScheme(.dark)
        .transaction { transaction in
            if reduceMotion { transaction.disablesAnimations = true }
        }
        .sheet(item: $controller.panel) { panel in
            CRPanelSheet(panel: panel, controller: controller)
        }
    }

    /// Darken only the screen edges; leave the rendered harbor's midtones intact.
    private var legibilityWash: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(controller.run.phase == .menu ? 0.38 : 0.23), location: 0),
            .init(color: .clear, location: 0.28),
            .init(color: .clear, location: 0.56),
            .init(color: .black.opacity(controller.run.phase == .menu ? 0.64 : 0.18), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder
    private func phaseLayer(wide: Bool) -> some View {
        switch controller.run.phase {
        case .menu:
            CRMenuLayer(controller: controller, wide: wide)
                .transition(.opacity.combined(with: .scale(scale: 1.02, anchor: .center)))
        case .running:
            CRHUDLayer(controller: controller, live: true)
                .transition(.opacity)
        case .paused:
            ZStack {
                CRHUDLayer(controller: controller, live: false)
                if !controller.profile.tutorialCompleted {
                    CROverlayCard(kicker: controller.run.mode.title.uppercased(), title: "MAKE YOUR\nFIRST RUN") {
                        Text(controller.run.mode.instructions)
                            .font(CRTheme.label(15, .medium)).foregroundColor(CRTheme.inkSoft(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(controller.run.mode == .jetSki ? "Hit the cyan gates. Orange buoys are solid obstacles." : "Double-tap or press B for a shield board. Arrows or WASD also work.")
                            .font(CRTheme.label(12, .medium)).foregroundColor(CRTheme.sea)
                        CRActionButton(title: "Ready. Let's go.", symbol: "play.fill") {
                            controller.dismissTutorial()
                            controller.resume()
                        }
                    }
                } else {
                    CRPausedOverlay(controller: controller)
                }
            }
        case .crashed:
            ZStack {
                if controller.isReplaying {
                    CRCrashReplayOverlay(controller: controller)
                } else {
                    CRHUDLayer(controller: controller, live: false)
                    CRCrashOverlay(controller: controller)
                }
            }
        case .finished:
            CRFinishOverlay(controller: controller)
        }
    }
}

// MARK: - Menu

private struct CRMenuLayer: View {
    @ObservedObject var controller: GameController
    let wide: Bool

    var body: some View {
        if wide {
            wideLayout
        } else {
            portraitLayout
        }
    }

    private var launchTitle: String {
        if controller.selectedMode == .odyssey {
            switch controller.selectedExpeditionStyle {
            case .campaign: return "BEGIN ODYSSEY"
            case .endless: return "ENTER ENDLESS ODYSSEY"
            case .practice: return "PRACTICE THIS WORLD"
            }
        }
        return controller.selectedMode == .jetSki ? "RIDE THE HARBOR" : "HIT THE COAST"
    }

    private var portraitLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                CRMenuMasthead(controller: controller)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 10) {
                    CRBalanceChip(profile: controller.profile)
                    CRDailyRewardChip(controller: controller)
                }
            }
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 11) {
                CRModeSelection(controller: controller)
                CRPrimaryCTA(title: launchTitle) { controller.start() }
                CRDailyCourseRow(controller: controller)
                CRMenuTabRow(controller: controller, vertical: false)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    /// Desktop composes off the sides so the runner in the middle is never covered.
    private var wideLayout: some View {
        ZStack {
            corner(.topLeading) {
                CRMenuMasthead(controller: controller)
                    .frame(maxWidth: 400, alignment: .leading)
            }
            corner(.topTrailing) {
                VStack(alignment: .trailing, spacing: 12) {
                    CRBalanceChip(profile: controller.profile)
                    CRDailyRewardChip(controller: controller)
                }
            }
            corner(.bottomLeading) {
                VStack(alignment: .leading, spacing: 18) {
                    CRModeSelection(controller: controller)
                    CRPrimaryCTA(title: launchTitle) { controller.start() }
                    CRDailyCourseRow(controller: controller)
                }
                .frame(maxWidth: 380, alignment: .leading)
            }
            corner(.bottomTrailing) {
                CRMenuTabRow(controller: controller, vertical: true)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
    }

    private func corner<Content: View>(_ alignment: Alignment,
                                       @ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

private struct CRMenuMasthead: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(controller.selectedMode == .odyssey ? "SIX WORLDS / ONE ODYSSEY" : "AFTER HOURS / HARBOR DISTRICT")
                .font(CRTheme.label(10, .bold))
                .kerning(1.8)
                .foregroundColor(CRTheme.coral)
                .padding(.bottom, 8)

            CRWordmark()

            HStack(spacing: 6) {
                Image(systemName: "trophy.fill").foregroundColor(CRTheme.gold)
                Text(CRFormat.count(controller.profile.modeBestScore(mode: controller.selectedMode, expert: controller.selectedExpert, expeditionStyle: controller.selectedExpeditionStyle)))
                    .monospacedDigit()
                Text(controller.selectedMode == .odyssey ? (controller.selectedExpeditionStyle == .endless ? "ENDLESS ODYSSEY BEST" : "CAMPAIGN BEST") : "PERSONAL BEST").foregroundColor(CRTheme.inkSoft())
            }.font(CRTheme.label(10, .bold)).padding(.top, 12)
        }
        .shadow(color: CRTheme.cream.opacity(0.85), radius: 10, x: 0, y: 2)
        .accessibilityElement(children: .combine)
    }
}

private struct CRWordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: -8) {
            Text("COASTLINE")
                .font(CRTheme.display(42))
                .kerning(-1.5)
            Text("RUSH")
                .font(CRTheme.display(42))
                .kerning(-1.0)
                .foregroundColor(CRTheme.coral)
        }
        .foregroundColor(CRTheme.ink)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .accessibilityLabel("Coastline Rush")
    }
}

private struct CRBestRunLine: View {
    let profile: PlayerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(profile.bestScore > 0 ? "BEST RUN" : "NO RUNS YET")
                .font(CRTheme.label(10, .bold))
                .kerning(1.8)
                .foregroundColor(CRTheme.inkSoft(0.55))

            if profile.bestScore > 0 {
                Text(CRFormat.count(profile.bestScore))
                    .font(CRTheme.title(26))
                    .foregroundColor(CRTheme.ink)
                Text("\(CRFormat.count(profile.totalRuns)) \(profile.totalRuns == 1 ? "run" : "runs") · \(CRFormat.meters(profile.totalDistance)) travelled")
                    .font(CRTheme.label(12, .medium))
                    .foregroundColor(CRTheme.inkSoft(0.62))
            } else {
                Text("Your first score lands here.")
                    .font(CRTheme.label(13, .medium))
                    .foregroundColor(CRTheme.inkSoft(0.62))
            }
        }
    }
}

private struct CRModeSelection: View {
    @ObservedObject var controller: GameController
    private var odyssey: Bool { controller.selectedMode == .odyssey }
    private func shortTitle(_ mode: RunMode) -> String {
        switch mode { case .endless: return "ENDLESS"; case .harborSprint: return "SPRINT"; case .jetSki: return "JET SKI"; case .odyssey: return "ODYSSEY" }
    }
    private func icon(_ mode: RunMode) -> String {
        switch mode { case .endless: return "figure.run"; case .harborSprint: return "timer"; case .jetSki: return "water.waves"; case .odyssey: return "sparkles" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { controller.selectMode(.odyssey) } label: {
                HStack(spacing: 11) {
                    Image(systemName: "sparkles").font(.system(size: 24, weight: .semibold))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PORTAL ODYSSEY").font(CRTheme.label(14, .heavy)).kerning(1.1)
                        Text("Run through six worlds. Recover their relics.").font(CRTheme.label(11, .medium))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: odyssey ? "checkmark.circle.fill" : "arrow.up.right")
                }.foregroundColor(odyssey ? CRTheme.cream : CRTheme.ink)
                    .padding(.horizontal, 14).frame(minHeight: 62)
                    .background(RoundedRectangle(cornerRadius: 10).fill(odyssey ? CRTheme.sea : CRTheme.cream.opacity(0.92)))
            }.buttonStyle(CRPressStyle()).accessibilityLabel("Portal Odyssey")
                .accessibilityAddTraits(odyssey ? .isSelected : [])
            if odyssey {
                Picker("Expedition style", selection: Binding(get: { controller.selectedExpeditionStyle }, set: controller.setExpeditionStyle)) {
                    ForEach([ExpeditionStyle.campaign, .endless], id: \.rawValue) { style in
                        Text(style == .campaign ? "Campaign" : style == .endless ? "Endless" : "Practice").tag(style)
                    }
                }.pickerStyle(.segmented).frame(minHeight: 36)
                Text(controller.selectedExpeditionStyle.detail)
                    .font(CRTheme.label(10, .medium)).foregroundColor(CRTheme.inkSoft(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 5) {
                ForEach([RunMode.endless, .harborSprint, .jetSki], id: \.rawValue) { mode in
                    Button { controller.selectMode(mode) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: icon(mode))
                            Text(shortTitle(mode)).font(CRTheme.label(9, .bold)).kerning(0.5)
                        }.foregroundColor(controller.selectedMode == mode ? CRTheme.cream : CRTheme.ink)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 8).fill(controller.selectedMode == mode ? CRTheme.ink : CRTheme.cream.opacity(0.9)))
                    }.buttonStyle(CRPressStyle()).accessibilityLabel(mode.title)
                        .accessibilityAddTraits(controller.selectedMode == mode ? .isSelected : [])
                }
            }
            HStack(alignment: .center, spacing: 10) {
                if odyssey {
                    Button { controller.showPanel(.journey) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "map.fill").foregroundColor(CRTheme.sea)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(controller.selectedWorld + 1) / 6 · \(controller.selectedStage.title)").font(CRTheme.label(12, .bold))
                                Text("Route & relics · best \(CRFormat.meters(controller.profile.worldBestDistance(controller.selectedStage)))")
                                    .font(CRTheme.label(10, .medium)).foregroundColor(CRTheme.inkSoft(0.75))
                            }
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        }.foregroundColor(CRTheme.ink).frame(minHeight: 44)
                    }.buttonStyle(CRPressStyle()).accessibilityLabel("Choose world and view relic collection")
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(controller.selectedMode == .endless ? "The coast never ends." : controller.selectedMode == .harborSprint ? "Beat the checkpoint clock." : "Master the harbor slalom.").font(CRTheme.label(12, .semibold))
                        Text(controller.selectedMode == .endless ? "Chain close calls. Chase your best." : controller.selectedMode == .harborSprint ? "1,500m. Checkpoints gain time." : "1,800m. Gates, tricks and boost.")
                            .font(CRTheme.label(10, .medium)).foregroundColor(CRTheme.inkSoft(0.72))
                    }.foregroundColor(CRTheme.ink)
                }
                Spacer(minLength: 0)
                Button { controller.toggleExpert() } label: {
                    VStack(spacing: 3) {
                        Text(controller.selectedExpert ? "EXPERT" : "STANDARD").font(CRTheme.label(9, .heavy)).kerning(0.6)
                        HStack(spacing: 3) { ForEach(0..<3) { n in Capsule().fill(n == 0 || controller.selectedExpert ? CRTheme.coral : CRTheme.ink.opacity(0.22)).frame(width: 10, height: 3) } }
                    }.foregroundColor(CRTheme.ink).frame(width: 82, height: 44)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CRTheme.cream.opacity(0.88)))
                }.buttonStyle(CRPressStyle()).accessibilityLabel(controller.selectedExpert ? "Expert difficulty. Tap for standard." : "Standard difficulty. Tap for expert.")
            }
        }
    }
}

private struct CRPrimaryCTA: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title)
                    .font(CRTheme.display(27))
                    .kerning(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .black, design: .rounded))
            }
            .foregroundColor(CRTheme.cream)
            .padding(.horizontal, 26)
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CRTheme.coral)
                    .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 6)
            )
        }
        .buttonStyle(CRPressStyle(scale: 0.975))
        .accessibilityLabel(title)
    }
}

private struct CRDailyCourseRow: View {
    @ObservedObject var controller: GameController

    private var isToday: Bool {
        controller.profile.dailyOdysseyScore() > 0
    }

    var body: some View {
        Button { controller.start(daily: true) } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(CRTheme.sea)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Daily Odyssey")
                        .font(CRTheme.label(14, .bold))
                        .foregroundColor(CRTheme.ink)
                    Text(isToday
                         ? "Six worlds · today’s best \(CRFormat.count(controller.profile.dailyOdysseyScore()))"
                         : "One fixed expedition today · race your ghost")
                        .font(CRTheme.label(11, .medium))
                        .foregroundColor(CRTheme.inkSoft(0.6))
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(CRTheme.inkSoft(0.45))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CRTheme.cream.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(CRTheme.ink.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(CRPressStyle())
        .accessibilityHint("Starts today’s six-world expedition on standard difficulty from the harbor")
    }
}

private struct CRBalanceChip: View {
    let profile: PlayerProfile

    var body: some View {
        HStack(spacing: 14) {
            item("circle.fill", CRTheme.gold, CRFormat.count(profile.coins), "coins")
            Rectangle()
                .fill(CRTheme.ink.opacity(0.12))
                .frame(width: 1, height: 16)
            item("key.fill", CRTheme.sea, CRFormat.count(profile.keys), "keys")
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 44)
        .background(
            Capsule(style: .continuous)
                .fill(CRTheme.cream.opacity(0.94))
                .shadow(color: CRTheme.ink.opacity(0.12), radius: 10, x: 0, y: 4)
        )
    }

    private func item(_ symbol: String, _ tint: Color, _ value: String, _ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(tint)
            Text(value)
                .font(CRTheme.label(15, .bold))
                .foregroundColor(CRTheme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(name)")
    }
}

private struct CRDailyRewardChip: View {
    @ObservedObject var controller: GameController

    private var canClaim: Bool { controller.profile.canClaimDaily() }

    var body: some View {
        Button { controller.claimDaily() } label: {
            HStack(spacing: 8) {
                Image(systemName: canClaim ? "gift.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(canClaim ? "Daily gift" : streakText)
                    .font(CRTheme.label(12, .bold))
            }
            .foregroundColor(canClaim ? CRTheme.cream : CRTheme.inkSoft(0.62))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(canClaim ? CRTheme.coral : CRTheme.cream.opacity(0.9))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(CRTheme.ink.opacity(canClaim ? 0 : 0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(CRPressStyle())
        .disabled(!canClaim)
        .accessibilityLabel(canClaim ? "Claim daily gift" : "Daily gift already collected")
    }

    private var streakText: String {
        let streak = controller.profile.dailyStreak
        return streak > 1 ? "Day \(CRFormat.count(streak))" : "Collected"
    }
}

private struct CRMenuTabRow: View {
    @ObservedObject var controller: GameController
    let vertical: Bool

    private static let items: [(GamePanel, String, String)] = [
        (.missions, "list.bullet.rectangle", "Missions"),
        (.locker, "tshirt.fill", "Locker"),
        (.upgrades, "arrow.up.circle.fill", "Upgrades"),
        (.settings, "gearshape.fill", "Settings")
    ]

    var body: some View {
        if vertical {
            VStack(spacing: 14) { buttons }
        } else {
            HStack(spacing: 10) { buttons }
        }
    }

    private var buttons: some View {
        ForEach(Self.items, id: \.0) { panel, symbol, title in
            CRTabButton(symbol: symbol, title: title, wide: !vertical) {
                controller.showPanel(panel)
            }
        }
    }
}

private struct CRTabButton: View {
    let symbol: String
    let title: String
    let wide: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(CRTheme.label(10, .bold))
                    .kerning(0.3)
            }
            .foregroundColor(CRTheme.ink)
            .frame(minWidth: 64, minHeight: 60)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CRTheme.cream.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(CRTheme.ink.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(CRPressStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Running HUD

private struct CRHUDLayer: View {
    @ObservedObject var controller: GameController
    /// False while an overlay owns the screen: the HUD stays visible but inert.
    let live: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                CRHUDTopBar(controller: controller)
                CRChallengeHUD(controller: controller).padding(.top, controller.run.mode == .odyssey ? 6 : 12)
                Spacer(minLength: 0)
                CRPowerChipRow(active: controller.run.activePowerUps)
                    .padding(.bottom, 10)
            }
            .allowsHitTesting(false)

            if live {
                controlsLayer
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private var controlsLayer: some View {
        ZStack {
            CRPauseButton { controller.pause() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if controller.run.mode == .odyssey && controller.run.portalReady && !controller.run.isPortalTransitioning {
                VStack(spacing: 7) {
                    Text("PORTAL OPEN").font(CRTheme.label(10, .heavy)).kerning(2).foregroundColor(CRTheme.sea)
                    Button { controller.perform(.jump) } label: {
                        Label("JUMP INTO PORTAL", systemImage: "arrow.up.forward.circle.fill")
                            .font(CRTheme.label(15, .heavy)).foregroundColor(CRTheme.cream)
                            .padding(.horizontal, 20).frame(height: 52)
                            .background(Capsule().fill(CRTheme.sea))
                    }.buttonStyle(CRPressStyle()).accessibilityHint("Jump through the portal to the next world")
                }.padding(.bottom, 108)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            if controller.run.isPortalTransitioning {
                VStack(spacing: 8) {
                    Text("CROSSING THE RIFT").font(CRTheme.title(22)).kerning(2)
                    Text(controller.run.stageIndex == WorldStage.allCases.count - 1 && controller.run.expeditionStyle != .endless ? "The expedition comes home" : "Keep your flow. A new world awaits.").font(CRTheme.label(13, .medium))
                }.foregroundColor(CRTheme.ink).shadow(color: .black, radius: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).allowsHitTesting(false)
            }
            if controller.run.mode == .odyssey && controller.run.routeChoiceAvailable {
                CRRouteChoice(controller: controller)
                    .frame(maxWidth: 460)
                    .padding(.bottom, 112)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            CRBoardButton(controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            if controller.run.mode == .odyssey {
                CRArtifactButton(controller: controller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            if controller.run.elapsed < 8 && controller.profile.tutorialCompleted {
                VStack(alignment: .leading, spacing: 5) {
                    Text(controller.run.mode == .jetSki ? "CARVE. BRAKE. BOOST." : "FIND YOUR FLOW.")
                        .font(CRTheme.label(10, .heavy)).kerning(1.4).foregroundColor(CRTheme.sea)
                    #if os(macOS)
                    Text(controller.run.mode == .jetSki ? "← → steer  ·  ↓ brake\n↑ trick after ramp  ·  B boost" : "← → steer  ·  ↑ jump  ·  ↓ roll\nB board  ·  Esc pause")
                    #else
                    Text(controller.run.mode == .jetSki ? "Swipe to steer  ·  Down to brake\nUp after ramp to trick  ·  Double-tap boost" : "Swipe to steer  ·  Up to jump  ·  Down to roll\nDouble-tap for a shield board")
                    #endif
                }.font(CRTheme.label(11, .medium)).foregroundColor(CRTheme.inkSoft(0.8))
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(CRTheme.cream.opacity(0.8)))
                    .padding(.bottom, 96)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false).transition(.opacity)
            }

            if !controller.profile.tutorialCompleted {
                CRTutorialHint(controller: controller)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 92)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

private struct CRHUDTopBar: View {
    @ObservedObject var controller: GameController

    private var runHeading: String {
        if controller.isDailyRun { return "DAILY ODYSSEY" }
        guard controller.run.mode == .odyssey else {
            return controller.run.mode.title.uppercased() + (controller.run.expert ? " / EXPERT" : "")
        }
        let prefix = controller.run.isPractice ? "PRACTICE" : controller.run.expeditionStyle == .endless ? "CYCLE \(controller.run.expeditionCycle + 1)" : "WORLD \(controller.run.stageIndex + 1) / 6"
        return prefix + " · " + controller.run.worldStage.title.uppercased()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(runHeading)
                    .font(CRTheme.label(9, .bold)).kerning(1.2).foregroundColor(CRTheme.coral)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if controller.run.mode == .odyssey {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        score
                        CRHUDStat(symbol: "circle.fill", tint: CRTheme.gold,
                                  value: CRFormat.count(controller.run.coins), name: "coins collected")
                        if controller.run.multiplier > 1 {
                            Text("×\(controller.run.multiplier)").font(CRTheme.label(11, .bold)).foregroundColor(CRTheme.coral)
                                .accessibilityLabel("Score multiplier \(controller.run.multiplier)")
                        }
                    }
                } else {
                    score
                    HStack(spacing: 10) {
                        CRHUDStat(symbol: "arrow.right", tint: CRTheme.sea,
                                  value: CRFormat.meters(controller.run.distance), name: "distance")
                        CRHUDStat(symbol: "circle.fill", tint: CRTheme.gold,
                                  value: CRFormat.count(controller.run.coins), name: "coins collected")
                        if controller.run.multiplier > 1 {
                            CRHUDStat(symbol: "multiply.circle.fill", tint: CRTheme.coral,
                                      value: "\(controller.run.multiplier)", name: "score multiplier")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .shadow(color: CRTheme.cream.opacity(0.9), radius: 8, x: 0, y: 1)
        .padding(.trailing, 60)
    }

    private var score: some View {
        Text(CRFormat.count(controller.run.score))
            .font(CRTheme.title(controller.run.mode == .odyssey ? 30 : 34)).foregroundColor(CRTheme.ink)
            .lineLimit(1).minimumScaleFactor(0.7)
            .accessibilityLabel("Score \(CRFormat.count(controller.run.score))")
    }
}

private struct CRHUDStat: View {
    let symbol: String
    let tint: Color
    let value: String
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(tint)
            Text(value)
                .font(CRTheme.label(14, .bold))
                .foregroundColor(CRTheme.inkSoft(0.8))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(value)")
    }
}

private struct CRPowerChipRow: View {
    let active: [PowerUp: Double]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PowerUp.allCases.filter { active[$0] != nil }, id: \.rawValue) { power in
                CRPowerChip(power: power, remaining: active[power] ?? 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: active.count)
    }
}

private struct CRPowerChip: View {
    let power: PowerUp
    let remaining: Double

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: CRIcon.power(power))
                .font(.system(size: 10, weight: .bold))
            Text(CRFormat.seconds(remaining))
                .font(CRTheme.label(12, .bold))
                .monospacedDigit()
        }
        .foregroundColor(CRTheme.ink)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            Capsule(style: .continuous)
                .fill(CRTheme.cream.opacity(0.92))
                .overlay(Capsule(style: .continuous).strokeBorder(CRTheme.coral.opacity(0.35), lineWidth: 1))
        )
        .accessibilityLabel("\(GameCatalog.name(forPower: power)) \(CRFormat.seconds(remaining)) left")
    }
}

private struct CRPauseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pause.fill")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(CRTheme.ink)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(CRTheme.cream.opacity(0.92))
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
                )
        }
        .buttonStyle(CRPressStyle(scale: 0.9))
        .accessibilityLabel("Pause run")
    }
}

private struct CRChallengeHUD: View {
    @ObservedObject var controller: GameController

    private var imminentCue: String {
        guard let distance = controller.run.encounterDistance,
              distance / max(1, controller.run.speed) <= 2.0 else { return "" }
        return controller.run.encounterText.components(separatedBy: " · ").last ?? ""
    }
    private var cueSymbol: String {
        let cue = imminentCue
        if cue.contains("JUMP") || cue.contains("RAMP") { return "arrow.up" }
        if cue.contains("SLIDE") { return "arrow.down" }
        return "arrow.left.arrow.right"
    }
    private var arrivalEvent: Bool {
        controller.run.eventText.uppercased().hasPrefix(controller.run.worldStage.title.uppercased())
    }
    private var contextLine: String {
        if arrivalEvent && controller.run.eventTime > 0.8 { return "ARRIVED · " + controller.run.worldStage.title.uppercased() }
        if controller.run.finaleActive { return "\(controller.run.finaleTitle) · \(CRFormat.seconds(controller.run.finaleTimeRemaining))" }
        if controller.run.isWaterTraversal { return "TIDAL CHANNEL · BRAKE / TRICK / BOOST" }
        if controller.run.routeIsActive { return controller.run.branchRoute.title(in: controller.run.worldStage).uppercased() }
        if !arrivalEvent && controller.run.eventTime > 0.8 { return controller.run.eventText.uppercased() }
        if let ghost = controller.ghostSample {
            let lead = controller.run.distance - ghost.distance
            return "GHOST · \(Int(abs(lead)))m \(lead >= 0 ? "AHEAD" : "BEHIND")"
        }
        return ""
    }

    var body: some View {
        if controller.run.mode == .odyssey {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Label("\(Int(controller.run.speed * 3.6)) KM/H", systemImage: "speedometer")
                            .font(CRTheme.label(10, .bold)).monospacedDigit().foregroundColor(CRTheme.gold)
                        ProgressView(value: controller.run.stageProgress).tint(CRTheme.sea).frame(width: 86)
                        Text("\(Int(controller.run.stageProgress * 100))%")
                            .font(CRTheme.label(10, .bold)).monospacedDigit().foregroundColor(CRTheme.ink)
                    }
                    .padding(.horizontal, controller.profile.highContrastCues ? 6 : 0)
                    .padding(.vertical, controller.profile.highContrastCues ? 3 : 0)
                    .background(Capsule().fill(controller.profile.highContrastCues ? Color.black.opacity(0.88) : .clear))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Speed \(Int(controller.run.speed * 3.6)) kilometres per hour. \(controller.run.difficultyTier.title). Stage \(CRFormat.meters(controller.run.stageDistance)) of \(CRFormat.meters(controller.run.stageLength)). Total distance \(CRFormat.meters(controller.run.distance)). \(controller.run.artifactsCollected) relics.")
                    if !imminentCue.isEmpty {
                        Label(imminentCue, systemImage: cueSymbol)
                            .font(CRTheme.label(12, .heavy)).foregroundColor(CRTheme.gold)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(controller.profile.highContrastCues ? 0.94 : 0.65)))
                            .accessibilityLabel(controller.run.encounterText)
                    }
                    if !contextLine.isEmpty {
                        Text(contextLine).font(CRTheme.label(9, .bold)).foregroundColor(controller.run.finaleActive ? CRTheme.coral : CRTheme.sea)
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .shadow(color: .black, radius: 4)
                            .accessibilityLabel(contextLine)
                    }
                }.frame(maxWidth: 260, alignment: .leading)
                Spacer(minLength: 0)
                if controller.run.combo > 0 {
                    Text("\(controller.run.combo)×").font(CRTheme.display(21)).foregroundColor(CRTheme.gold).monospacedDigit()
                        .accessibilityLabel("Flow chain \(controller.run.combo)")
                }
            }
            .allowsHitTesting(false)
        } else {
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    if controller.run.mode != .endless {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Image(systemName: "timer")
                                Text(CRFormat.seconds(controller.run.timeRemaining)).monospacedDigit()
                                Text("LEFT").font(CRTheme.label(9, .bold)).foregroundColor(CRTheme.inkSoft())
                            }.font(CRTheme.title(21)).foregroundColor(controller.run.timeRemaining < 12 ? CRTheme.coral : CRTheme.sea)
                            ProgressView(value: min(1, controller.run.distance / max(1, controller.run.courseTarget)))
                                .tint(CRTheme.sea).frame(width: 122)
                        }
                    }
                    Spacer()
                    if controller.run.combo > 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(controller.run.combo)×").font(CRTheme.display(30)).foregroundColor(CRTheme.gold).monospacedDigit()
                            Text("FLOW CHAIN").font(CRTheme.label(8, .bold)).kerning(1.5).foregroundColor(CRTheme.ink)
                        }
                    }
                }
                if controller.run.eventTime > 0 {
                    Text(controller.run.eventText.uppercased()).font(CRTheme.label(11, .heavy)).foregroundColor(CRTheme.ink)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(CRTheme.cream.opacity(0.82)))
                }
            }.allowsHitTesting(false)
        }
    }
}

private struct CRBoardButton: View {
    @ObservedObject var controller: GameController
    private var water: Bool { controller.run.isWaterTraversal }
    private var active: Bool { water ? controller.run.isBoosting : controller.run.boardTime > 0 }
    private var available: Bool { water ? (controller.run.boostCharge >= 0.5 && controller.run.height < 0.05) : controller.run.availableBoards > 0 }
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if water {
                Button { controller.perform(.roll) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.down").font(.system(size: 19, weight: .bold))
                        Text("BRAKE").font(CRTheme.label(9, .bold)).kerning(1)
                    }.foregroundColor(CRTheme.ink).frame(width: 62, height: 66)
                    .background(RoundedRectangle(cornerRadius: 12).fill(CRTheme.cream.opacity(0.86)))
                }.buttonStyle(CRPressStyle()).accessibilityLabel("Brake jet ski")
            }
            VStack(alignment: .trailing, spacing: 7) {
                if water {
                    HStack(spacing: 3) {
                        ForEach(0..<10) { n in Rectangle().fill(Double(n) / 10 < controller.run.boostCharge ? CRTheme.sea : CRTheme.ink.opacity(0.2)).frame(width: 4, height: 7) }
                    }.accessibilityLabel("Boost charge \(Int(controller.run.boostCharge * 100)) percent")
                }
                Button { controller.perform(.board) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: water ? "bolt.fill" : "shield.fill").font(.system(size: 22, weight: .bold))
                        Text(water ? (active ? "BOOSTING" : "BOOST") : active ? CRFormat.seconds(controller.run.boardTime) : "BOARD · \(controller.run.availableBoards)")
                            .font(CRTheme.label(9, .heavy)).kerning(0.8)
                    }
                    .foregroundColor(active ? CRTheme.cream : CRTheme.ink)
                    .frame(width: 78, height: 76)
                    .background(RoundedRectangle(cornerRadius: 12).fill(active ? CRTheme.sea : CRTheme.cream.opacity(0.92)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder((water ? CRTheme.sea : CRTheme.coral).opacity(0.7), lineWidth: 1))
                }.buttonStyle(CRPressStyle())
                    .disabled(!available || active || controller.run.portalReady || controller.run.isPortalTransitioning)
                    .opacity(controller.run.portalReady || controller.run.isPortalTransitioning ? 0.35 : available || active ? 1 : 0.45)
                .accessibilityLabel(water ? "Boost jet ski" : "Ride board")
            }
        }
    }
}

private struct CRTutorialHint: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(controller.run.mode == .jetSki ? "HOW TO RIDE" : "HOW TO RUN")
                .font(CRTheme.label(10, .bold))
                .kerning(1.8)
                .foregroundColor(CRTheme.coral)

            Text(controller.run.mode.instructions)
                .font(CRTheme.label(13, .medium))
                .foregroundColor(CRTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Button { controller.dismissTutorial() } label: {
                Text("Got it")
                    .font(CRTheme.label(14, .bold))
                    .foregroundColor(CRTheme.cream)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 44)
                    .background(Capsule(style: .continuous).fill(CRTheme.ink))
            }
            .buttonStyle(CRPressStyle())
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CRTheme.cream.opacity(0.96))
                .shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 8)
        )
    }
}

// MARK: - Overlay scaffolding

/// Cream postcard sheet floated over the live scene. Sized, never stretched.
private struct CROverlayCard<Content: View>: View {
    let kicker: String
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kicker).font(CRTheme.label(10, .bold)).kerning(2.2).foregroundColor(CRTheme.coral)
                            Text(title).font(CRTheme.display(34)).kerning(-0.8).foregroundColor(CRTheme.ink)
                                .minimumScaleFactor(0.7).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        content()
                    }
                    .padding(26)
                    .frame(maxWidth: 400, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CRTheme.cream).shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 16))
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }.scrollIndicators(.hidden)
            }
        }.transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

private struct CRActionButton: View {
    let title: String
    var subtitle: String?
    var kind: Kind = .primary
    var symbol: String?
    let action: () -> Void

    enum Kind { case primary, secondary, quiet }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(CRTheme.label(16, .bold))
                    if let subtitle {
                        Text(subtitle)
                            .font(CRTheme.label(11, .medium))
                            .opacity(0.78)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(foreground)
            .padding(.horizontal, 20)
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity)
            .background(background)
        }
        .buttonStyle(CRPressStyle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return CRTheme.cream
        case .secondary, .quiet: return CRTheme.ink
        }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CRTheme.coral)
                .shadow(color: CRTheme.coral.opacity(0.35), radius: 14, x: 0, y: 7)
        case .secondary:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CRTheme.ink.opacity(0.22), lineWidth: 1.5)
        case .quiet:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CRTheme.ink.opacity(0.05))
        }
    }
}

/// Sparse label / value line — the alternative to a dashboard of cards.
private struct CRFactRow: View {
    let label: String
    let value: String
    var tint: Color = CRTheme.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(CRTheme.label(13, .medium))
                .foregroundColor(CRTheme.inkSoft(0.6))
            Spacer(minLength: 12)
            Text(value)
                .font(CRTheme.label(16, .bold))
                .foregroundColor(tint)
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Paused / crashed / finished

private struct CRPausedOverlay: View {
    @ObservedObject var controller: GameController

    var body: some View {
        CROverlayCard(kicker: "PAUSED", title: "TAKE A\nBREATHER") {
            VStack(spacing: 10) {
                CRFactRow(label: "Score so far", value: CRFormat.count(controller.run.score))
                CRFactRow(label: "Distance", value: CRFormat.meters(controller.run.distance))
                if controller.run.mode == .odyssey {
                    CRRunObjectives(controller: controller)
                    CRSelectedPerks(controller: controller)
                }
                Divider().overlay(CRTheme.ink.opacity(0.1))
                CRActionButton(title: "Resume", kind: .primary, symbol: "play.fill") {
                    controller.resume()
                }
                CRActionButton(title: "End run", kind: .secondary) {
                    controller.finish()
                }
                CRActionButton(title: "How to play", kind: .quiet, symbol: "questionmark.circle.fill") {
                    controller.showPanel(.help)
                }
            }
        }
    }
}

private struct CRCrashOverlay: View {
    @ObservedObject var controller: GameController

    var body: some View {
        CROverlayCard(kicker: "WIPEOUT", title: controller.run.mode == .odyssey ? "KEEP\nEXPLORING?" : "ONE MORE\nWAVE?") {
            VStack(spacing: 10) {
                if !controller.run.crashReason.isEmpty {
                    Text(controller.run.crashReason)
                        .font(CRTheme.label(13, .medium))
                        .foregroundColor(CRTheme.inkSoft(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if controller.run.mode == .odyssey {
                    CRFactRow(label: "Worlds cleared", value: "\(controller.run.stagesCleared)", tint: CRTheme.sea)
                    CRFactRow(label: "Relics recovered", value: "\(controller.run.artifactsCollected)", tint: CRTheme.gold)
                }
                CRFactRow(label: "Score", value: CRFormat.count(controller.run.score))
                CRFactRow(label: "Coins collected",
                          value: CRFormat.count(controller.run.coins),
                          tint: CRTheme.gold)
                Divider().overlay(CRTheme.ink.opacity(0.1))
                if controller.run.isPractice {
                    CRActionButton(title: "Practice again", subtitle: "Restart this finale · no key needed", symbol: "arrow.counterclockwise") {
                        controller.startPractice(stage: controller.run.worldStage)
                    }
                } else {
                    CRActionButton(title: "Continue run",
                                   subtitle: reviveSubtitle,
                                   kind: .primary,
                                   symbol: "key.fill") {
                        controller.revive()
                    }
                    .disabled(!controller.canRevive)
                    .opacity(controller.canRevive ? 1 : 0.45)
                    .accessibilityHint(controller.canRevive
                                       ? "Spends one rescue key"
                                       : "Unavailable: \(reviveSubtitle)")
                }

                if controller.replayAvailable {
                    CRActionButton(title: "See what happened", kind: .quiet, symbol: "backward.end.fill") {
                        controller.startCrashReplay()
                    }
                }
                CRActionButton(title: "Finish run", kind: .secondary) {
                    controller.finish()
                }
            }
        }
    }

    private var reviveSubtitle: String {
        if controller.canRevive { return "Spend 1 key · one revive per run" }
        return controller.profile.keys > 0 ? "Already revived this run" : "No rescue keys left"
    }
}

private struct CRFinishOverlay: View {
    @ObservedObject var controller: GameController

    private var isBest: Bool {
        controller.achievedPersonalBest
    }

    var body: some View {
        CROverlayCard(kicker: isBest ? "NEW PERSONAL BEST" : "RUN COMPLETE",
                      title: controller.run.isPractice ? "PRACTICE\nCOMPLETE" : controller.run.mode == .odyssey ? (controller.run.journeyComplete ? (controller.run.stagesCleared == 6 ? "ODYSSEY\nCOMPLETE" : "ROUTE\nCOMPLETE") : "EXPEDITION\nLOGGED") : controller.run.mode != .endless && controller.run.distance >= controller.run.courseTarget ? "COURSE\nCLEARED" : "SESSION\nCOMPLETE") {
            VStack(spacing: 10) {
                if controller.run.mode == .odyssey {
                    CRFactRow(label: "Worlds cleared", value: "\(controller.run.stagesCleared)", tint: CRTheme.sea)
                    CRFactRow(label: "Relics recovered", value: "\(controller.run.artifactsCollected)", tint: CRTheme.gold)
                    if !controller.run.stageResults.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(Array(controller.run.stageResults.suffix(6).enumerated()), id: \.offset) { _, result in
                                VStack(spacing: 3) {
                                    CRMedalBadge(level: result.medal.rawValue)
                                    Text(result.stage.title).font(CRTheme.label(8, .bold)).lineLimit(1)
                                }.frame(maxWidth: .infinity)
                            }
                        }.padding(.vertical, 3)
                    }
                    CRRunObjectives(controller: controller)
                    if controller.run.isPractice {
                        Text("Practice builds skill. Coins, records and world unlocks stay with your expedition runs.")
                            .font(CRTheme.label(12, .medium)).foregroundColor(CRTheme.sea)
                    } else if controller.run.journeyComplete {
                        Text("You crossed the final rift. Your unlocked worlds are ready to revisit.")
                            .font(CRTheme.label(12, .medium)).foregroundColor(CRTheme.sea)
                    }
                }
                CRFactRow(label: "Score", value: CRFormat.count(controller.run.score))
                CRFactRow(label: "Coins",
                          value: CRFormat.count(controller.run.coins),
                          tint: CRTheme.gold)
                CRFactRow(label: "Distance", value: CRFormat.meters(controller.run.distance))
                CRFactRow(label: "Best flow chain", value: "\(controller.run.bestCombo)×", tint: CRTheme.gold)
                if controller.run.mode == .jetSki {
                    CRFactRow(label: "Gates / missed", value: "\(controller.run.gatesCleared) / \(controller.run.gatesMissed)")
                } else {
                    CRFactRow(label: "Close calls", value: "\(controller.run.nearMisses)")
                }
                CRFactRow(label: controller.isDailyRun ? "Daily best" : "Best score",
                          value: CRFormat.count(controller.isDailyRun
                                                ? controller.profile.dailyChallengeBest
                                                : controller.profile.modeBestScore(mode: controller.run.mode, expert: controller.run.expert, expeditionStyle: controller.run.expeditionStyle)),
                          tint: CRTheme.coral)
                Divider().overlay(CRTheme.ink.opacity(0.1))
                CRActionButton(title: controller.run.isPractice ? "Practice again" : "Go again", kind: .primary, symbol: "arrow.counterclockwise") {
                    if controller.run.isPractice { controller.startPractice(stage: controller.run.worldStage) }
                    else { controller.start(daily: controller.isDailyRun) }
                }
                CRActionButton(title: "Back to harbor", kind: .secondary, symbol: "house.fill") {
                    controller.returnToMenu()
                }
            }
        }
    }
}

// MARK: - Toast

private struct CRToastLayer: View {
    let message: String?

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let message {
                Text(message)
                    .font(CRTheme.label(13, .bold))
                    .foregroundColor(CRTheme.cream)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CRTheme.ink.opacity(0.93))
                            .shadow(color: CRTheme.ink.opacity(0.2), radius: 12, x: 0, y: 6)
                    )
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: message)
    }
}

// MARK: - Sheets

private enum CRIcon {
    static func power(_ power: PowerUp) -> String {
        switch power {
        case .magnet: return "arrow.triangle.merge"
        case .jetpack: return "flame.fill"
        case .sneakers: return "hare.fill"
        case .multiplier: return "multiply.circle.fill"
        }
    }

    static func character(_ id: String) -> String {
        switch id {
        case "sana": return "figure.wave"
        case "rio": return "figure.run"
        default: return "figure.walk"
        }
    }

    static func board(_ id: String) -> String {
        switch id {
        case "sunset": return "sun.max.fill"
        case "mint": return "leaf.fill"
        default: return "water.waves"
        }
    }

    static func tint(_ id: String) -> Color {
        switch id {
        case "sana", "sunset": return CRTheme.gold
        case "rio", "mint": return CRTheme.mint
        default: return CRTheme.coral
        }
    }
}

private struct CRPanelSheet: View {
    let panel: GamePanel
    @ObservedObject var controller: GameController

    #if os(macOS)
    private static let sheetMinWidth: CGFloat = 520
    private static let sheetMinHeight: CGFloat = 620
    #else
    private static let sheetMinWidth: CGFloat = 0
    private static let sheetMinHeight: CGFloat = 0
    #endif

    var body: some View {
        ZStack {
            CRTheme.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    panelBody(for: panel)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 520, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(minWidth: Self.sheetMinWidth, minHeight: Self.sheetMinHeight)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kicker)
                    .font(CRTheme.label(10, .bold))
                    .kerning(2.2)
                    .foregroundColor(CRTheme.coral)
                Text(title)
                    .font(CRTheme.display(32))
                    .kerning(-0.8)
                    .foregroundColor(CRTheme.ink)
                if panel == .locker || panel == .upgrades || panel == .missions {
                    Label("\(CRFormat.count(controller.profile.coins)) coins available", systemImage: "circle.fill")
                        .font(CRTheme.label(12, .semibold))
                        .foregroundColor(CRTheme.sea)
                        .padding(.top, 6)
                }
            }
            Spacer(minLength: 12)
            Button { controller.panel = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(CRTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(CRTheme.ink.opacity(0.07)))
            }
            .buttonStyle(CRPressStyle(scale: 0.9))
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        switch panel {
        case .missions: return "MISSIONS"
        case .locker: return "LOCKER"
        case .upgrades: return "UPGRADES"
        case .settings: return "SETTINGS"
        case .help: return "HOW TO PLAY"
        case .scores: return "YOUR RUNS"
        case .journey: return "THE STAR ATLAS"
        case .loadout: return "YOUR BUILD"
        }
    }

    private var kicker: String {
        switch panel {
        case .missions: return "EARN A BIGGER MULTIPLIER"
        case .locker: return "RUNNERS & BOARDS"
        case .upgrades: return "LONGER POWER-UPS"
        case .settings: return "SOUND, FEEL & HELP"
        case .help: return "THREE LANES, FOUR POWERS"
        case .scores: return "SAVED ON THIS DEVICE"
        case .journey: return "SIX WORLDS · SIX RELICS"
        case .loadout: return "TIME IS PAUSED · CHOOSE YOUR NEXT MOVE"
        }
    }

    @ViewBuilder
    private func panelBody(for panel: GamePanel) -> some View {
        switch panel {
        case .missions: CRMissionsPanel(controller: controller)
        case .locker: CRLockerPanel(controller: controller)
        case .upgrades: CRUpgradesPanel(controller: controller)
        case .settings: CRSettingsPanel(controller: controller)
        case .help: CRHelpPanel()
        case .scores: CRScoresPanel(profile: controller.profile)
        case .journey: CRJourneyPanel(controller: controller)
        case .loadout:
            VStack(alignment: .leading, spacing: 20) {
                CRPerkSelection(controller: controller)
                CRSelectedPerks(controller: controller)
                CRArtifactLoadout(controller: controller)
                CRRunObjectives(controller: controller)
                CRActionButton(title: "Resume expedition", symbol: "play.fill") { controller.resume() }
            }
        }
    }
}

// MARK: Missions

private struct CRMissionsPanel: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Every run counts toward all three. Clear the set to raise your base score multiplier.")
                .font(CRTheme.label(13, .medium))
                .foregroundColor(CRTheme.inkSoft(0.7))
                .fixedSize(horizontal: false, vertical: true)

            CRFactRow(label: "Base multiplier now",
                      value: "×\(controller.profile.baseMultiplier)",
                      tint: CRTheme.coral)

            ForEach(controller.profile.missions) { mission in
                CRMissionRow(mission: mission,
                             claimed: controller.profile.claimedMissionIDs.contains(mission.id)) {
                    controller.claimMission(mission.id)
                }
            }

            CRSkillChallenges(controller: controller)

            Text("Next tier pays ×\(controller.profile.baseMultiplier + 1) on every metre you run.")
                .font(CRTheme.label(12, .semibold))
                .foregroundColor(CRTheme.inkSoft(0.6))
                .padding(.top, 2)
        }
    }
}

private struct CRMissionRow: View {
    let mission: Mission
    let claimed: Bool
    let claim: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mission.title)
                        .font(CRTheme.label(16, .bold))
                        .foregroundColor(CRTheme.ink)
                    Text(mission.detail)
                        .font(CRTheme.label(12, .medium))
                        .foregroundColor(CRTheme.inkSoft(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailing
            }
            CRProgressBar(fraction: fraction, tint: mission.complete ? CRTheme.coral : CRTheme.sea)
            Text("\(CRFormat.count(min(mission.progress, mission.target))) / \(CRFormat.count(mission.target))")
                .font(CRTheme.label(11, .semibold))
                .foregroundColor(CRTheme.inkSoft(0.55))
                .monospacedDigit()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CRTheme.ink.opacity(0.08)).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var fraction: Double {
        guard mission.target > 0 else { return 0 }
        return min(1, Double(max(0, mission.progress)) / Double(mission.target))
    }

    @ViewBuilder
    private var trailing: some View {
        if claimed {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .bold))
                Text("Claimed").font(CRTheme.label(12, .bold))
            }
            .foregroundColor(CRTheme.inkSoft(0.5))
            .frame(minHeight: 44)
            .accessibilityLabel("Reward claimed")
        } else if mission.complete {
            Button(action: claim) {
                Text("Claim +\(CRFormat.count(mission.reward))")
                    .font(CRTheme.label(13, .bold))
                    .foregroundColor(CRTheme.cream)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Capsule(style: .continuous).fill(CRTheme.coral))
            }
            .buttonStyle(CRPressStyle())
            .accessibilityLabel("Claim \(CRFormat.count(mission.reward)) coins")
        } else {
            Text("+\(CRFormat.count(mission.reward))")
                .font(CRTheme.label(13, .bold))
                .foregroundColor(CRTheme.gold)
                .frame(minHeight: 44)
                .accessibilityLabel("Reward \(CRFormat.count(mission.reward)) coins")
        }
    }
}

private struct CRProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(CRTheme.ink.opacity(0.1))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

// MARK: Locker

private struct CRLockerPanel: View {
    @ObservedObject var controller: GameController
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Locker section", selection: $tab) {
                Text("Runners").tag(0)
                Text("Boards").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == 0 {
                ForEach(GameCatalog.characters) { character in
                    CRLockerRow(
                        id: character.id,
                        name: character.name,
                        subtitle: character.subtitle,
                        cost: character.cost,
                        symbol: CRIcon.character(character.id),
                        unlocked: controller.profile.unlockedCharacters.contains(character.id),
                        selected: controller.profile.selectedCharacter == character.id,
                        coins: controller.profile.coins,
                        select: { controller.selectCharacter(character.id) },
                        purchase: { controller.purchaseCharacter(character.id) }
                    )
                }
            } else {
                ForEach(GameCatalog.boards) { board in
                    CRLockerRow(
                        id: board.id,
                        name: board.name,
                        subtitle: board.subtitle,
                        cost: board.cost,
                        symbol: CRIcon.board(board.id),
                        unlocked: controller.profile.unlockedBoards.contains(board.id),
                        selected: controller.profile.selectedBoard == board.id,
                        coins: controller.profile.coins,
                        select: { controller.selectBoard(board.id) },
                        purchase: { controller.purchaseBoard(board.id) }
                    )
                }
            }

            Text("You have \(CRFormat.count(controller.profile.coins)) coins.")
                .font(CRTheme.label(12, .semibold))
                .foregroundColor(CRTheme.inkSoft(0.6))
        }
    }
}

private struct CRLockerRow: View {
    let id: String
    let name: String
    let subtitle: String
    let cost: Int
    let symbol: String
    let unlocked: Bool
    let selected: Bool
    let coins: Int
    let select: () -> Void
    let purchase: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            CRLockerArt(symbol: symbol, tint: CRIcon.tint(id), locked: !unlocked)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(CRTheme.label(17, .bold))
                    .foregroundColor(CRTheme.ink)
                Text(subtitle)
                    .font(CRTheme.label(12, .medium))
                    .foregroundColor(CRTheme.inkSoft(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
            action
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CRTheme.ink.opacity(0.08)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var action: some View {
        if selected {
            Text("Wearing")
                .font(CRTheme.label(12, .bold))
                .foregroundColor(CRTheme.coral)
                .frame(minHeight: 44)
                .accessibilityLabel("\(name) is selected")
        } else if unlocked {
            Button(action: select) {
                Text("Select")
                    .font(CRTheme.label(13, .bold))
                    .foregroundColor(CRTheme.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(
                        Capsule(style: .continuous)
                            .strokeBorder(CRTheme.ink.opacity(0.22), lineWidth: 1.5)
                    )
            }
            .buttonStyle(CRPressStyle())
            .accessibilityLabel("Select \(name)")
        } else {
            Button(action: purchase) {
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill").font(.system(size: 9, weight: .bold))
                    Text(CRFormat.count(cost)).font(CRTheme.label(13, .bold))
                }
                .foregroundColor(CRTheme.cream)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule(style: .continuous).fill(coins >= cost ? CRTheme.coral : CRTheme.ink.opacity(0.3)))
            }
            .buttonStyle(CRPressStyle())
            .accessibilityLabel("Unlock \(name) for \(CRFormat.count(cost)) coins")
        }
    }
}

private struct CRLockerArt: View {
    let symbol: String
    let tint: Color
    let locked: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Circle()
                .strokeBorder(CRTheme.ink.opacity(0.12), lineWidth: 1)
            Image(systemName: locked ? "lock.fill" : symbol)
                .font(.system(size: locked ? 17 : 22, weight: .bold))
                .foregroundColor(CRTheme.cream)
        }
        .frame(width: 54, height: 54)
        .saturation(locked ? 0.25 : 1)
        .accessibilityHidden(true)
    }
}

// MARK: Upgrades

private struct CRUpgradesPanel: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Upgrades make each power-up last longer. Five levels each.")
                .font(CRTheme.label(13, .medium))
                .foregroundColor(CRTheme.inkSoft(0.7))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(PowerUp.allCases, id: \.rawValue) { power in
                CRUpgradeRow(power: power,
                             level: level(power),
                             duration: controller.profile.powerUpDuration(power),
                             cost: controller.profile.upgradeCost(power),
                             coins: controller.profile.coins) {
                    controller.upgrade(power)
                }
            }

            Text("SUPPLIES")
                .font(CRTheme.label(10, .bold))
                .kerning(1.8)
                .foregroundColor(CRTheme.coral)
                .padding(.top, 8)

            CRSupplyRow(title: "Three boards",
                        detail: "Each board absorbs one crash. You hold \(CRFormat.count(controller.profile.boards)).",
                        cost: 150,
                        symbol: "shield.fill",
                        coins: controller.profile.coins) { controller.buyBoards() }

            CRSupplyRow(title: "One rescue key",
                        detail: "Revive once per run. You hold \(CRFormat.count(controller.profile.keys)).",
                        cost: 250,
                        symbol: "key.fill",
                        coins: controller.profile.coins) { controller.buyKeys() }
        }
    }

    private func level(_ power: PowerUp) -> Int {
        min(PlayerProfile.maximumUpgradeLevel, max(0, controller.profile.upgradeLevels[power.rawValue] ?? 0))
    }
}

private struct CRUpgradeRow: View {
    let power: PowerUp
    let level: Int
    let duration: Double
    let cost: Int
    let coins: Int
    let buy: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: CRIcon.power(power))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(CRTheme.cream)
                .frame(width: 44, height: 44)
                .background(Circle().fill(CRTheme.sea))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(GameCatalog.name(forPower: power))
                    .font(CRTheme.label(16, .bold))
                    .foregroundColor(CRTheme.ink)
                Text("Level \(level) of \(PlayerProfile.maximumUpgradeLevel) · lasts \(CRFormat.seconds(duration))")
                    .font(CRTheme.label(12, .medium))
                    .foregroundColor(CRTheme.inkSoft(0.62))
                CRLevelDots(level: level)
            }

            Spacer(minLength: 8)

            if cost == 0 {
                Text("Maxed")
                    .font(CRTheme.label(12, .bold))
                    .foregroundColor(CRTheme.mint)
                    .frame(minHeight: 44)
            } else {
                Button(action: buy) {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.fill").font(.system(size: 9, weight: .bold))
                        Text(CRFormat.count(cost)).font(CRTheme.label(13, .bold))
                    }
                    .foregroundColor(CRTheme.cream)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Capsule(style: .continuous).fill(coins >= cost ? CRTheme.coral : CRTheme.ink.opacity(0.3)))
                }
                .buttonStyle(CRPressStyle())
                .accessibilityLabel("Upgrade \(GameCatalog.name(forPower: power)) for \(CRFormat.count(cost)) coins")
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CRTheme.ink.opacity(0.08)).frame(height: 1)
        }
    }
}

private struct CRLevelDots: View {
    let level: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<PlayerProfile.maximumUpgradeLevel, id: \.self) { index in
                Capsule()
                    .fill(index < level ? CRTheme.coral : CRTheme.ink.opacity(0.14))
                    .frame(width: 16, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CRSupplyRow: View {
    let title: String
    let detail: String
    let cost: Int
    let symbol: String
    let coins: Int
    let buy: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(CRTheme.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(CRTheme.gold.opacity(0.28)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CRTheme.label(16, .bold))
                    .foregroundColor(CRTheme.ink)
                Text(detail)
                    .font(CRTheme.label(12, .medium))
                    .foregroundColor(CRTheme.inkSoft(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: buy) {
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill").font(.system(size: 9, weight: .bold))
                    Text(CRFormat.count(cost)).font(CRTheme.label(13, .bold))
                }
                .foregroundColor(CRTheme.cream)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule(style: .continuous).fill(coins >= cost ? CRTheme.coral : CRTheme.ink.opacity(0.3)))
            }
            .buttonStyle(CRPressStyle())
            .accessibilityLabel("Buy \(title) for \(CRFormat.count(cost)) coins")
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CRTheme.ink.opacity(0.08)).frame(height: 1)
        }
    }
}

// MARK: Settings

private struct CRSettingsPanel: View {
    @ObservedObject var controller: GameController

    private var soundBinding: Binding<Bool> {
        Binding(get: { controller.profile.soundEnabled }, set: { _ in controller.toggleSound() })
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(get: { controller.profile.hapticsEnabled }, set: { _ in controller.toggleHaptics() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: soundBinding) {
                CRToggleLabel(symbol: "speaker.wave.2.fill",
                              title: "Sound",
                              detail: "Coins, boards and wipeouts.")
            }
            .tint(CRTheme.coral)
            .frame(minHeight: 56)

            Toggle(isOn: hapticsBinding) {
                CRToggleLabel(symbol: "iphone.radiowaves.left.and.right",
                              title: "Haptics",
                              detail: "A tap for every lane change.")
            }
            .tint(CRTheme.coral)
            .frame(minHeight: 56)

            Divider().overlay(CRTheme.ink.opacity(0.1)).padding(.vertical, 6)
            Text("PLAY & PERFORMANCE").font(CRTheme.label(10, .bold)).kerning(1.8).foregroundColor(CRTheme.sea)
            Toggle(isOn: Binding(get: { controller.profile.portalAssist }, set: controller.setPortalAssist)) {
                CRToggleLabel(symbol: "sparkles", title: "Portal assist", detail: "Keep moving through the rift automatically.")
            }.tint(CRTheme.sea).frame(minHeight: 56)
            Toggle(isOn: Binding(get: { controller.profile.reducedMotion }, set: controller.setReducedMotion)) {
                CRToggleLabel(symbol: "camera.metering.center.weighted", title: "Reduced motion", detail: "Steady camera and quieter transitions.")
            }.tint(CRTheme.sea).frame(minHeight: 56)
            Toggle(isOn: Binding(get: { controller.profile.highContrastCues }, set: controller.setHighContrastCues)) {
                CRToggleLabel(symbol: "circle.lefthalf.filled", title: "High contrast cues", detail: "Stronger hazard outlines and action signals.")
            }.tint(CRTheme.sea).frame(minHeight: 56)
            Toggle(isOn: Binding(get: { controller.profile.ghostEnabled }, set: controller.setGhostEnabled)) {
                CRToggleLabel(symbol: "figure.run", title: "Personal ghost", detail: "Race your best attempt on a matching course.")
            }.tint(CRTheme.sea).frame(minHeight: 56)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Swipe sensitivity").font(CRTheme.label(16, .bold))
                    Spacer()
                    Text(String(format: "%.0f%%", controller.profile.swipeSensitivity * 100)).font(CRTheme.label(12, .bold)).monospacedDigit()
                }
                Slider(value: Binding(get: { controller.profile.swipeSensitivity }, set: controller.setSwipeSensitivity), in: 0.65...1.5, step: 0.05)
                    .tint(CRTheme.sea).accessibilityLabel("Swipe sensitivity")
                Text("Higher values need shorter swipes. Fast swipe chains stay responsive.")
                    .font(CRTheme.label(12, .medium)).foregroundColor(CRTheme.inkSoft())
                CRSwipeCalibration(sensitivity: controller.profile.swipeSensitivity)
            }.padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 8) {
                Text("Graphics quality").font(CRTheme.label(16, .bold))
                Picker("Graphics quality", selection: Binding(get: { controller.profile.graphicsQuality }, set: controller.setGraphicsQuality)) {
                    Text("Auto").tag(RenderQuality.automatic)
                    Text("Fast").tag(RenderQuality.performance)
                    Text("Balanced").tag(RenderQuality.balanced)
                    Text("Ultra").tag(RenderQuality.ultra)
                }.pickerStyle(.segmented)
                Text("Auto adapts effects to your device and temperature. Fast reduces shadows and effects; Ultra prioritizes detail.")
                    .font(CRTheme.label(12, .medium)).foregroundColor(CRTheme.inkSoft()).fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 10)
            Divider().overlay(CRTheme.ink.opacity(0.1)).padding(.vertical, 6)

            DisclosureGroup {
                Text(controller.performanceReport)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(CRTheme.inkSoft(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .textSelection(.enabled)
                Text("Local frame and input timings help check this device. They are not sent anywhere.")
                    .font(CRTheme.label(11, .medium)).foregroundColor(CRTheme.inkSoft())
            } label: {
                Label("Device diagnostics", systemImage: "waveform.path.ecg")
                    .font(CRTheme.label(14, .bold))
            }.tint(CRTheme.sea).padding(.vertical, 10)

            CRNavRow(symbol: "questionmark.circle.fill", title: "How to play") {
                switchPanel(.help)
            }
            CRNavRow(symbol: "trophy.fill", title: "Your runs") {
                switchPanel(.scores)
            }

            Divider().overlay(CRTheme.ink.opacity(0.1)).padding(.vertical, 6)

            CRGhostRaceRow(controller: controller)
            Text("LIFETIME")
                .font(CRTheme.label(10, .bold))
                .kerning(1.8)
                .foregroundColor(CRTheme.coral)
            CRFactRow(label: "Runs", value: CRFormat.count(controller.profile.totalRuns))
            CRFactRow(label: "Distance", value: CRFormat.meters(controller.profile.totalDistance))
            CRFactRow(label: "Coins earned",
                      value: CRFormat.count(controller.profile.totalCoins),
                      tint: CRTheme.gold)
            CRFactRow(label: "Best score",
                      value: CRFormat.count(controller.profile.bestScore),
                      tint: CRTheme.coral)

            Text("Everything is stored on this device. Coastline Rush is fully offline.")
                .font(CRTheme.label(12, .medium))
                .foregroundColor(CRTheme.inkSoft(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    /// Swapping a presented sheet's identity directly can drop the new sheet,
    /// so dismiss first and present the next panel on the following beat.
    private func switchPanel(_ panel: GamePanel) {
        let target = controller
        target.panel = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            target.panel = panel
        }
    }
}

private struct CRToggleLabel: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(CRTheme.ink)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(CRTheme.label(16, .bold))
                    .foregroundColor(CRTheme.ink)
                Text(detail)
                    .font(CRTheme.label(12, .medium))
                    .foregroundColor(CRTheme.inkSoft(0.62))
            }
        }
    }
}

private struct CRNavRow: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(CRTheme.ink)
                    .frame(width: 34)
                Text(title)
                    .font(CRTheme.label(16, .bold))
                    .foregroundColor(CRTheme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(CRTheme.inkSoft(0.4))
            }
            .frame(minHeight: 56)
        }
        .buttonStyle(CRPressStyle(scale: 0.99))
    }
}

// MARK: Help

private struct CRHelpPanel: View {
    private static let touchControls: [(String, String)] = [
        ("Swipe left or right", "Hop to the next lane. Three lanes, that's it."),
        ("Swipe up", "Jump a cargo barrier, or land on a tram roof."),
        ("Swipe down", "Roll under the low signs. Roll to scoop low coins."),
        ("Double-tap", "Ride a board. It absorbs one crash, then it's gone.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("CONTROLS") {
                ForEach(Self.touchControls, id: \.0) { title, detail in
                    CRHelpRow(title: title, detail: detail)
                }
                CRHelpRow(title: "Keyboard",
                          detail: "Arrows or WASD to move, space to jump, B for a board, E for your artifact, Esc to pause.")
            }

            section("CHOOSE YOUR CHALLENGE") {
                ForEach(RunMode.allCases, id: \.rawValue) { mode in
                    CRHelpRow(title: mode.title, detail: mode.instructions)
                }
                CRHelpRow(title: "Flow chains", detail: "Clear hazards, skim close calls and hit gates to build your chain. Keep acting before it decays. A collision or missed gate breaks your flow.")
                CRHelpRow(title: "Expert", detail: "Faster starts, tighter patterns and a separate personal best for each mode.")
                CRHelpRow(title: "Mastery medals", detail: "Bronze: clear a world. Silver: clear it without a hit and perform two obstacle actions. Gold: also recover two risky relics and time your portal jump. Replay unlocked worlds to improve your medal.")
                CRHelpRow(title: "Risk routes", detail: "Gold relics sit behind optional skill challenges. Follow the marked route and jump or slide as signaled; the ordinary route remains available.")
                CRHelpRow(title: "Artifacts", detail: "Relics charge your equipped ability, up to three uses. Tap the artifact control or press E to activate it. Change your ability in the Atlas before a run or at an approaching portal.")
                CRHelpRow(title: "Portal assist", detail: "Your runner enters portals automatically by default. Jump at the portal yourself for a precision bonus. Disable assist in Settings for manual entry.")
                CRHelpRow(title: "Personal ghost", detail: "A translucent opponent replays your best attempt on the identical course. Race it from the Atlas, or repeat today’s Daily Odyssey. Ghosts never collide with you.")
            }
            section("JET SKI CONTROLS") {
                CRHelpRow(title: "Steer / brake / boost", detail: "Swipe sideways to steer. Swipe down or tap Brake to slow for a gate. Double-tap, tap Boost or press B to spend earned boost charge.")
                CRHelpRow(title: "Ramp tricks", detail: "Take a wave ramp and swipe up while airborne to land a trick. Gates add time; misses cost time and break your chain.")
            }
            section("POWER-UPS") {
                ForEach(PowerUp.allCases, id: \.rawValue) { power in
                    CRHelpRow(symbol: CRIcon.power(power),
                              title: GameCatalog.name(forPower: power),
                              detail: Self.detail(power))
                }
            }

            section("THE RULES") {
                CRHelpRow(symbol: "shield.fill",
                          title: "A board absorbs one crash",
                          detail: "Ride it before a tricky stretch. One crash, one board.")
                CRHelpRow(symbol: "key.fill",
                          title: "One revive per run",
                          detail: "A rescue key puts you back on the track with three seconds of protection.")
                CRHelpRow(symbol: "calendar",
                          title: "Daily Odyssey",
                          detail: "One fixed six-world route per UTC day. Standard difficulty, a fresh expedition from the harbor, and your own matching ghost to beat.")
            }
        }
    }

    private static func detail(_ power: PowerUp) -> String {
        switch power {
        case .magnet: return "Pulls nearby coins straight to you."
        case .jetpack: return "Fly above the road. Steer through aerial rings and dodge the airborne hazards."
        case .sneakers: return "Much taller jumps while they last."
        case .multiplier: return "Doubles your score multiplier."
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(CRTheme.label(10, .bold))
                .kerning(1.8)
                .foregroundColor(CRTheme.coral)
            content()
        }
    }
}

private struct CRHelpRow: View {
    var symbol: String?
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(CRTheme.sea)
                    .frame(width: 24, height: 22)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CRTheme.label(15, .bold))
                    .foregroundColor(CRTheme.ink)
                Text(detail)
                    .font(CRTheme.label(13, .medium))
                    .foregroundColor(CRTheme.inkSoft(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Scores

private struct CRScoresPanel: View {
    let profile: PlayerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(RunMode.allCases, id: \.rawValue) { mode in
                CRFactRow(label: mode.title, value: CRFormat.count(profile.modeBestScore(mode: mode, expert: false)), tint: CRTheme.sea)
                CRFactRow(label: "  Expert", value: CRFormat.count(profile.modeBestScore(mode: mode, expert: true)))
            }
            CRFactRow(label: "Endless Odyssey", value: CRFormat.count(profile.modeBestScore(mode: .odyssey, expert: false, expeditionStyle: .endless)), tint: CRTheme.sea)
            CRFactRow(label: "  Expert", value: CRFormat.count(profile.modeBestScore(mode: .odyssey, expert: true, expeditionStyle: .endless)))
            Divider().overlay(CRTheme.ink.opacity(0.15))
            if profile.recentScores.isEmpty {
                Text("No runs saved yet. Head back to the harbor and take the first one.")
                    .font(CRTheme.label(14, .medium))
                    .foregroundColor(CRTheme.inkSoft(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                CRFactRow(label: "Best score",
                          value: CRFormat.count(profile.bestScore),
                          tint: CRTheme.coral)
                if profile.dailyOdysseyScore() > 0 {
                    CRFactRow(label: "Today's Daily Odyssey",
                              value: CRFormat.count(profile.dailyOdysseyScore()),
                              tint: CRTheme.sea)
                }

                Text("LAST \(profile.recentScores.count) RUNS")
                    .font(CRTheme.label(10, .bold))
                    .kerning(1.8)
                    .foregroundColor(CRTheme.coral)
                    .padding(.top, 6)

                ForEach(Array(profile.recentScores.enumerated()), id: \.offset) { index, score in
                    CRScoreRow(position: index + 1, score: score, isBest: score == profile.bestScore)
                }
            }
        }
    }
}

private struct CRScoreRow: View {
    let position: Int
    let score: Int
    let isBest: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text("\(position)")
                .font(CRTheme.label(13, .bold))
                .foregroundColor(CRTheme.inkSoft(0.45))
                .frame(width: 24, alignment: .leading)
                .monospacedDigit()
            Text(CRFormat.count(score))
                .font(CRTheme.label(17, .bold))
                .foregroundColor(CRTheme.ink)
                .monospacedDigit()
            Spacer(minLength: 8)
            if isBest {
                HStack(spacing: 5) {
                    Image(systemName: "trophy.fill").font(.system(size: 11, weight: .bold))
                    Text("Best").font(CRTheme.label(12, .bold))
                }
                .foregroundColor(CRTheme.coral)
            }
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CRTheme.ink.opacity(0.08)).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isBest
                            ? "Run \(position), \(CRFormat.count(score)) points, personal best"
                            : "Run \(position), \(CRFormat.count(score)) points")
    }
}


private struct CRJourneyPanel: View {
    @ObservedObject var controller: GameController
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Six worlds to discover. Three mastery medals in each. Choose your next route and the artifact you’ll carry.")
                .font(CRTheme.label(13, .medium)).foregroundColor(CRTheme.inkSoft(0.8))
            HStack {
                Label("\(controller.profile.collectedRelicWorlds.count) / 6 relics", systemImage: "sparkles")
                Spacer()
                Text("\(controller.profile.completedExpeditions) expeditions")
            }.font(CRTheme.label(11, .bold)).foregroundColor(CRTheme.sea)
            CRArtifactLoadout(controller: controller)
            CRGhostRaceRow(controller: controller)
            if controller.run.phase == .menu {
                CRActionButton(title: "Practice \(controller.selectedStage.title)", subtitle: "Final ~30 seconds · no wallet or record changes", kind: .secondary, symbol: "scope") {
                    controller.startPractice(stage: controller.selectedStage)
                }
            }
            Text("BRONZE · CLEAR   /   SILVER · CLEAN   /   GOLD · MASTER")
                .font(CRTheme.label(9, .heavy)).kerning(0.8).foregroundColor(CRTheme.gold)
            Text("Silver needs a clean stage and two obstacle actions. Gold adds two risky relics and a precision portal jump.")
                .font(CRTheme.label(11, .medium)).foregroundColor(CRTheme.inkSoft())
            ForEach(Array(WorldStage.allCases.enumerated()), id: \.element.rawValue) { index, stage in
                let unlocked = index <= controller.profile.highestUnlockedWorld
                let collected = controller.profile.collectedRelicWorlds.contains(stage)
                Button {
                    controller.selectWorld(index)
                    controller.panel = nil
                } label: {
                    HStack(alignment: .top, spacing: 13) {
                        ZStack {
                            Circle().fill(unlocked ? CRTheme.sea.opacity(0.16) : CRTheme.ink.opacity(0.06)).frame(width: 38, height: 38)
                            if unlocked { Text(String(format: "%02d", index + 1)).font(CRTheme.title(15)) }
                            else { Image(systemName: "lock.fill") }
                        }.foregroundColor(unlocked ? CRTheme.sea : CRTheme.inkSoft(0.45))
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(stage.title.uppercased()).font(CRTheme.label(14, .heavy)).kerning(1)
                                CRMedalBadge(level: controller.profile.worldMedals[stage.rawValue] ?? 0)
                            }
                            Text(stage.subtitle).font(CRTheme.label(11, .medium)).foregroundColor(CRTheme.inkSoft(0.75))
                            Label(collected ? stage.artifactName : "Unrecovered · \(stage.artifactName)", systemImage: collected ? "sparkle" : "diamond")
                                .font(CRTheme.label(10, .semibold)).foregroundColor(collected ? CRTheme.gold : CRTheme.inkSoft(0.5))
                            Text(unlocked ? "Best \(CRFormat.meters(controller.profile.worldBestDistance(stage))) · \(CRFormat.meters(stage.length)) world" : "Clear world \(index) to unlock")
                                .font(CRTheme.label(10, .medium)).foregroundColor(CRTheme.inkSoft(0.6))
                        }
                        Spacer(minLength: 0)
                        if index == controller.selectedWorld { Image(systemName: "checkmark.circle.fill").foregroundColor(CRTheme.sea) }
                        else if unlocked { Image(systemName: "arrow.up.right").foregroundColor(CRTheme.inkSoft()) }
                    }.foregroundColor(CRTheme.ink).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(CRTheme.creamEdge.opacity(index == controller.selectedWorld ? 1 : 0.55)))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(index == controller.selectedWorld ? CRTheme.sea.opacity(0.6) : .clear, lineWidth: 1))
                }.buttonStyle(CRPressStyle()).disabled(!unlocked || controller.run.phase != .menu)
                    .accessibilityLabel("World \(index + 1), \(stage.title), \(unlocked ? "unlocked" : "locked"), \(collected ? "relic recovered" : "relic not recovered")")
                    .accessibilityHint(unlocked ? "Select this world as your expedition starting point" : "Clear the previous world to unlock")
            }
        }
    }
}

// MARK: Expedition equipment and mastery

private struct CRMedalBadge: View {
    let level: Int
    private var tint: Color { level == 3 ? CRTheme.gold : level == 2 ? CRTheme.ink : level == 1 ? CRTheme.coral : CRTheme.ink.opacity(0.25) }
    var body: some View {
        Image(systemName: level > 0 ? "medal.fill" : "medal")
            .font(.system(size: 17, weight: .semibold)).foregroundColor(tint)
            .accessibilityLabel(level == 3 ? "Gold mastery" : level == 2 ? "Silver mastery" : level == 1 ? "Bronze mastery" : "No medal yet")
    }
}

private struct CRArtifactLoadout: View {
    @ObservedObject var controller: GameController
    private var canChoose: Bool { controller.run.phase == .menu || controller.run.canChooseAbility }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ARTIFACT LOADOUT").font(CRTheme.label(10, .bold)).kerning(1.5).foregroundColor(CRTheme.sea)
            HStack(spacing: 7) {
                ForEach(ArtifactAbility.allCases, id: \.rawValue) { ability in
                    let selected = controller.profile.selectedArtifact == ability
                    Button { controller.equipArtifact(ability) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: ability.symbol).font(.system(size: 20, weight: .semibold))
                            Text(ability.title).font(CRTheme.label(10, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                        }.foregroundColor(selected ? CRTheme.cream : CRTheme.ink)
                            .frame(maxWidth: .infinity).frame(height: 65)
                            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? CRTheme.sea : CRTheme.creamEdge))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? CRTheme.ink : CRTheme.sea.opacity(0.40), lineWidth: selected ? 2 : 1))
                            .overlay(alignment: .topTrailing) {
                                if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .bold)).foregroundColor(CRTheme.cream).padding(5) }
                            }
                    }.buttonStyle(CRPressStyle()).disabled(!canChoose)
                        .accessibilityLabel("Equip \(ability.title)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text(controller.profile.selectedArtifact.detail)
                .font(CRTheme.label(12, .medium)).foregroundColor(CRTheme.inkSoft(0.8)).fixedSize(horizontal: false, vertical: true)
            Text(canChoose ? "Risky relics earn charges. Your run’s upgrades can change their cost and capacity." : "Change your loadout at the next portal or before a run.")
                .font(CRTheme.label(11, .medium)).foregroundColor(CRTheme.inkSoft())
        }.padding(.vertical, 7)
    }
}

private struct CRArtifactButton: View {
    @ObservedObject var controller: GameController
    private var ability: ArtifactAbility { controller.run.selectedAbility ?? controller.profile.selectedArtifact }
    private var active: Bool { controller.run.isAbilityActive }
    private var available: Bool { controller.run.canActivateAbility }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if controller.run.canChooseAbility || controller.run.canChoosePerk {
                Button { controller.showPanel(.loadout) } label: {
                    Label(controller.run.canChoosePerk ? "UPGRADE" : "LOADOUT", systemImage: controller.run.canChoosePerk ? "sparkles" : "slider.horizontal.3")
                        .font(CRTheme.label(9, .bold)).foregroundColor(CRTheme.sea)
                        .padding(.horizontal, 12).frame(height: 44)
                        .background(Capsule().fill(CRTheme.cream.opacity(0.94)))
                }.buttonStyle(CRPressStyle())
            }
            Button { controller.activateArtifact() } label: {
                VStack(spacing: 4) {
                    Image(systemName: ability.symbol).font(.system(size: 22, weight: .semibold))
                    Text(active ? (controller.run.activeAbility == .shield ? "ARMED" : CRFormat.seconds(controller.run.abilityTime)) : ability.title.uppercased())
                        .font(CRTheme.label(9, .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 4) {
                        ForEach(0..<controller.run.maximumAbilityCharges, id: \.self) { index in
                            Circle().fill(index < controller.run.abilityCharges ? CRTheme.gold : CRTheme.ink.opacity(0.2)).frame(width: 5, height: 5)
                        }
                    }
                    if controller.run.abilityChargeCost > 1 && !active {
                        Text("\(controller.run.abilityChargeCost) CHARGES / USE").font(CRTheme.label(7, .bold)).foregroundColor(CRTheme.gold)
                    }
                }.foregroundColor(active ? CRTheme.cream : CRTheme.ink)
                    .frame(width: 96, height: 76)
                    .background(RoundedRectangle(cornerRadius: 12).fill(active ? CRTheme.sea : CRTheme.cream.opacity(0.94)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(CRTheme.sea.opacity(0.6), lineWidth: 1))
            }.buttonStyle(CRPressStyle()).disabled(!available).opacity(available || active ? 1 : 0.5)
                .accessibilityLabel("\(ability.title), \(controller.run.abilityCharges) charges")
                .accessibilityHint(available ? "Activate your artifact. Costs \(controller.run.abilityChargeCost) charge\(controller.run.abilityChargeCost == 1 ? "" : "s")." : "Recover a risky relic to earn a charge")
        }
    }
}

private struct CRGhostRaceRow: View {
    @ObservedObject var controller: GameController
    private var ghost: GhostReplay? {
        controller.profile.preferredGhost(forMode: controller.selectedMode, expert: controller.selectedExpert,
                                          startWorld: controller.selectedMode == .odyssey ? controller.selectedWorld : 0)
    }
    var body: some View {
        if controller.selectedMode == .odyssey && controller.selectedExpeditionStyle != .campaign {
            EmptyView()
        } else if let ghost {
            Button { controller.racePersonalGhost() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run").font(.system(size: 23, weight: .semibold)).foregroundColor(CRTheme.sea)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RACE YOUR GHOST").font(CRTheme.label(12, .heavy)).kerning(0.7)
                        Text("Same route · \(CRFormat.count(ghost.score)) points to beat")
                            .font(CRTheme.label(11, .medium)).foregroundColor(CRTheme.inkSoft())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                }.foregroundColor(CRTheme.ink).padding(.vertical, 14)
                    .overlay(alignment: .bottom) { Rectangle().fill(CRTheme.sea.opacity(0.25)).frame(height: 1) }
            }.buttonStyle(CRPressStyle()).disabled(controller.run.phase != .menu)
                .accessibilityHint("Starts the exact recorded seed, starting world and difficulty with your personal best ghost")
        } else {
            Text("Finish a run to save a personal ghost for this route and difficulty.")
                .font(CRTheme.label(11, .medium)).foregroundColor(CRTheme.inkSoft()).padding(.vertical, 7)
        }
    }
}

// MARK: Expedition decisions

private struct CRRouteChoice: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("CHOOSE YOUR ROUTE").kerning(1.3)
                Spacer()
                Text(CRFormat.seconds(controller.run.routeChoiceRemaining)).monospacedDigit()
            }.font(CRTheme.label(10, .heavy)).foregroundColor(CRTheme.ink)
            HStack(spacing: 8) {
                routeButton(.safe, symbol: "arrow.left", tint: CRTheme.sea)
                routeButton(.risky, symbol: "arrow.right", tint: CRTheme.gold)
            }
            Text("Choose before the fork. No choice takes the safe route.")
                .font(CRTheme.label(10, .medium)).foregroundColor(CRTheme.inkSoft(0.8))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(CRTheme.cream.opacity(0.96)))
    }

    private func routeButton(_ route: BranchRoute, symbol: String, tint: Color) -> some View {
        Button { controller.chooseRoute(route) } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: controller.run.branchRoute == route ? "checkmark.circle.fill" : symbol).font(.system(size: 15, weight: .heavy)).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(route.title(in: controller.run.worldStage)).font(CRTheme.label(12, .heavy))
                    Text(route.detail(in: controller.run.worldStage)).font(CRTheme.label(10, .medium)).opacity(0.85)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundColor(tint).padding(10).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(controller.run.branchRoute == route ? 0.24 : 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(CRPressStyle())
        .accessibilityLabel("Choose \(route.title(in: controller.run.worldStage)). \(route.detail(in: controller.run.worldStage))")
        .accessibilityAddTraits(controller.run.branchRoute == route ? .isSelected : [])
    }
}

private struct CRPerkSelection: View {
    @ObservedObject var controller: GameController

    var body: some View {
        if controller.run.canChoosePerk {
            VStack(alignment: .leading, spacing: 10) {
                Text("ONE UPGRADE / ONE TRADEOFF")
                    .font(CRTheme.label(10, .heavy)).kerning(1.4).foregroundColor(CRTheme.gold)
                Text("Choose a modifier for this expedition. You can also keep running without one.")
                    .font(CRTheme.label(12, .medium)).foregroundColor(CRTheme.inkSoft(0.85))
                ForEach(controller.run.availablePerks, id: \.rawValue) { perk in
                    Button { controller.choosePerk(perk) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: perk.symbol).font(.system(size: 22, weight: .semibold)).frame(width: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(perk.title).font(CRTheme.label(15, .bold))
                                Text(perk.detail).font(CRTheme.label(12, .medium)).foregroundColor(CRTheme.inkSoft(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "plus.circle").font(.system(size: 17, weight: .semibold))
                        }.foregroundColor(CRTheme.gold).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(CRTheme.creamEdge))
                    }.buttonStyle(CRPressStyle()).accessibilityLabel("Choose \(perk.title). \(perk.detail)")
                }
            }
        }
    }
}

private struct CRSelectedPerks: View {
    @ObservedObject var controller: GameController

    var body: some View {
        if !controller.run.selectedPerks.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("THIS RUN’S BUILD").font(CRTheme.label(10, .bold)).kerning(1.4).foregroundColor(CRTheme.sea)
                ForEach(controller.run.selectedPerks, id: \.rawValue) { perk in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(perk.title, systemImage: perk.symbol).font(CRTheme.label(12, .bold)).foregroundColor(CRTheme.gold)
                        Text(perk.detail).font(CRTheme.label(11, .medium)).foregroundColor(CRTheme.inkSoft(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CRRunObjectives: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(controller.run.objectiveStatus, id: \.id) { objective in
                HStack(spacing: 7) {
                    Image(systemName: objective.completed ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(objective.completed ? CRTheme.mint : CRTheme.inkSoft(0.4))
                    Text(objective.title).lineLimit(2)
                    Spacer(minLength: 3)
                    Text("\(min(objective.progress, objective.target))/\(objective.target)").monospacedDigit()
                }.font(CRTheme.label(11, .semibold)).foregroundColor(CRTheme.inkSoft(0.85))
                    .accessibilityElement(children: .combine)
            }
        }.padding(.vertical, 5)
    }
}

private struct CRSkillChallenges: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SKILL CONTRACTS").font(CRTheme.label(10, .heavy)).kerning(1.6).foregroundColor(CRTheme.sea)
            Text("Master a route, protect a clean run, and collect one-time rewards. Practice runs do not count.")
                .font(CRTheme.label(12, .medium)).foregroundColor(CRTheme.inkSoft())
            ForEach(controller.profile.skillChallenges) { challenge in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(challenge.title).font(CRTheme.label(15, .bold))
                            Text(challenge.detail).font(CRTheme.label(12, .medium)).foregroundColor(CRTheme.inkSoft(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if challenge.claimed {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(CRTheme.mint)
                                .accessibilityLabel("Reward claimed")
                        } else if challenge.complete {
                            Button { controller.claimSkillChallenge(challenge.id) } label: {
                                Text("+\(challenge.reward)").font(CRTheme.label(12, .bold)).foregroundColor(CRTheme.cream)
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .background(Capsule().fill(CRTheme.gold))
                            }.buttonStyle(CRPressStyle()).accessibilityLabel("Claim \(challenge.reward) coins for \(challenge.title)")
                        } else {
                            Text("\(min(challenge.progress, challenge.target))/\(challenge.target)")
                                .font(CRTheme.label(11, .bold)).foregroundColor(CRTheme.inkSoft()).monospacedDigit()
                        }
                    }
                    CRProgressBar(fraction: Double(challenge.progress) / Double(max(1, challenge.target)), tint: challenge.complete ? CRTheme.mint : CRTheme.sea)
                }.padding(.vertical, 10)
            }
        }.padding(.top, 18)
    }
}

// MARK: Local crash review

private struct CRCrashReplayOverlay: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("CRASH REPLAY", systemImage: "backward.end.fill")
                        .font(CRTheme.label(12, .heavy)).kerning(1.4).foregroundColor(CRTheme.sea)
                    Text(controller.run.crashReason).font(CRTheme.label(12, .medium)).foregroundColor(CRTheme.ink)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { controller.stopCrashReplay() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundColor(CRTheme.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(CRTheme.creamEdge))
                }.buttonStyle(CRPressStyle()).accessibilityLabel("Close crash replay")
            }.padding(16).background(RoundedRectangle(cornerRadius: 12).fill(CRTheme.cream.opacity(0.94)))
            Spacer(minLength: 20)
            VStack(spacing: 8) {
                HStack {
                    Text("\(String(format: "%.1f", max(0, (1 - controller.replayProgress) * controller.replayDuration)))s BEFORE IMPACT")
                    Spacer()
                    Text("DRAG TO REVIEW")
                }.font(CRTheme.label(10, .bold)).foregroundColor(CRTheme.inkSoft(0.85)).monospacedDigit()
                Slider(value: Binding(get: { controller.replayProgress }, set: controller.seekCrashReplay), in: 0...1)
                    .tint(CRTheme.sea).accessibilityLabel("Crash replay timeline")
                Button { controller.stopCrashReplay() } label: {
                    Text("Back to run options").font(CRTheme.label(13, .bold)).foregroundColor(CRTheme.sea)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(CRPressStyle())
            }.padding(16).background(RoundedRectangle(cornerRadius: 12).fill(CRTheme.cream.opacity(0.96)))
        }.padding(20)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
    }
}

private struct CRSwipeCalibration: View {
    let sensitivity: Double
    @State private var translation = CGSize.zero
    @State private var action = "SWIPE HERE TO TEST"
    @State private var recognized = false

    private var threshold: CGFloat {
        #if os(macOS)
        return CGFloat(28 / max(0.65, sensitivity))
        #else
        return CGFloat(24 / max(0.65, sensitivity))
        #endif
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(CRTheme.creamEdge)
                RoundedRectangle(cornerRadius: 8).strokeBorder(CRTheme.sea.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .frame(width: threshold * 2, height: threshold * 2)
                Circle().fill(recognized ? CRTheme.mint : CRTheme.sea).frame(width: 16, height: 16)
                    .offset(x: min(75, max(-75, translation.width)), y: min(28, max(-28, translation.height)))
            }.frame(height: 86).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        translation = value.translation
                        if max(abs(translation.width), abs(translation.height)) >= threshold {
                            recognized = true
                            if abs(translation.width) > abs(translation.height) {
                                action = translation.width < 0 ? "LEFT RECOGNIZED" : "RIGHT RECOGNIZED"
                            } else {
                                action = translation.height < 0 ? "JUMP RECOGNIZED" : "SLIDE RECOGNIZED"
                            }
                        }
                    }
                    .onEnded { _ in translation = .zero; recognized = false })
                .accessibilityLabel("Swipe calibration area")
                .accessibilityHint("Drag in any direction to test the current sensitivity without starting a run")
            Text(action).font(CRTheme.label(9, .bold)).kerning(1).foregroundColor(CRTheme.sea)
        }.padding(.top, 3)
    }
}
