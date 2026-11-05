import Foundation
import CryptoKit
import Darwin
import SwiftUI

private nonisolated struct DispatcherPackage: Decodable, Sendable {
    let build: String
    let clipCount: Int
    let resource: String
    let resourceSHA256: String
    let files: [AssetPatch]
    let audioResources: [AudioResource]?

    struct AudioResource: Decodable, Sendable {
        let name: String
        let sha256: String
    }

    struct AssetPatch: Decodable, Sendable {
        let asset: String
        let originalSHA256: String
        let patchedSHA256: String
        let previousPatchedSHA256: String?
        let compatiblePatchedSHA256s: [String]?
        let legacyBackupName: String?
        let patches: [ClipPatch]
    }

    struct ClipPatch: Decodable, Sendable {
        let offset: Int
        let originalBytes: Data
        let replacementBytes: Data
    }
}

private enum VoiceInstaller {
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case let .message(text) = self { return text }
            return nil
        }
    }

    nonisolated static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func processIsRunning(_ pattern: String) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-if", pattern]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus < 2 else {
            throw Failure.message("Не удалось проверить запущенные процессы.")
        }
        return process.terminationStatus == 0
    }

    nonisolated static func perform(folder: URL, resources: URL, restore: Bool) throws -> String {
        guard try !processIsRunning("[p]hasmophobia\\.exe|[s]team\\.exe") else {
            throw Failure.message("Закрой Phasmophobia и выйди из Steam, затем повтори.")
        }
        let fm = FileManager.default
        let package = try JSONDecoder().decode(DispatcherPackage.self,
            from: Data(contentsOf: resources.appendingPathComponent("dispatcher-package.json")))
        let dataFolder = folder.appendingPathComponent("Phasmophobia_Data")
        // Serialize operations across app windows and instances.
        let lockURL = dataFolder.appendingPathComponent(".gamelocale-voice.lock")
        let lockFD = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { throw Failure.message("Нет доступа к папке игры.") }
        defer { close(lockFD) }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            throw Failure.message("Другая установка озвучки ещё выполняется.")
        }
        defer { flock(lockFD, LOCK_UN) }

        var changes: [(url: URL, before: Data, after: Data)] = []
        for file in package.files {
            let asset = dataFolder.appendingPathComponent(file.asset)
            let current = try Data(contentsOf: asset)
            let digest = hash(current)
            guard digest == file.originalSHA256 || digest == file.patchedSHA256
                    || digest == file.previousPatchedSHA256
                    || file.compatiblePatchedSHA256s?.contains(digest) == true else {
                throw Failure.message("Файл \(file.asset) отличается от сборки Steam \(package.build). Применение остановлено.")
            }
            let backup = dataFolder.appendingPathComponent(".gamelocale-original-" + file.asset)
            let legacy = file.legacyBackupName.map { dataFolder.appendingPathComponent($0) }
            let original: Data
            if fm.fileExists(atPath: backup.path) {
                original = try Data(contentsOf: backup)
            } else if let legacy, fm.fileExists(atPath: legacy.path) {
                original = try Data(contentsOf: legacy)
            } else {
                guard digest == file.originalSHA256 else {
                    throw Failure.message("Для \(file.asset) отсутствует оригинальная резервная копия.")
                }
                original = current
            }
            guard hash(original) == file.originalSHA256 else {
                throw Failure.message("Резервная копия \(file.asset) не прошла проверку.")
            }
            var result = original
            if !restore {
                for clip in file.patches {
                    guard clip.offset >= 0, clip.offset <= result.count - clip.originalBytes.count,
                          clip.originalBytes.count == clip.replacementBytes.count,
                          result.subdata(in: clip.offset..<(clip.offset + clip.originalBytes.count)) == clip.originalBytes else {
                        throw Failure.message("Проверка AudioClip не пройдена.")
                    }
                    result.replaceSubrange(clip.offset..<(clip.offset + clip.originalBytes.count), with: clip.replacementBytes)
                }
                guard hash(result) == file.patchedSHA256 else {
                    throw Failure.message("Изменённый файл не прошёл проверку.")
                }
                if !fm.fileExists(atPath: backup.path) {
                    try original.write(to: backup, options: .atomic)
                }
            }
            if current != result { changes.append((asset, current, result)) }
        }

        if !restore {
            let banks = package.audioResources ?? [.init(name: package.resource, sha256: package.resourceSHA256)]
            // Check every bank before changing either resources or AudioClip metadata.
            let checked = try banks.map { bank -> (URL, Data) in
                guard bank.name == URL(fileURLWithPath: bank.name).lastPathComponent,
                      !bank.name.hasPrefix(".") else {
                    throw Failure.message("Некорректное имя аудиопакета.")
                }
                let audio = try Data(contentsOf: resources.appendingPathComponent(bank.name))
                guard hash(audio) == bank.sha256 else {
                    throw Failure.message("Аудиопакет не прошёл проверку целостности.")
                }
                let target = dataFolder.appendingPathComponent(bank.name)
                if fm.fileExists(atPath: target.path),
                   try hash(Data(contentsOf: target)) != bank.sha256 {
                    throw Failure.message("В папке игры находится другой пакет. Сначала верни оригинал.")
                }
                return (target, audio)
            }
            for (target, audio) in checked {
                try audio.write(to: target, options: .atomic)
            }
        }

        var written: [(url: URL, before: Data)] = []
        do {
            for change in changes {
                try change.after.write(to: change.url, options: .atomic)
                written.append((change.url, change.before))
            }
        } catch {
            var rollbackFailed = false
            for change in written.reversed() {
                do { try change.before.write(to: change.url, options: .atomic) }
                catch { rollbackFailed = true }
            }
            if rollbackFailed {
                throw Failure.message("Запись прервалась. Резервные копии сохранены. Повтори «Вернуть оригинал» перед запуском игры.")
            }
            throw error
        }
        return restore ? "Оригинальная озвучка восстановлена."
            : "Установлено \(package.clipCount) русских голосовых записей с эффектами. Перезапусти игру."
    }
}

