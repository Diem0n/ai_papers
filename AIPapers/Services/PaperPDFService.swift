//
//  PaperPDFService.swift
//  AIPapers
//
//  Fetches a paper's full PDF from arXiv once, on demand, and keeps it on
//  disk so it opens instantly and offline afterwards. This is the only place
//  besides ArxivService that talks to arXiv, so offline mode gates it.
//

import Foundation

enum PaperPDFError: LocalizedError {
    case offline
    case unavailable
    case notAPDF

    var errorDescription: String? {
        switch self {
        case .offline: "You're offline and this paper hasn't been downloaded yet."
        case .unavailable: "arXiv didn't return the PDF. Try again in a moment."
        case .notAPDF: "The downloaded file wasn't a readable PDF."
        }
    }
}

enum PaperPDFService {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIPapers/PDFs", isDirectory: true)
    }

    /// "arXiv:2608.12345" → "2608.12345"; old-style ids contain a slash.
    private static func bareID(_ id: String) -> String {
        id.replacingOccurrences(of: "arXiv:", with: "")
    }

    static func localURL(for id: String) -> URL {
        folder.appendingPathComponent(bareID(id).replacingOccurrences(of: "/", with: "_") + ".pdf")
    }

    static func isDownloaded(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: id).path)
    }

    /// The saved PDF, downloading it first if needed.
    static func fetch(_ id: String) async throws -> URL {
        let destination = localURL(for: id)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        guard !NetworkStatus.shared.isOffline else { throw PaperPDFError.offline }

        guard let remote = URL(string: "https://arxiv.org/pdf/\(bareID(id))") else { throw PaperPDFError.unavailable }
        var request = URLRequest(url: remote)
        request.setValue("AIPapers/1.0 (personal research reader)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60

        let (temporary, response): (URL, URLResponse)
        do {
            (temporary, response) = try await URLSession.shared.download(for: request)
        } catch {
            throw PaperPDFError.unavailable
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PaperPDFError.unavailable }

        // arXiv sometimes answers with an HTML page instead; the file must start with "%PDF".
        let header = try FileHandle(forReadingFrom: temporary).read(upToCount: 4)
        guard header == Data("%PDF".utf8) else { throw PaperPDFError.notAPDF }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}
