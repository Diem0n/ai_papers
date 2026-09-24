//
//  JSONFile.swift
//  AIPapers
//
//  One Codable value in one JSON file in the App Group container — the same
//  approach DigestStore and PicksStore use, factored out for the newer stores
//  (code links, engineering insights, review cards) so each is a few lines.
//

import Foundation

nonisolated struct JSONFile<Value: Codable> {
    let name: String

    private var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedModelContainer.appGroupID)?
            .appendingPathComponent(name)
    }

    func load() -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.iso.decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let url, let data = try? JSONEncoder.iso.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension JSONEncoder {
    nonisolated static let iso: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    nonisolated static let iso: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