struct PhasmophobiaVoiceView: View {
    var isActive = true
    var onBusyChange: (Bool) -> Void = { _ in }
    @State private var folder: URL?
    @State private var message = ""
    @State private var busy = false
    @State private var previewProcess: Process?
    @State private var previewPlaying = false

    private var resources: URL? {
        guard let root = Bundle.main.resourceURL else { return nil }
        return [root.appendingPathComponent("VoicePilot"), root].first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("dispatcher-package.json").path)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Phasmophobia").font(.system(size: 26, weight: .bold))
                        Text("Русская озвучка · 226 записей с эффектами")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(PhasmophobiaVoiceRelease.status)
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
                HStack(spacing: 8) {
                    voiceChip("Диктор", icon: "mic")
                    voiceChip("Spirit Box", icon: "antenna.radiowaves.left.and.right")
                    voiceChip("Шёпот", icon: "waveform")
                    voiceChip("Игровые объекты", icon: "cube")
                }
                HStack(spacing: 12) {
                    Label("Установка", systemImage: "externaldrive").foregroundStyle(.secondary)
                    Button(folderTitle, systemImage: "folder", action: select)
                        .buttonStyle(.bordered).disabled(busy)
                    Spacer(minLength: 0)
                    Label("Оригиналы сохраняются", systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let folder {
                    Text(folder.path).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(folder.path)
                }
                HStack(spacing: 12) {
                    Button("Установить озвучку", systemImage: "arrow.down.to.line") {
                        Task { await install(restore: false) }
                    }
                    .buttonStyle(.borderedProminent).tint(.cyan)
                    .disabled(folder == nil || resources == nil || busy)
                    Button("Вернуть оригинал", systemImage: "arrow.uturn.backward") {
                        Task { await install(restore: true) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(folder == nil || resources == nil || busy)
                    Spacer(minLength: 0)
                    Button(previewPlaying ? "Остановить" : "Послушать",
                           systemImage: previewPlaying ? "stop.fill" : "play.fill") {
                        if previewPlaying { stopPreview() } else { preview() }
                    }
                        .buttonStyle(.bordered).disabled(busy)
                }
                .controlSize(.large)
                if busy { ProgressView("Применяем пакет…") }
                if !message.isEmpty { Text(message).textSelection(.enabled).font(.callout) }
                Text("Закрой игру и выйди из Steam. Пакет 0.1 beta для сборки 25811160; 12 записей содержат атмосферную адаптацию. Новые реплики требуют проверки в игре.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }
        .onChange(of: busy) { _, value in onBusyChange(value) }
        .onChange(of: isActive) { _, active in if !active { stopPreview() } }
        .onDisappear(perform: stopPreview)
        .onAppear {
            let support = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
            let roots = [support.appendingPathComponent("CrossOver/Bottles"),
                         support.appendingPathComponent("com.gamemac.www/wine-engine/containers/virtual_containers")]
            for root in roots {
                let containers = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
                for container in containers {
                    let game = container.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common/Phasmophobia")
                    if FileManager.default.fileExists(atPath: game.appendingPathComponent("Phasmophobia.exe").path) {
                        folder = game
                        return
                    }
                }
            }
        }
    }

    private var folderTitle: String {
        guard let folder else { return "Выбрать папку игры…" }
        return folder.path.contains("/CrossOver/") ? "CrossOver · Steam" : "GameHub · Steam"
    }

    private func voiceChip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.caption)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }

    private func preview() {
        guard let resources else { message = "Аудиопакет отсутствует."; return }
        let file = resources.appendingPathComponent("dispatcher-preview.wav")
        guard FileManager.default.isReadableFile(atPath: file.path) else {
            message = "Файл примера озвучки отсутствует или недоступен. Переустанови приложение."
            return
        }
        stopPreview()
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        do {
            try process.run()
            previewProcess = process
            previewPlaying = true
            Task {
                let result = await Task.detached {
                    let diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    return (process.terminationStatus, String(decoding: diagnostic, as: UTF8.self))
                }.value
                guard previewProcess === process else { return }
                previewProcess = nil
                previewPlaying = false
                if result.0 != 0 {
                    message = "Не удалось воспроизвести пример. " + result.1
                }
            }
        } catch { message = error.localizedDescription }
    }

    private func stopPreview() {
        let process = previewProcess
        previewProcess = nil
        previewPlaying = false
        if let process, process.isRunning { process.terminate() }
    }

    private func select() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = folder
        FolderSheet.present(panel) { response in
            guard response == .OK, let selected = panel.url else { return }
            guard FileManager.default.fileExists(atPath: selected.appendingPathComponent("Phasmophobia.exe").path) else {
                message = "Выбери папку, в которой находится Phasmophobia.exe."
                return
            }
            folder = selected
            message = ""
        }
    }

    private func install(restore: Bool) async {
        guard let folder, let resources, !busy else { return }
        stopPreview()
        busy = true
        defer { busy = false }
        do {
            message = try await Task.detached {
                try VoiceInstaller.perform(folder: folder, resources: resources, restore: restore)
            }.value
        } catch { message = error.localizedDescription }
    }
}
