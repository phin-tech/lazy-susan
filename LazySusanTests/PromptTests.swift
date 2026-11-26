import XCTest

@testable import LazySusan

final class PromptTests: XCTestCase {
  func testOnlyCommandsAndURLsWithPlaceholderNeedInput() {
    XCTAssertTrue(
      ActionInput.needsInput(Action(key: "r", type: .command, value: "cubicle rename {input}")))
    XCTAssertTrue(
      ActionInput.needsInput(Action(key: "s", type: .url, value: "https://duckduckgo.com/?q={input}")))
    XCTAssertFalse(ActionInput.needsInput(Action(key: "g", type: .command, value: "cubicle grid")))
    XCTAssertFalse(
      ActionInput.needsInput(Action(key: "f", type: .folder, value: "~/{input}")))
  }

  func testCommandGetsInputThroughEnvironment() {
    let action = Action(key: "r", type: .command, value: "cubicle rename {input}")
    let (filled, environment) = ActionInput.fill(action, with: "Mail")
    XCTAssertEqual(filled.value, "cubicle rename \"$LAZYSUSAN_INPUT\"")
    XCTAssertEqual(environment, ["LAZYSUSAN_INPUT": "Mail"])
  }

  func testCommandInputIsNeverParsedAsShellSyntax() throws {
    let hostile = "a b; touch /tmp/pwned $(whoami) `id` \"q\" 'r' \\ *"
    let (filled, environment) = ActionInput.fill(
      Action(key: "e", type: .command, value: "printf %s {input}"), with: hostile)

    for shell in ["/bin/sh", "/bin/zsh", "/bin/bash"] {
      let task = Process()
      let pipe = Pipe()
      task.executableURL = URL(fileURLWithPath: shell)
      task.arguments = ["-c", filled.value]
      task.environment = environment
      task.standardOutput = pipe
      try task.run()
      task.waitUntilExit()
      let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
      XCTAssertEqual(output, hostile, shell)
    }
  }

  func testURLInputIsPercentEncoded() {
    let action = Action(key: "s", type: .url, value: "https://duckduckgo.com/?q={input}")
    let (filled, environment) = ActionInput.fill(action, with: "a&b c/d?é")
    XCTAssertEqual(filled.value, "https://duckduckgo.com/?q=a%26b%20c%2Fd%3F%C3%A9")
    XCTAssertTrue(environment.isEmpty)
  }

  func testDropLastWord() {
    XCTAssertEqual(Controller.dropLastWord("rename my space  "), "rename my ")
    XCTAssertEqual(Controller.dropLastWord("one"), "")
    XCTAssertEqual(Controller.dropLastWord(""), "")
  }
}
