//
//  Downloader.swift
//  MagentaRTDemo
//
//  Pure-Swift HuggingFace downloader for the in-app "Download" button — no
//  Python/uv needed. Fetches the file list from the HF tree API and downloads
//  the model + shared resources into Application Support, then hands back the
//  resolved model/resources paths.
//

import Foundation

@MainActor
@Observable
final class Downloader {
    var isDownloading = false
    var progress = 0.0
    var status = ""

    static let repo = "google/magenta-realtime-2"

    private struct Entry: Decodable { let path: String; let type: String }

    /// Where downloaded assets live (mirrors the repo's `resources/` + `models/`).
    static func destination() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "MagentaRTDemo/magenta-rt-v2")
        return base
    }

    /// Download `resources/*` and `models/<model>/*`. Returns (modelPath, resourcesPath).
    func download(model: String = "mrt2_small") async throws -> (model: String, resources: String) {
        isDownloading = true
        progress = 0
        defer { isDownloading = false }

        let dest = Self.destination()
        status = "Listing files…"
        var files = try await list(subpath: "resources")
        files += try await list(subpath: "models/\(model)")
        guard !files.isEmpty else {
            throw Err.message("No files found for \(model) in \(Self.repo).")
        }

        for (i, path) in files.enumerated() {
            progress = Double(i) / Double(files.count)
            let local = dest.appending(path: path)
            if FileManager.default.fileExists(atPath: local.path) { continue }  // resume-friendly
            status = "Downloading \(path)…"
            try FileManager.default.createDirectory(
                at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
            let src = URL(string: "https://huggingface.co/\(Self.repo)/resolve/main/\(path)")!
            let (tmp, response) = try await URLSession.shared.download(from: src)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw Err.message("HTTP \(http.statusCode) for \(path). If the repo is gated, set HF_TOKEN / `hf auth login`.")
            }
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.moveItem(at: tmp, to: local)
        }

        progress = 1
        status = "Done."
        return (dest.appending(path: "models/\(model)/\(model).mlxfn").path,
                dest.appending(path: "resources").path)
    }

    /// List file paths under `subpath` via the HF tree API (recursive).
    private func list(subpath: String) async throws -> [String] {
        let url = URL(string: "https://huggingface.co/api/models/\(Self.repo)/tree/main/\(subpath)?recursive=true")!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Err.message("HTTP \(http.statusCode) listing \(subpath).")
        }
        return try JSONDecoder().decode([Entry].self, from: data)
            .filter { $0.type == "file" }
            .map(\.path)
    }

    enum Err: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }
}
