import Foundation

/// Fills dynamic groups: runs a group's `source` command and reads its output
/// as items (see docs/integrations.md).
enum DynamicSource {
  static let timeout: TimeInterval = 3

  enum Failure: Error, Equatable {
    case timedOut
    case failed(status: Int32, message: String)
    case invalidOutput(String)

    var summary: String {
      switch self {
      case .timedOut: return "took longer than \(Int(DynamicSource.timeout)) seconds"
      case .failed(let status, let message):
        return message.isEmpty ? "exited with status \(status)" : message
      case .invalidOutput(let detail): return "printed something that isn't items: \(detail)"
      }
    }
  }

  /// Runs `source` off the main thread and calls back on the main thread.
  static func load(
    _ source: String, completion: @escaping (Result<[ActionOrGroup], Failure>) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let result = run(source).flatMap(parse)
      DispatchQueue.main.async { completion(result) }
    }
  }

  static func run(_ source: String) -> Result<Data, Failure> {
    let task = Process()
    let output = Pipe()
    let errors = Pipe()
    task.executableURL = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh")
    task.arguments = ["-c", source]
    task.standardOutput = output
    task.standardError = errors

    let finished = DispatchSemaphore(value: 0)
    task.terminationHandler = { _ in finished.signal() }
    do {
      try task.run()
    } catch {
      return .failure(.failed(status: -1, message: error.localizedDescription))
    }

    // Read while it runs, so a large output can't fill the pipe and stall it.
    var data = Data()
    let reader = DispatchQueue(label: "DynamicSource.read")
    reader.async { data = output.fileHandleForReading.readDataToEndOfFile() }

    if finished.wait(timeout: .now() + timeout) == .timedOut {
      task.terminate()
      return .failure(.timedOut)
    }
    reader.sync {}

    guard task.terminationStatus == 0 else {
      // The last line: a login shell (fish, say) may print its own startup
      // errors before the command's.
      let message =
        String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
      return .failure(.failed(status: task.terminationStatus, message: message))
    }
    return .success(data)
  }

  /// Accepts an array of items or `{ "actions": [...] }`.
  static func parse(_ data: Data) -> Result<[ActionOrGroup], Failure> {
    struct Wrapped: Decodable { let actions: [ActionOrGroup] }
    let decoder = JSONDecoder()
    do {
      if let items = try? decoder.decode([ActionOrGroup].self, from: data) {
        return .success(assignKeys(items))
      }
      return .success(assignKeys(try decoder.decode(Wrapped.self, from: data).actions))
    } catch {
      let text = String(data: data.prefix(80), encoding: .utf8) ?? ""
      return .failure(.invalidOutput(text.isEmpty ? "nothing" : text))
    }
  }

  static let keyOrder = Array("1234567890abcdefghijklmnopqrstuvwxyz").map(String.init)

  /// Gives items without a key the first free one from `keyOrder`.
  static func assignKeys(_ items: [ActionOrGroup]) -> [ActionOrGroup] {
    var used = Set(items.compactMap { $0.item.key }.filter { !$0.isEmpty })
    var free = keyOrder.filter { !used.contains($0) }.makeIterator()

    return items.map { item in
      guard (item.item.key ?? "").isEmpty, let key = free.next() else { return item }
      used.insert(key)
      switch item {
      case .action(var action):
        action.key = key
        return .action(action)
      case .group(var group):
        group.key = key
        return .group(group)
      }
    }
  }
}
