import Foundation
import Testing
import BlinkengraphsCore

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("history"), withIntermediateDirectories: true)
    try Data([1, 2, 3]).write(to: dir.appendingPathComponent("history/archives.bin"))
    return dir
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

@Test func aLoadThatFinishesLeavesHistoryInPlace() throws {
    let dir = try scratch(), history = dir.appendingPathComponent("history")
    let breaker = LoadBreaker(directory: history)
    for _ in 0..<5 {
        #expect(!breaker.begin())
        breaker.end()
    }
    #expect(exists(history.appendingPathComponent("archives.bin")))
}

@Test func oneUnfinishedLoadIsForgiven() throws {
    // A user can swipe the app away mid-load; that alone must not cost them their History.
    let dir = try scratch(), history = dir.appendingPathComponent("history")
    let breaker = LoadBreaker(directory: history)
    #expect(!breaker.begin())
    #expect(!breaker.begin())
    #expect(exists(history.appendingPathComponent("archives.bin")))
}

@Test func twoUnfinishedLoadsInARowSetHistoryAside() throws {
    let dir = try scratch(), history = dir.appendingPathComponent("history")
    let breaker = LoadBreaker(directory: history)
    _ = breaker.begin()
    _ = breaker.begin()
    #expect(breaker.begin())
    #expect(!exists(history))
    #expect(exists(dir.appendingPathComponent("history.unreadable/archives.bin")))
    // The fresh start loads normally, and a later trip replaces the copy set aside before.
    breaker.end()
    #expect(!breaker.begin())
}

@Test func aFinishedLoadResetsTheCount() throws {
    let dir = try scratch(), history = dir.appendingPathComponent("history")
    let breaker = LoadBreaker(directory: history)
    _ = breaker.begin()
    _ = breaker.begin()
    breaker.end()
    #expect(!breaker.begin())
    #expect(!breaker.begin())
    #expect(exists(history.appendingPathComponent("archives.bin")))
}

@Test func aSecondTripReplacesTheCopySetAsideBefore() throws {
    let dir = try scratch(), history = dir.appendingPathComponent("history")
    let breaker = LoadBreaker(directory: history)
    for _ in 0..<3 { _ = breaker.begin() }
    breaker.end()
    try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
    try Data([9]).write(to: history.appendingPathComponent("archives.bin"))
    for _ in 0..<2 { _ = breaker.begin() }
    #expect(breaker.begin())
    #expect(try Data(contentsOf: dir.appendingPathComponent("history.unreadable/archives.bin")) == Data([9]))
}
