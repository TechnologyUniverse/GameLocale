import Sparkle
import SwiftUI

private enum LibraryGame { case ghostExile, phasmophobia }
private enum LibrarySection: String, CaseIterable {
    case library = "Библиотека"
    case updates = "Обновления"
    case settings = "Настройки"

    var icon: String {
        switch self {
        case .library: "square.grid.2x2"
        case .updates: "arrow.triangle.2.circlepath"
        case .settings: "gearshape"
        }
    }
}

struct GameLibraryView: View {
    let updater: SPUUpdater
    @State private var game: LibraryGame = .phasmophobia
    @State private var section: LibrarySection = .library
    @State private var ghostBusy = false
    @State private var voiceBusy = false
    private var busy: Bool { ghostBusy || voiceBusy }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 18) {
                header
                switch section {
                case .library:
                    HStack(spacing: 16) {
                        gameButton(.ghostExile)
                            .keyboardShortcut("1", modifiers: .command)
                        gameButton(.phasmophobia)
                            .keyboardShortcut("2", modifiers: .command)
                    }
                    ZStack(alignment: .topLeading) {
                        ContentView(onBusyChange: { ghostBusy = $0 })
                            .opacity(game == .ghostExile ? 1 : 0)
                            .allowsHitTesting(game == .ghostExile)
                            .accessibilityHidden(game != .ghostExile)
                        PhasmophobiaVoiceView(isActive: game == .phasmophobia,
                                              onBusyChange: { voiceBusy = $0 })
                            .opacity(game == .phasmophobia ? 1 : 0)
                            .allowsHitTesting(game == .phasmophobia)
                            .accessibilityHidden(game != .phasmophobia)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(GlassPanel())
                case .updates:
                    informationPanel(title: "Обновления", icon: "arrow.triangle.2.circlepath") {
                        Text("Game Locale 3.0").font(.title2.bold())
                        Text("Проверка новых версий приложения через Sparkle.")
                            .foregroundStyle(.secondary)
                        CheckForUpdatesButton(updater: updater)
                            .buttonStyle(.borderedProminent).tint(.cyan)
                        Text("Озвучка Phasmophobia имеет отдельную версию: 0.1 beta.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                case .settings:
                    informationPanel(title: "Настройки", icon: "gearshape") {
                        LabeledContent("Приложение", value: "Game Locale 3.0")
                        LabeledContent("Озвучка Phasmophobia", value: "0.1 · Бета")
                        LabeledContent("Автоматическая проверка обновлений", value: "Выключена")
                        Text("Папка игры выбирается в её панели в библиотеке. Перед изменением файлов закрой игру и выйди из Steam.")
                            .foregroundStyle(.secondary)
                        Label("Поддержка нативных игр — в планах", systemImage: "desktopcomputer")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .padding(14)
        .frame(minWidth: 1040, minHeight: 800)
        .background {
            ZStack {
                Color(red: 0.025, green: 0.055, blue: 0.095)
                LinearGradient(colors: [.blue.opacity(0.16), .clear, .orange.opacity(0.10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }.ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("GameLocaleLogo").resizable().scaledToFit()
                .frame(height: 90).padding(.top, 28).padding(.bottom, 18)
                .accessibilityLabel("Game Locale")
            ForEach(LibrarySection.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { section = item }
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 15, weight: section == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .background(section == item ? Color.cyan.opacity(0.16) : .clear,
                                    in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(section == item ? .cyan.opacity(0.5) : .clear)
                        }
                }
                .buttonStyle(.plain).disabled(busy)
            }
            Spacer()
            Divider().opacity(0.4)
            Text("Версия приложения 3.0").font(.caption).foregroundStyle(.secondary)
            Text("Technology Universe").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 180)
        .modifier(GlassPanel())
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(section == .library ? "Библиотека игр" : section.rawValue)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text("Русский язык и озвучка на Mac")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Image("TechnologyUniverse").resizable().scaledToFit()
                .frame(width: 180, height: 58)
                .accessibilityLabel("Technology Universe")
        }
        .padding(.bottom, 2)
    }

    private func gameButton(_ item: LibraryGame) -> some View {
        let ghost = item == .ghostExile
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { game = item }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 148)
                    .overlay {
                        Image(ghost ? "GhostHero" : "PhasmophobiaCard")
                            .resizable().scaledToFill().allowsHitTesting(false)
                    }
                    .clipped()
                    .overlay(alignment: .top) {
                        if !ghost {
                            Image("PhasmophobiaLogo").resizable().scaledToFit()
                                .frame(maxWidth: 320).padding(.horizontal, 20).padding(.top, 5)
                                .shadow(color: .black.opacity(0.9), radius: 6)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(ghost ? "Ghost Exile" : "Phasmophobia").font(.headline)
                        Spacer()
                        Image(systemName: game == item ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(game == item ? Color.cyan : Color.secondary)
                    }
                    Text(ghost ? "Русский интерфейс и ритуалы" : "Русская озвучка · 226 записей")
                        .font(.callout).foregroundStyle(.secondary)
                    Label(ghost ? "CrossOver · GameHub" : "0.1 · Бета",
                          systemImage: ghost ? "checkmark.shield" : "testtube.2")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ghost ? Color.mint : Color.orange)
                }.padding(16)
            }
            .background(.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(game == item ? .cyan.opacity(0.85) : .white.opacity(0.16),
                                  lineWidth: game == item ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain).disabled(busy)
        .accessibilityAddTraits(game == item ? .isSelected : [])
    }

    private func informationPanel<Content: View>(title: String, icon: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(title, systemImage: icon).font(.title2.bold())
            content()
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(GlassPanel())
    }
}

private struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.17))
                    .allowsHitTesting(false)
            }
    }
}
