import XCTest
@testable import AIPapers

final class QueryRouterTests: XCTestCase {
    func testSlashCommandsAlwaysWin() {
        XCTAssertEqual(QueryRouter.route("/explain kv cache"), .explain("kv cache"))
        XCTAssertEqual(QueryRouter.route("/ask what is new in rag"), .archive("what is new in rag"))
    }

    func testHeldOutQuestionsRouteCorrectly() {
        let accuracy = QueryRouter.accuracy(explain: RouteTrainingData.heldOutExplain, archive: RouteTrainingData.heldOutArchive)
        XCTAssertGreaterThanOrEqual(accuracy, 0.9)
    }
}

final class HuggingFaceTests: XCTestCase {
    func testFindsGithubLinkInAbstract() {
        XCTAssertEqual(HuggingFaceService.githubLink(in: "Code is at https://github.com/foo/bar-baz."), "https://github.com/foo/bar-baz")
        XCTAssertNil(HuggingFaceService.githubLink(in: "No link here, see github or gitlab.com/x/y"))
    }
}

@MainActor
final class ReviewScheduleTests: XCTestCase {
    func testRememberedCardsMoveThroughTheBoxes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ReviewStore.nextDue(box: 0, remembered: true, from: now).timeIntervalSince(now), 86_400)
        XCTAssertEqual(ReviewStore.nextDue(box: 3, remembered: true, from: now).timeIntervalSince(now), 16 * 86_400)
    }

    func testForgottenCardsComeBackSoon() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ReviewStore.nextDue(box: 4, remembered: false, from: now).timeIntervalSince(now), 600)
    }
}

final class DeduplicationTests: XCTestCase {
    private func paper(_ id: String) -> ArxivPaper {
        ArxivPaper(id: id, title: "t", authors: "a", abstractText: "x", url: "u", publishedAt: .now, primaryCategory: nil)
    }

    func testSkipsPapersAlreadyStored() {
        let result = DeduplicationService.filterNewPapers([paper("arXiv:1"), paper("arXiv:2")], existingIDs: ["arXiv:1"])
        XCTAssertEqual(result.map(\.id), ["arXiv:2"])
    }
}

final class RelevanceTests: XCTestCase {
    func testScoreStaysInRangeAndPrefersOnTopicPapers() {
        let now = Date.now
        let onTopic = RelevanceService.score(title: "Efficient LLM inference with RAG agents", abstractText: "retrieval and fine-tuning for agents", publishedAt: now, referenceDate: now)
        let offTopic = RelevanceService.score(title: "Bird migration patterns", abstractText: "ornithology field study", publishedAt: now, referenceDate: now)
        XCTAssertGreaterThan(onTopic, offTopic)
        XCTAssertTrue((0...1).contains(onTopic) && (0...1).contains(offTopic))
    }

    func testLLMRelevanceIsClampedAndMinorityWeighted() {
        let now = Date.now
        let base = RelevanceService.score(title: "x", abstractText: "y", publishedAt: now, referenceDate: now)
        let boosted = RelevanceService.score(title: "x", abstractText: "y", publishedAt: now, llmRelevance: 99, referenceDate: now)
        XCTAssertLessThanOrEqual(boosted, 1)
        XCTAssertLessThan(boosted - base, 0.35)
    }
}

/// arXiv feed parsing, through the real service with a canned response.
final class ArxivParsingTests: XCTestCase {
    final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var body = Data()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func testParsesEntryFields() async throws {
        StubProtocol.body = Data("""
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>http://arxiv.org/abs/2609.12345v1</id>
            <published>2026-09-23T05:08:41Z</published>
            <title>A Paper
              Title</title>
            <summary>An abstract.</summary>
            <author><name>Ada Lovelace</name></author>
            <author><name>Alan Turing</name></author>
            <category term="cs.LG"/>
          </entry>
        </feed>
        """.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let papers = try await ArxivService(session: URLSession(configuration: configuration)).fetchRecentPapers(maxResults: 1)
        XCTAssertEqual(papers.count, 1)
        XCTAssertEqual(papers[0].id, "arXiv:2609.12345")
        XCTAssertEqual(papers[0].authors, "Ada Lovelace, Alan Turing")
        XCTAssertFalse(papers[0].title.contains("\n"))
    }

    func testMalformedFeedThrowsInsteadOfCrashing() async {
        StubProtocol.body = Data("<feed><entry>".utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        do {
            _ = try await ArxivService(session: URLSession(configuration: configuration)).fetchRecentPapers(maxResults: 1)
            XCTFail("expected a parsing error")
        } catch {}
    }
}
