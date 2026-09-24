//
//  HuggingFaceService.swift
//  AIPapers
//
//  Hugging Face as a second source and as the code/weights index. Papers with
//  Code was shut down in July 2025 and its paper→repository links now live in
//  Hugging Face's paper pages, so one API covers both:
//
//    /api/daily_papers        — the community's daily picks (all arXiv papers)
//    /api/papers/<arxiv id>   — GitHub repo + stars, linked models/datasets, upvotes
//
//  Public, unauthenticated, read-only. Like ArxivService it never touches
//  SwiftData — it returns plain values for PaperService to store.
//

import Foundation

nonisolated struct CodeLinks: Codable, Equatable, Sendable {
    var githubRepo: String?
    var githubStars: Int?
    var models: Int
    var datasets: Int
    var upvotes: Int?
    var fetchedAt: Date

    var hasCode: Bool { githubRepo != nil }
    var hasWeights: Bool { models > 0 }
    static func none(at date: Date = .now) -> CodeLinks { CodeLinks(models: 0, datasets: 0, fetchedAt: date) }
}

nonisolated struct HFDailyPaper: Sendable {
    let paper: ArxivPaper
    let links: CodeLinks
}

nonisolated enum HuggingFaceError: Error {
    case unavailable
}

nonisolated final class HuggingFaceService {
    private let session: URLSession
    private let base = URL(string: "https://huggingface.co/api")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// The daily papers list for one day (UTC date, as the site uses).
    func dailyPapers(on date: Date, limit: Int = 50) async throws -> [HFDailyPaper] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        var components = URLComponents(url: base.appendingPathComponent("daily_papers"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "date", value: formatter.string(from: date)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let data = try await get(components.url!)
        let entries = try JSONDecoder().decode([DailyEntry].self, from: data)
        return entries.compactMap { Self.convert($0.paper) }
    }

    /// Code and weights for one arXiv paper; `.none` when Hugging Face has no page for it.
    func links(for arxivID: String) async throws -> CodeLinks {
        let id = arxivID.replacingOccurrences(of: "arXiv:", with: "")
        let (data, response) = try await session.data(for: request(base.appendingPathComponent("papers/\(id)")))
        guard let http = response as? HTTPURLResponse else { throw HuggingFaceError.unavailable }
        if http.statusCode == 404 { return .none() }
        guard (200..<300).contains(http.statusCode) else { throw HuggingFaceError.unavailable }
        let paper = try JSONDecoder().decode(PaperJSON.self, from: data)
        return Self.links(from: paper)
    }

    /// A GitHub link written into the abstract itself — works for papers
    /// Hugging Face hasn't indexed yet.
    static func githubLink(in abstract: String) -> String? {
        let pattern = #"https?://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"#
        guard let range = abstract.range(of: pattern, options: .regularExpression) else { return nil }
        return String(abstract[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)"))
    }

    // MARK: Decoding

    private struct DailyEntry: Decodable { let paper: PaperJSON }

    private struct PaperJSON: Decodable {
        struct Author: Decodable { let name: String? }
        let id: String
        let title: String?
        let summary: String?
        let publishedAt: String?
        let authors: [Author]?
        let upvotes: Int?
        let githubRepo: String?
        let githubStars: Int?
        let numTotalModels: Int?
        let numTotalDatasets: Int?
    }

    private static func links(from paper: PaperJSON) -> CodeLinks {
        CodeLinks(
            githubRepo: paper.githubRepo,
            githubStars: paper.githubStars,
            models: paper.numTotalModels ?? 0,
            datasets: paper.numTotalDatasets ?? 0,
            upvotes: paper.upvotes,
            fetchedAt: .now
        )
    }

    private static func convert(_ paper: PaperJSON) -> HFDailyPaper? {
        // Canonical metadata must be complete; skip anything that isn't.
        guard let title = paper.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let summary = paper.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty,
              paper.id.range(of: #"^\d{4}\.\d{4,5}$"#, options: .regularExpression) != nil else { return nil }
        let published = paper.publishedAt.flatMap { ISO8601DateFormatter.withFraction.date(from: $0) } ?? .now
        let authors = (paper.authors ?? []).compactMap(\.name).joined(separator: ", ")
        return HFDailyPaper(
            paper: ArxivPaper(
                id: "arXiv:\(paper.id)",
                title: title.replacingOccurrences(of: "\n", with: " "),
                authors: authors,
                abstractText: summary.replacingOccurrences(of: "\n", with: " "),
                url: "https://arxiv.org/abs/\(paper.id)",
                publishedAt: published,
                primaryCategory: nil
            ),
            links: links(from: paper)
        )
    }

    // MARK: HTTP

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("AIPapers/1.0 (personal research reader)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: request(url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw HuggingFaceError.unavailable }
        return data
    }
}

extension ISO8601DateFormatter {
    nonisolated static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
