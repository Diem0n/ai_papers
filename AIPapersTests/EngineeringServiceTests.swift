import XCTest
@testable import AIPapers

/// The model's answers are untrusted: these check what survives validation.
final class EngineeringServiceTests: XCTestCase {
    // MARK: fit

    func testParseFitAcceptsValidVerdict() throws {
        let raw = #"{"verdict":"Applies","why":"Targets your reranker.","change":"Swap the scorer.","effort":"code"}"#
        let fit = try XCTUnwrap(EngineeringService.parseFit(raw, signature: "abc"))
        XCTAssertEqual(fit.verdict, .applies)
        XCTAssertEqual(fit.effort, .code)
        XCTAssertEqual(fit.stackSignature, "abc")
    }

    func testParseFitRejectsUnknownVerdictAndMissingReason() {
        XCTAssertNil(EngineeringService.parseFit(#"{"verdict":"definitely","why":"x"}"#, signature: ""))
        XCTAssertNil(EngineeringService.parseFit(#"{"verdict":"no","why":"  "}"#, signature: ""))
        XCTAssertNil(EngineeringService.parseFit("not json", signature: ""))
    }

    func testParseFitDefaultsUnknownEffortToCode() throws {
        let fit = try XCTUnwrap(EngineeringService.parseFit(#"{"verdict":"maybe","why":"adjacent","effort":"magic"}"#, signature: ""))
        XCTAssertEqual(fit.effort, .code)
    }

    // MARK: claims

    func testClaimsKeepOnlyNumbersFoundInTheAbstract() throws {
        let abstract = "Pass@32 increases from 59.9% to 66.2% with a 3x speedup on 1,024 GPUs."
        let raw = #"""
        {"claims":[
          {"claim":"Pass@32 rises to 66.2%","benchmark":"LiveCodeBench","metric":"Pass@32","value":"66.2%","baseline":"59.9%"},
          {"claim":"Pass@32 rises to 67.0%","benchmark":"LiveCodeBench","metric":"Pass@32","value":"67.0%","baseline":null},
          {"claim":"Scales to 1024 GPUs","benchmark":null,"metric":null,"value":null,"baseline":null}
        ]}
        """#
        let claims = try XCTUnwrap(EngineeringService.parseClaims(raw, abstract: abstract))
        XCTAssertEqual(claims.map(\.text), ["Pass@32 rises to 66.2%", "Scales to 1024 GPUs"])
        XCTAssertNil(claims[1].benchmark)
    }

    func testClaimsCappedAtFive() throws {
        let items = "abcdefgh".map { #"{"claim":"claim \#($0)"}"# }.joined(separator: ",")
        let claims = try XCTUnwrap(EngineeringService.parseClaims(#"{"claims":[\#(items)]}"#, abstract: ""))
        XCTAssertEqual(claims.count, 5)
    }

    func testNumbersIgnoreThousandsSeparators() {
        XCTAssertEqual(EngineeringService.numbers(in: "1,024 GPUs, 66.2%"), ["1024", "66.2"])
        XCTAssertEqual(EngineeringService.firstNumber("about 66.2% and 3x"), 66.2)
        XCTAssertNil(EngineeringService.firstNumber("no numbers"))
    }

    func testLowerIsBetterMetrics() {
        XCTAssertTrue(EngineeringService.lowerIsBetter("MAE"))
        XCTAssertTrue(EngineeringService.lowerIsBetter("p95 latency"))
        XCTAssertFalse(EngineeringService.lowerIsBetter("Accuracy"))
        XCTAssertFalse(EngineeringService.lowerIsBetter("Pass@32"))
    }

    // MARK: plan

    func testPlanNeedsAtLeastTwoSteps() {
        XCTAssertNil(EngineeringService.parsePlan(#"{"steps":[{"title":"Do it","detail":""}]}"#, usedFullText: false))
        let plan = EngineeringService.parsePlan(
            #"{"prerequisites":["GPU"],"steps":[{"title":"A","detail":"a"},{"title":"B","detail":"b"}],"success":"Beats baseline","risks":["OOM"]}"#,
            usedFullText: true)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.usedFullText, true)
        XCTAssertEqual(plan?.risks, ["OOM"])
    }

    // MARK: LaTeX inside JSON

    func testJSONDataKeepsLatexCommandsThatEscapesWouldEat() throws {
        // "\times" is a valid JSON escape (\t) followed by "imes"; it must survive as LaTeX.
        let raw = #"{"a": "V \times W_v and \frac{1}{2}", "b": "line1\nline2", "c": "\nabla f"}"#
        let decoded = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(EngineeringService.jsonData(raw)))
        XCTAssertEqual(decoded["a"], #"V \times W_v and \frac{1}{2}"#)
        XCTAssertEqual(decoded["b"], "line1\nline2")
        XCTAssertEqual(decoded["c"], #"\nabla f"#)
    }
}
