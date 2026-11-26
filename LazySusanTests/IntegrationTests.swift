import XCTest

@testable import LazySusan

final class DynamicSourceTests: XCTestCase {
  func testParsesAnArrayOfItems() throws {
    let json = #"[{"key":"1","type":"command","label":"Mail","value":"cubicle go 1"}]"#
    let items = try DynamicSource.parse(Data(json.utf8)).get()
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items[0].item.displayName, "Mail")
  }

  func testParsesWrappedActions() throws {
    let json = #"{"actions":[{"type":"url","value":"https://example.com"}]}"#
    let items = try DynamicSource.parse(Data(json.utf8)).get()
    XCTAssertEqual(items.map(\.item.key), ["1"])
  }

  func testAssignsFreeKeysToItemsWithoutOne() throws {
    let json = #"""
      [{"type":"command","value":"a"},{"key":"1","type":"command","value":"b"},
       {"type":"command","value":"c"},{"type":"group","source":"x"}]
      """#
    let items = try DynamicSource.parse(Data(json.utf8)).get()
    XCTAssertEqual(items.map(\.item.key), ["2", "1", "3", "4"])
  }

  func testRejectsOutputThatIsNotItems() {
    guard case .failure(.invalidOutput) = DynamicSource.parse(Data("hello".utf8)) else {
      return XCTFail("expected invalidOutput")
    }
  }

  func testRunsTheSourceCommand() throws {
    let data = try DynamicSource.run(#"printf '[{"type":"command","value":"x"}]'"#).get()
    XCTAssertEqual(try DynamicSource.parse(data).get().count, 1)
  }

  func testReportsAFailingCommandWithItsFirstErrorLine() {
    let result = DynamicSource.run("echo 'no socket' >&2; echo more >&2; exit 3")
    XCTAssertEqual(result, .failure(.failed(status: 3, message: "no socket")))
  }

  func testStopsASlowCommand() {
    let started = Date()
    XCTAssertEqual(DynamicSource.run("sleep 10"), .failure(.timedOut))
    XCTAssertLessThan(Date().timeIntervalSince(started), DynamicSource.timeout + 2)
  }
}

final class DynamicGroupConfigTests: XCTestCase {
  func testSourceGroupRoundTripsWithoutSavingItsItems() throws {
    var group = Group(key: "s", label: "Switch", actions: [], source: "cubicle leader go")
    group.actions = [.action(Action(key: "1", type: .command, value: "cubicle go 1"))]

    let data = try JSONEncoder().encode(ActionOrGroup.group(group))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(json["source"] as? String, "cubicle leader go")
    XCTAssertEqual((json["actions"] as? [Any])?.count, 0)

    guard case .group(let decoded) = try JSONDecoder().decode(ActionOrGroup.self, from: data)
    else { return XCTFail("expected a group") }
    XCTAssertEqual(decoded.source, "cubicle leader go")
  }

  func testSourceGroupMayLeaveOutActions() throws {
    let json = #"{"key":"s","type":"group","source":"cubicle leader go"}"#
    guard case .group(let group) = try JSONDecoder().decode(ActionOrGroup.self, from: Data(json.utf8))
    else { return XCTFail("expected a group") }
    XCTAssertEqual(group.actions, [])
  }

  func testPlainGroupStillNeedsActions() {
    let json = #"{"key":"g","type":"group"}"#
    XCTAssertThrowsError(try JSONDecoder().decode(ActionOrGroup.self, from: Data(json.utf8)))
  }
}

final class GroupInstallerTests: XCTestCase {
  let cubicle = Group(key: "c", label: "Cubicle", actions: [])

  func root(_ items: ActionOrGroup...) -> Group {
    Group(key: nil, actions: items)
  }

  func testAddsWhenTheKeyIsFree() {
    let before = root(.action(Action(key: "t", type: .application, value: "/Terminal.app")))
    let plan = GroupInstaller.plan(installing: cubicle, into: before)
    XCTAssertEqual(plan, .add)
    XCTAssertEqual(GroupInstaller.apply(plan, installing: cubicle, into: before).actions.count, 2)
  }

  func testUpdatesAnEarlierCopyBySameLabel() {
    let old = Group(key: "c", label: "Cubicle", actions: [])
    let before = root(.group(old))
    var newer = cubicle
    newer.actions = [.action(Action(key: "g", type: .command, value: "x"))]

    let plan = GroupInstaller.plan(installing: newer, into: before)
    XCTAssertEqual(plan, .update(index: 0))
    let after = GroupInstaller.apply(plan, installing: newer, into: before)
    XCTAssertEqual(after.actions, [.group(newer)])
  }

  func testUpdateThatMovesKeyDropsTheClash() {
    let before = root(
      .group(Group(key: "c", label: "Cubicle", actions: [])),
      .action(Action(key: "w", type: .command, value: "y")))
    var moved = cubicle
    moved.key = "w"
    let plan = GroupInstaller.plan(installing: moved, into: before)
    let after = GroupInstaller.apply(plan, installing: moved, into: before)
    XCTAssertEqual(after.actions.map(\.item.key), ["w"])
  }

  func testConflictsWhenSomethingElseHasTheKey() {
    let before = root(.group(Group(key: "c", label: "Calendar", actions: [])))
    XCTAssertEqual(GroupInstaller.plan(installing: cubicle, into: before), .conflict(index: 0))
  }

  func testReadsAGroupFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "install-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try #"{"key":"c","type":"group","label":"Cubicle","actions":[{"key":"s","type":"group","source":"x"}]}"#
      .write(to: url, atomically: true, encoding: .utf8)
    let group = try GroupInstaller.read(url)
    XCTAssertEqual(group.label, "Cubicle")
  }

  func testRefusesAGroupWithoutAKey() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "install-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try #"{"type":"group","label":"Cubicle","actions":[]}"#
      .write(to: url, atomically: true, encoding: .utf8)
    XCTAssertThrowsError(try GroupInstaller.read(url)) { error in
      XCTAssertEqual(error as? GroupInstaller.InstallError, .missingKey)
    }
  }

  func testParsesTheInstallURL() {
    let url = URL(string: "lazysusan://install?file=%2Ftmp%2Fcubicle%20group.json")!
    XCTAssertEqual(
      URLSchemeHandler.parse(url), .install(file: URL(fileURLWithPath: "/tmp/cubicle group.json")))
    XCTAssertEqual(
      URLSchemeHandler.parse(URL(string: "lazysusan://install?file=relative.json")!), .show)
  }
}
