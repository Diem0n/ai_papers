//
//  ArxivService.swift
//  AIPapers
//
//  Fetches and parses papers from the arXiv API. Does not persist,
//  summarize, or touch SwiftUI — that belongs to other layers.
//

import Foundation

/// A paper as returned by arXiv, before it becomes a persisted `Paper`.
struct ArxivPaper: Sendable, Equatable {
    let id: String
    let title: String
    let authors: String
    let abstractText: String
    let url: String
    let publishedAt: Date
    let primaryCategory: String?
}

enum ArxivServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build the arXiv request."
        case .invalidResponse:
            return "arXiv did not return a valid response."
        case .parsingFailed:
            return "Could not parse the arXiv response."
        }
    }
}

nonisolated final class ArxivService {
    private let session: URLSession
    private let baseURL = URL(string: "https://export.arxiv.org/api/query")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRecentPapers(
        categories: [String] = AppConstants.arxivCategories,
        maxResults: Int = 50
    ) async throws -> [ArxivPaper] {
        let url = try buildQueryURL(categories: categories, maxResults: maxResults)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ArxivServiceError.invalidResponse
        }

        return try parse(data)
    }

    private func buildQueryURL(categories: [String], maxResults: Int) throws -> URL {
        let searchQuery = categories.map { "cat:\($0)" }.joined(separator: " OR ")

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "search_query", value: searchQuery),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "max_results", value: String(maxResults)),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending"),
        ]

        guard let url = components?.url else {
            throw ArxivServiceError.invalidURL
        }
        return url
    }

    private func parse(_ data: Data) throws -> [ArxivPaper] {
        let parser = ArxivAtomParser()
        return try parser.parse(data)
    }
}

/// SAX-style parser for the arXiv Atom feed. Kept private to ArxivService —
/// nothing outside this file needs to know the feed is Atom/XML.
private final class ArxivAtomParser: NSObject, XMLParserDelegate {
    private var papers: [ArxivPaper] = []

    private var currentElement = ""
    private var currentID = ""
    private var currentTitle = ""
    private var currentSummary = ""
    private var currentPublished = ""
    private var currentAuthors: [String] = []
    private var currentAuthorName = ""
    private var currentCategory: String?
    private var insideEntry = false

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func parse(_ data: Data) throws -> [ArxivPaper] {
        papers = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw ArxivServiceError.parsingFailed
        }
        return papers
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName

        if elementName == "entry" {
            insideEntry = true
            currentID = ""
            currentTitle = ""
            currentSummary = ""
            currentPublished = ""
            currentAuthors = []
            currentCategory = nil
        } else if elementName == "arxiv:primary_category", insideEntry {
            currentCategory = attributeDict["term"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideEntry else { return }
        switch currentElement {
        case "id":
            currentID += string
        case "title":
            currentTitle += string
        case "summary":
            currentSummary += string
        case "published":
            currentPublished += string
        case "name":
            currentAuthorName += string
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "name":
            let trimmed = currentAuthorName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                currentAuthors.append(trimmed)
            }
            currentAuthorName = ""
        case "entry":
            if let paper = makePaper() {
                papers.append(paper)
            }
            insideEntry = false
        default:
            break
        }
    }

    private func makePaper() -> ArxivPaper? {
        let absURL = currentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = arxivID(from: absURL) else { return nil }

        let title = currentTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let abstract = currentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let published = dateFormatter.date(from: currentPublished.trimmingCharacters(in: .whitespacesAndNewlines))

        guard !title.isEmpty, let publishedAt = published else { return nil }

        return ArxivPaper(
            id: id,
            title: title,
            authors: currentAuthors.joined(separator: ", "),
            abstractText: abstract,
            url: absURL,
            publishedAt: publishedAt,
            primaryCategory: currentCategory
        )
    }

    /// Extracts "2608.12345" from "http://arxiv.org/abs/2608.12345v1".
    private func arxivID(from absURL: String) -> String? {
        guard let lastComponent = absURL.split(separator: "/").last else { return nil }
        let withoutVersion = lastComponent.split(separator: "v").first.map(String.init) ?? String(lastComponent)
        return withoutVersion.isEmpty ? nil : "arXiv:\(withoutVersion)"
    }
}
