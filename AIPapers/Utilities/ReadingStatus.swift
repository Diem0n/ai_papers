//
//  ReadingStatus.swift
//  AIPapers
//
//  A deliberate reading workflow, separate from Paper.isRead (which is set
//  just by opening a paper). Stored on Paper as its raw string.
//

import Foundation

enum ReadingStatus: String, CaseIterable, Identifiable {
    case toRead = "To read"
    case reading = "Reading"
    case done = "Done"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .toRead: "bookmark"
        case .reading: "book"
        case .done: "checkmark.circle"
        }
    }
}

/// The lab notebook: did you try the idea, and did it hold up in your system?
enum TrialOutcome: String, CaseIterable, Identifiable {
    case planned = "Want to try"
    case trying = "Trying"
    case worked = "Worked"
    case failed = "Didn't work"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .planned: "flag"
        case .trying: "hammer"
        case .worked: "checkmark.seal"
        case .failed: "xmark.octagon"
        }
    }
}

extension Paper {
    var trial: TrialOutcome? {
        get { trialOutcome.flatMap(TrialOutcome.init(rawValue:)) }
        set { trialOutcome = newValue?.rawValue }
    }

    var status: ReadingStatus? {
        get { readingStatus.flatMap(ReadingStatus.init(rawValue:)) }
        set { readingStatus = newValue?.rawValue }
    }
}
