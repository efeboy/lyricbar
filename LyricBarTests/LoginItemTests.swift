import Testing
import Foundation
@testable import LyricBar

@Suite("Login item location")
struct LoginItemTests {

    @Test("A real install location can register", arguments: [
        "/Applications/LyricBar.app",
        "/Users/someone/Applications/LyricBar.app",
        "/Applications/Utilities/LyricBar.app",
    ])
    func stableLocations(path: String) {
        #expect(LoginItem.isStableLocation(URL(filePath: path)))
    }

    @Test("A build output cannot, however it was produced", arguments: [
        "/Users/someone/Library/Developer/Xcode/DerivedData/LyricBar-abc/Build/Products/Debug/LyricBar.app",
        "/Users/someone/code/lyricbar/build/Build/Products/Release/LyricBar.app",
        "/tmp/scratch/Build/Products/Release/LyricBar.app",
    ])
    func buildOutputs(path: String) {
        #expect(!LoginItem.isStableLocation(URL(filePath: path)))
    }

    @Test("The test host is itself a build output, so the toggle is off here")
    func testHostIsUnsupported() {
        #expect(!LoginItem.isSupported)
    }
}
