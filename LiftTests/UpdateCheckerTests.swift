import XCTest
@testable import Lift

final class SemanticVersionTests: XCTestCase {
    func testDetectsNewerPatchAndMinorVersions() {
        XCTAssertTrue(SemanticVersion.isNewer("1.1", than: "1.0"))
        XCTAssertTrue(SemanticVersion.isNewer("1.0.1", than: "1.0"))
        XCTAssertTrue(SemanticVersion.isNewer("2.0", than: "1.9.9"))
    }

    func testEqualVersionsAreNotNewer() {
        XCTAssertFalse(SemanticVersion.isNewer("1.0", than: "1.0"))
        XCTAssertFalse(SemanticVersion.isNewer("1.0.0", than: "1.0"))
    }

    func testOlderVersionsAreNotNewer() {
        XCTAssertFalse(SemanticVersion.isNewer("1.0", than: "1.1"))
        XCTAssertFalse(SemanticVersion.isNewer("1.9.9", than: "2.0"))
    }

    func testComparesNumericallyNotLexically() {
        XCTAssertTrue(SemanticVersion.isNewer("1.10", than: "1.9"))
        XCTAssertFalse(SemanticVersion.isNewer("1.9", than: "1.10"))
    }

    func testIgnoresTagPrefix() {
        XCTAssertTrue(SemanticVersion.isNewer("v1.1", than: "1.0"))
        XCTAssertFalse(SemanticVersion.isNewer("v1.0", than: "1.0"))
    }

    func testMalformedInputIsNotTreatedAsNewer() {
        XCTAssertFalse(SemanticVersion.isNewer("", than: "1.0"))
        XCTAssertFalse(SemanticVersion.isNewer("bozuk", than: "1.0"))
    }
}

private final class MockReleaseFetcher: ReleaseFetching {
    var tag: String?
    private(set) var fetchCount = 0

    func fetchLatestVersion(completion: @escaping (String?) -> Void) {
        fetchCount += 1
        completion(tag)
    }
}

final class UpdateCheckerTests: XCTestCase {
    private var fetcher: MockReleaseFetcher!
    private var checker: UpdateChecker!

    override func setUp() {
        super.setUp()
        fetcher = MockReleaseFetcher()
        checker = UpdateChecker(currentVersion: "1.0", fetcher: fetcher)
    }

    private func check(expecting description: String) -> String?? {
        let done = expectation(description: description)
        var result: String??
        checker.onResult = { version in
            result = version
            done.fulfill()
        }
        checker.check()
        wait(for: [done], timeout: 1)
        return result
    }

    func testReportsNewerRelease() {
        fetcher.tag = "v1.2"
        XCTAssertEqual(check(expecting: "yeni sürüm"), "v1.2")
        XCTAssertEqual(checker.availableVersion, "v1.2")
    }

    func testReportsNothingWhenUpToDate() {
        fetcher.tag = "v1.0"
        XCTAssertEqual(check(expecting: "güncel"), .some(nil))
        XCTAssertNil(checker.availableVersion)
    }

    func testReportsNothingWhenReleaseIsOlder() {
        fetcher.tag = "v0.9"
        XCTAssertEqual(check(expecting: "eski sürüm"), .some(nil))
    }

    func testNetworkFailureIsNotReportedAsUpdate() {
        fetcher.tag = nil
        XCTAssertEqual(check(expecting: "ağ hatası"), .some(nil))
        XCTAssertNil(checker.availableVersion)
    }
}
