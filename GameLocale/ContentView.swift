import Foundation
import SwiftUI
import UniformTypeIdentifiers

private struct Installation: Hashable, Sendable {
    let launcher: Launcher
    let folder: URL

    enum Launcher: String, CaseIterable, Sendable {
        case gamehub = "GameHub"
        case crossover = "CrossOver"

        var script: String {
            self == .gamehub ? "ghost_exile_ru_gamehub.sh" : "ghost_exile_ru_crossover.sh"
        }

        var pathOption: String { self == .gamehub ? "--container" : "--bottle" }

        var directory: URL {
            let support = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support")
            return support.appending(path: self == .gamehub
                ? "com.gamemac.www/wine-engine/containers/virtual_containers"
                : "CrossOver/Bottles")
        }
    }

    var title: String { "\(launcher.rawValue) · \(folder.lastPathComponent)" }

    nonisolated static func containsGame(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder
            .appending(path: "drive_c/Program Files (x86)/Steam/steamapps/appmanifest_1807080.acf").path)
    }

    static func discover() -> [Self] {
        Launcher.allCases.flatMap { launcher in
            let folders = (try? FileManager.default.contentsOfDirectory(
                at: launcher.directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            return folders.filter(containsGame).map { Self(launcher: launcher, folder: $0) }
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

private enum ScriptRunner {
    nonisolated static func run(_ executable: String, _ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

struct ContentView: View {
    @State private var installations: [Installation] = []
    @State private var selected: Installation?
    @State private var busy = false
    @State private var canApply = false
    @State private var report = ""
    @State private var notice = ""

    private var isRussian: Bool {
        report.contains("оба языка уже русские")
            && !report.contains("можно применить исправление")
            && !report.contains("неизвестный формат")
    }

    private var statusTitle: String {
        if busy { return "Проверяем установку…" }
        if selected == nil { return "Выбери установку" }
        if isRussian { return "Русский язык уже включён" }
        if canApply { return "Можно включить русский" }
        return "Проверь настройки игры"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    installationCard
                    statusCard
                }
                .padding(24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            footer
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.20, blue: 0.24), .black],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.white.opacity(0.13), lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 610, minHeight: 630)
        .onAppear(perform: discover)
        .task(id: selected) { await run(apply: false) }
    }

    private var header: some View {
        Color.clear
            .overlay {
                Image("GhostHero")
                    .resizable()
                    .scaledToFill()
                        .allowsHitTesting(false)
            }
                .clipped()
                .accessibilityHidden(true)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.88)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 85)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack {
                        Text("Русская локализация для macOS · GameHub и CrossOver")
                            .font(.callout.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("GameLocale 3.0")
                            .font(.caption.monospaced().weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                }
        .frame(height: 235)
        .background(.black)
    }

    private var installationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Установка игры", systemImage: "externaldrive")
                .font(.headline)
            if installations.isEmpty {
                Text("Игра не найдена автоматически. Выбери папку GameHub или CrossOver, в которой находится drive_c.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Лаунчер и контейнер", selection: $selected) {
                    ForEach(installations, id: \.self) { installation in
                        Text(installation.title).tag(Optional(installation))
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Лаунчер и контейнер")
            }
            installationActions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .disabled(busy)
    }

    @ViewBuilder
    private var installationActions: some View {
        if #available(macOS 26, *) {
            installationButtons
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
        } else {
            installationButtons
                .buttonStyle(.bordered)
        }
    }

    private var installationButtons: some View {
        HStack(spacing: 10) {
            Button("Найти снова", systemImage: "arrow.clockwise", action: discover)
            Menu("Выбрать папку…", systemImage: "folder") {
                ForEach(Installation.Launcher.allCases, id: \.self) { launcher in
                    Button(launcher.rawValue) { chooseFolder(for: launcher) }
                }
            }
            .fixedSize()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isRussian ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(isRussian ? Color.green : Color.secondary)
                        .accessibilityHidden(true)
                }
                Text(statusTitle).font(.headline)
            }
            let build = report.split(separator: "\n").first { $0.hasPrefix("Сборка Steam:") }
            if let build {
                Text(String(build)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if !notice.isEmpty {
                Label(notice, systemImage: "info.circle")
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            }
            if !report.isEmpty {
                DisclosureGroup("Подробности проверки") {
                    Text(report)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var footer: some View {
        if #available(macOS 26, *) {
            footerContent.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            footerContent.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private var footerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Перед применением закрой игру и Steam. Приложение сохранит резервную копию.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Image("TechnologyUniverse")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 46)
                    .padding(.horizontal, 8)
                    .background(Color(red: 0.05, green: 0.07, blue: 0.10),
                                in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Technology Universe")
                Spacer()
                if #available(macOS 26, *) {
                    checkButton.buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                    applyButton.buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .tint(Color(red: 0.16, green: 0.56, blue: 0.70))
                } else {
                    checkButton.buttonStyle(.bordered)
                    applyButton.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var checkButton: some View {
        Button("Проверить", systemImage: "arrow.clockwise") {
            Task { await run(apply: false) }
        }
        .disabled(selected == nil || busy)
    }

    private var applyButton: some View {
        Button("Включить русский", systemImage: "character.bubble") {
            Task { await run(apply: true) }
        }
        .disabled(!canApply || busy)
    }

    private func discover() {
        let previous = selected
        installations = Installation.discover()
        if let previous, installations.contains(previous) {
            Task { await run(apply: false) }
        } else {
            selected = installations.first
        }
    }

    private func chooseFolder(for launcher: Installation.Launcher) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = launcher.directory
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard Installation.containsGame(folder) else {
            notice = "В выбранной папке нет манифеста Ghost Exile. Выбери папку, в которой находится drive_c."
            return
        }
        let installation = Installation(launcher: launcher, folder: folder)
        if !installations.contains(installation) { installations.append(installation) }
        selected = installation
    }

    private func run(apply: Bool) async {
        guard let installation = selected else {
            report = ""
            notice = ""
            canApply = false
            return
        }
        guard !busy else { return }
        guard let resource = Bundle.main.resourceURL,
              let script = ["Scripts", ""].map({
                  resource.appending(path: $0).appending(path: installation.launcher.script)
              }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            notice = "В приложении отсутствуют скрипты."
            return
        }

        busy = true
        canApply = false
        notice = ""
        defer { busy = false }
        let arguments = [script.path, installation.launcher.pathOption, installation.folder.path]

        do {
            let result = try await Task.detached {
                if apply {
                    let game = try ScriptRunner.run("/usr/bin/pgrep", ["-if", "[g]hostexile\\.exe"])
                    guard game.0 == 1 else {
                        return (nil as String?, "Закрой Ghost Exile и повтори попытку.")
                    }
                    let steam = try ScriptRunner.run(
                        "/usr/bin/pgrep", ["-if", "[s]team\\.exe"]
                    )
                    if steam.0 == 0 {
                        return (nil as String?, "Steam ещё открыт. В меню Steam выбери «Выход», затем снова нажми «Включить русский».")
                    }
                    guard steam.0 == 1 else {
                        return (nil as String?, "Не удалось проверить, закрыт ли Steam. Закрой Steam и повтори попытку.")
                    }
                    let before = try ScriptRunner.run("/bin/bash", arguments + ["--check"])
                    guard before.0 == 0, before.1.contains("можно применить исправление"),
                          !before.1.contains("неизвестный формат") else {
                        return (before.1, "Настройки изменились. Проверь установку ещё раз.")
                    }
                    let applied = try ScriptRunner.run("/bin/bash", arguments)
                    if applied.0 != 0 { return (before.1, applied.1) }
                }
                let checked = try ScriptRunner.run("/bin/bash", arguments + ["--check"])
                let confirmed = checked.0 == 0 && checked.1.contains("оба языка уже русские")
                    && !checked.1.contains("можно применить исправление")
                    && !checked.1.contains("неизвестный формат")
                let message = checked.0 != 0 ? "Проверка завершилась с ошибкой."
                    : apply && confirmed ? "Русский включён. Теперь можно запустить игру."
                    : apply ? "Проверь результат ниже." : ""
                return (checked.1, message)
            }.value

            if let output = result.0 {
                report = output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            canApply = report.contains("можно применить исправление")
                && !report.contains("неизвестный формат")
            notice = result.1
        } catch {
            notice = error.localizedDescription
        }
    }
}
