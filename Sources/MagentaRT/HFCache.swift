import Foundation

/// Resolves Magenta RealTime 2 assets cached by `huggingface_hub`
/// (`~/.cache/huggingface`), populated by `scripts/download-models.sh`.
///
/// Cache layout: `…/hub/models--google--magenta-realtime-2/snapshots/<sha>/…`
/// with the current `<sha>` recorded in `refs/main`.
public enum HFCache {
    public static let repo = "google/magenta-realtime-2"

    /// The resolved snapshot directory, or `nil` if nothing is cached.
    public static func snapshotDir(repo: String = repo) -> URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache/huggingface/hub/models--\(repo.replacingOccurrences(of: "/", with: "--"))")
        guard let sha = try? String(contentsOf: base.appending(path: "refs/main"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !sha.isEmpty else { return nil }
        let snap = base.appending(path: "snapshots/\(sha)")
        return FileManager.default.fileExists(atPath: snap.path) ? snap : nil
    }

    /// Path to `<model>.mlxfn`, or `nil` if not cached.
    public static func modelPath(_ name: String = "mrt2_small") -> String? {
        guard let snap = snapshotDir() else { return nil }
        let p = snap.appending(path: "models/\(name)/\(name).mlxfn")
        return FileManager.default.fileExists(atPath: p.path) ? p.path : nil
    }

    /// Path to the shared `resources/` directory, or `nil` if not cached.
    public static func resourcesPath() -> String? {
        guard let snap = snapshotDir() else { return nil }
        let p = snap.appending(path: "resources")
        return FileManager.default.fileExists(atPath: p.path) ? p.path : nil
    }
}
