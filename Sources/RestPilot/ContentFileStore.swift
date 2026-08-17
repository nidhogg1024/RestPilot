import AppKit
import Foundation

enum ContentFileStore {
    @MainActor
    static func chooseAndCopyImage() -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择休息提示图片"
        panel.allowedContentTypes = [.png, .jpeg, .gif, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return nil }
        return copyImage(at: source)
    }

    static func copyImage(at source: URL) -> String? {
        let manager = FileManager.default
        guard let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = support.appendingPathComponent("RestPilot/BreakContent", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(UUID().uuidString).\(source.pathExtension)")
        do {
            try manager.copyItem(at: source, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }

    @MainActor
    static func chooseAndCopyBackground() -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择全屏休息背景"
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return nil }
        return copyBackground(at: source)
    }

    static func copyBackground(at source: URL) -> String? {
        let manager = FileManager.default
        guard let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = support.appendingPathComponent("RestPilot/Backgrounds", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension
        let destination = directory.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
        do {
            try manager.copyItem(at: source, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }
}
