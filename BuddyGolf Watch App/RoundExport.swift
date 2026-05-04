import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct RoundExport: Codable, Transferable {
    let exportedAt: Date
    let note: String
    let ownerEmail: String?
    let course: ExportCourse
    let round: ExportRound

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            try export.jsonData()
        }

        FileRepresentation(exportedContentType: .json) { export in
            SentTransferredFile(try export.writeJSONFile())
        }
    }

    var suggestedFilename: String {
        let courseName = course.name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return "\(courseName.isEmpty ? "bogey-round" : courseName)-round.json"
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    private func writeJSONFile() throws -> URL {
        let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BogeyExports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let fileURL = exportDirectory.appendingPathComponent(suggestedFilename)
        try jsonData().write(to: fileURL, options: [.atomic])
        return fileURL
    }

    struct ExportCourse: Codable {
        let id: UUID
        let name: String
        let holes: [ExportHole]
    }

    struct ExportHole: Codable {
        let holeNumber: Int
        let par: Int
        let greenLatitude: Double
        let greenLongitude: Double
    }

    struct ExportRound: Codable {
        let id: UUID
        let startedAt: Date
        let currentHoleNumber: Int
        let playerCount: Int
        let teamSetup: String
        let scoringMode: String
        let scoreBasis: String
        let players: [ExportPlayer]
        let holeStates: [ExportHoleState]
    }

    struct ExportPlayer: Codable {
        let index: Int
        let displayName: String
        let handicap: Int?
    }

    struct ExportHoleState: Codable {
        let holeNumber: Int
        let playerScores: [Int]
        let myShotPoints: [ShotPoint]
    }
}
