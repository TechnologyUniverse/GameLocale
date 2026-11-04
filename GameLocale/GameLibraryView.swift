import SwiftUI

private enum GamePage {
    case ghostExile
    case phasmophobia
}

struct GameLibraryView: View {
    @State private var page: GamePage?

    var body: some View {
        VStack(spacing: 0) {
            if let page {
                navigationBar
                    .zIndex(1)
                Divider().opacity(0.3)
                switch page {
                case .ghostExile:
                    ContentView()
                case .phasmophobia:
                    PhasmophobiaVoiceView()
                }
            } else {
                library
            }
        }
        .frame(minWidth: 760, minHeight: 700)
        .background {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.15, blue: 0.20),
                         Color(red: 0.035, green: 0.045, blue: 0.065)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private var library: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Image("GameLocaleLogo")
                        .resizable().scaledToFit()
                        .frame(width: 350, height: 112)
                        .accessibilityLabel("Game Locale")
                    Text("Русификация игр на Mac · версия 3.0")
                        .font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                Image("TechnologyUniverse")
                    .resizable().scaledToFit()
                    .frame(width: 170, height: 62)
                    .accessibilityLabel("Technology Universe")
            }

            HStack(spacing: 8) {
                platform("Нативные игры", icon: "desktopcomputer")
                platform("CrossOver", icon: "square.stack.3d.up")
                platform("GameHub", icon: "gamecontroller")
            }
            Text("Выбери игру")
                .font(.title2.bold())
                .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                Button { page = .ghostExile } label: {
                    gameCard(
                        title: "Ghost Exile",
                        subtitle: "Русский интерфейс и реплики ритуалов",
                        status: "Доступно", available: true,
                        platforms: "CrossOver · GameHub", artName: "GhostHero"
                    )
                }
                .buttonStyle(.plain)

                Button { page = .phasmophobia } label: {
                    gameCard(
                        title: "Phasmophobia",
                        subtitle: "Русская озвучка",
                        status: "226 записей · мужской голос", available: true,
                        platforms: "Сборка Steam 25811160", artName: "PhasmophobiaCard",
                        details: ["Диктор · Spirit Box · параболический микрофон",
                                  "Куклы · гномы · радио · телевизор",
                                  "Установка озвучки и возврат оригинала"],
                        testing: true
                    )
                }
                .buttonStyle(.plain)
            }

            Label("Для каждой игры указаны проверенные способы запуска и доступные переводы.",
                  systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
            Divider().opacity(0.3)
            HStack {
                Text("Technology Universe").font(.caption.weight(.medium))
                Spacer()
                Text("Поддержка нативных игр — в планах")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(32)
        }
    }

    private func platform(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.06), in: Capsule())
    }

    private func gameCard(
        title: String, subtitle: String, status: String,
        available: Bool, platforms: String, artName: String,
        details: [String] = [], testing: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 180)
                .overlay {
                    Image(artName)
                        .resizable()
                        .scaledToFill()
                        .allowsHitTesting(false)
                }
                .clipped()
                .overlay(alignment: .top) {
                    if artName == "PhasmophobiaCard" {
                        Image("PhasmophobiaLogo")
                            .resizable().scaledToFit()
                            .frame(maxWidth: 340)
                            .padding(.horizontal, 18).padding(.top, 8)
                            .shadow(color: .black.opacity(0.9), radius: 6)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.title2.bold())
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                Label(status, systemImage: available ? "checkmark.circle.fill" : "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(available ? Color.mint : Color.secondary)
                if testing {
                    Label(PhasmophobiaVoiceRelease.status, systemImage: "testtube.2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                ForEach(details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if testing {
                    Text("Эффекты голоса включены. 12 записей содержат атмосферную адаптацию.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(platforms).font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
        }
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12))
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }

    private var navigationBar: some View {
        HStack {
            if #available(macOS 26, *) {
                backButton.buttonStyle(.glass)
            } else {
                backButton.buttonStyle(.bordered)
            }
            Spacer()
            Text("GameLocale").font(.headline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var backButton: some View {
        Button("Все игры", systemImage: "chevron.left") { page = nil }
            .keyboardShortcut("[", modifiers: .command)
    }

}
