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

extension Paper {
    var status: ReadingStatus? {
        get { readingStatus.flatMap(ReadingStatus.init(rawValue:)) }
        set { readingStatus = newValue?.rawValue }
    }
}
