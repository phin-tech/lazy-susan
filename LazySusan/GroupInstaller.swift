import Cocoa

/// `lazysusan://install?file=<path>`: another app adds a group of its own
/// commands to the top level of the config, after the user agrees
/// (see docs/integrations.md).
enum GroupInstaller {
  enum InstallError: LocalizedError, Equatable {
    case unreadable(String)
    case notAGroup
    case missingKey

    var errorDescription: String? {
      switch self {
      case .unreadable(let detail): return "The file couldn't be read: \(detail)"
      case .notAGroup: return "The file holds an action, not a group."
      case .missingKey: return "The group has no key."
      }
    }
  }

  /// What installing would do to the top level of the config.
  enum Plan: Equatable {
    /// The key is free.
    case add
    /// An earlier copy (a group with the same label) is at this index.
    case update(index: Int)
    /// Something else already uses the key, at this index.
    case conflict(index: Int)
  }

  static func read(_ url: URL) throws -> Group {
    let item: ActionOrGroup
    do {
      item = try JSONDecoder().decode(ActionOrGroup.self, from: Data(contentsOf: url))
    } catch {
      throw InstallError.unreadable(error.localizedDescription)
    }
    guard case .group(let group) = item else { throw InstallError.notAGroup }
    guard let key = group.key, !key.isEmpty else { throw InstallError.missingKey }
    return group
  }

  static func plan(installing group: Group, into root: Group) -> Plan {
    if let index = root.actions.firstIndex(where: { item in
      if case .group(let existing) = item {
        return existing.label != nil && existing.label == group.label
      }
      return false
    }) {
      return .update(index: index)
    }
    if let index = root.actions.firstIndex(where: { $0.item.key == group.key }) {
      return .conflict(index: index)
    }
    return .add
  }

  static func apply(_ plan: Plan, installing group: Group, into root: Group) -> Group {
    var root = root
    switch plan {
    case .add:
      root.actions.append(.group(group))
    case .update(let index), .conflict(let index):
      root.actions[index] = .group(group)
    }
    // An update may have moved to a key another item uses; drop that clash
    // rather than leave two items on one key.
    if case .update(let index) = plan,
      let clash = root.actions.indices.first(where: {
        $0 != index && root.actions[$0].item.key == group.key
      })
    {
      root.actions.remove(at: clash)
    }
    return root
  }

  /// Asks the user, then changes the config. Runs on the main thread.
  static func install(fileAt url: URL, into config: UserConfig) {
    NSApp.activate(ignoringOtherApps: true)

    let group: Group
    do {
      group = try read(url)
    } catch {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Couldn't add a group to Lazy Susan"
      alert.informativeText = error.localizedDescription
      alert.runModal()
      return
    }

    let plan = plan(installing: group, into: config.root)
    let name = group.displayName
    let key = KeyMaps.glyph(for: group.key ?? "") ?? group.key ?? ""
    let alert = NSAlert()
    switch plan {
    case .add:
      alert.messageText = "Add “\(name)” to Lazy Susan?"
      alert.informativeText = "It goes on key \(key), at the top level."
      alert.addButton(withTitle: "Add")
    case .update:
      alert.messageText = "Update “\(name)” in Lazy Susan?"
      alert.informativeText = "This replaces the copy you added before, on key \(key)."
      alert.addButton(withTitle: "Update")
    case .conflict(let index):
      let existing = config.root.actions[index].item.displayName
      alert.alertStyle = .warning
      alert.messageText = "Replace “\(existing)” with “\(name)”?"
      alert.informativeText = "“\(name)” wants key \(key), which “\(existing)” uses now."
      alert.addButton(withTitle: "Replace")
    }
    alert.addButton(withTitle: "Cancel")

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    config.root = apply(plan, installing: group, into: config.root)
  }
}
