import Cocoa
import Combine
import Defaults
import SwiftUI

enum KeyHelpers: UInt16 {
  case enter = 36
  case tab = 48
  case space = 49
  case backspace = 51
  case escape = 53
  case upArrow = 126
  case downArrow = 125
  case leftArrow = 123
  case rightArrow = 124
}

class Controller {
  var userState: UserState
  var userConfig: UserConfig

  var window: MainWindow!
  var cheatsheetWindow: NSWindow!
  var promptWindow: Prompt.Window!
  private var cheatsheetTimer: Timer?

  private var cancellables = Set<AnyCancellable>()

  init(userState: UserState, userConfig: UserConfig) {
    self.userState = userState
    self.userConfig = userConfig

    Task {
      for await value in Defaults.updates(.theme) {
        let windowClass = Theme.classFor(value)
        self.window = await windowClass.init(controller: self)
      }
    }

    Events.sink { event in
      switch event {
      case .didReload:
        // This should all be handled by the themes
        self.userState.isShowingRefreshState = true
        self.show()
        // Delay for 4 * 300ms to wait for animation to be noticeable
        delay(Int(Pulsate.singleDurationS * 1000) * 3) {
          self.hide()
          self.userState.isShowingRefreshState = false
        }
      default: break
      }
    }.store(in: &cancellables)

    self.cheatsheetWindow = Cheatsheet.createWindow(for: userState)
    self.promptWindow = Prompt.Window(userState: userState)
  }

  func show() {
    Events.send(.willActivate)

    let screen = Defaults[.screen].getNSScreen() ?? NSScreen()
    window.show(on: screen) {
      Events.send(.didActivate)
    }

    if !window.hasCheatsheet || userState.isShowingRefreshState {
      return
    }

    switch Defaults[.autoOpenCheatsheet] {
    case .always:
      showCheatsheet()
    case .delay:
      scheduleCheatsheet()
    default: break
    }
  }

  func hide(afterClose: (() -> Void)? = nil) {
    Events.send(.willDeactivate)

    window.hide {
      self.clear()
      afterClose?()
      Events.send(.didDeactivate)
    }

    cheatsheetWindow?.orderOut(nil)
    promptWindow?.orderOut(nil)
    cheatsheetTimer?.invalidate()
  }

  func keyDown(with event: NSEvent) {
    // Reset the delay timer
    if Defaults[.autoOpenCheatsheet] == .delay {
      scheduleCheatsheet()
    }

    if userState.prompt != nil, handlePromptKey(event) {
      return
    }

    if event.modifierFlags.contains(.command) {
      switch event.charactersIgnoringModifiers {
      case ",":
        NSApp.sendAction(
          #selector(AppDelegate.settingsMenuItemActionHandler(_:)), to: nil,
          from: nil)
        hide()
        return
      case "w":
        hide()
        return
      case "q":
        NSApp.terminate(nil)
        return
      default:
        break
      }
    }

    switch event.keyCode {
    case KeyHelpers.backspace.rawValue:
      clear()
      delay(1) {
        self.positionCheatsheetWindow()
      }
    case KeyHelpers.escape.rawValue:
      window.resignKey()
    default:
      guard let char = charForEvent(event) else { return }
      handleKey(char, withModifiers: event.modifierFlags)
    }
  }

  func handleKey(_ key: String, withModifiers modifiers: NSEvent.ModifierFlags? = nil, execute: Bool = true) {
    if key == "?" {
      showCheatsheet()
      return
    }

    let list =
      (userState.currentGroup != nil)
      ? userState.currentGroup : userConfig.root

    let hit = list?.actions.first { item in
      switch item {
      case .group(let group):
        // Normalize both keys for comparison
        let groupKey = KeyMaps.glyph(for: group.key ?? "") ?? group.key ?? ""
        let inputKey = KeyMaps.glyph(for: key) ?? key
        if groupKey == inputKey {
          return true
        }
      case .action(let action):
        // Normalize both keys for comparison
        let actionKey = KeyMaps.glyph(for: action.key ?? "") ?? action.key ?? ""
        let inputKey = KeyMaps.glyph(for: key) ?? key
        if actionKey == inputKey {
          return true
        }
      }
      return false
    }

    switch hit {
    case .action(let action) where execute && ActionInput.needsInput(action):
      startPrompt(for: action)
    case .action(let action):
      if execute {
        if let mods = modifiers, isInStickyMode(mods) {
          runAction(action)
        } else {
          hide {
            self.runAction(action)
          }
        }
      }
      // If execute is false, just stay visible showing the matched action
    case .group(let group):
      if execute, let mods = modifiers, shouldRunGroupSequenceWithModifiers(mods) {
        hide {
          self.runGroup(group)
        }
      } else {
        userState.display = group.key
        userState.navigateToGroup(group)
        loadDynamicGroup(group)
      }
    case .none:
      window.notFound()
    }

    // Why do we need to wait here?
    delay(1) {
      self.positionCheatsheetWindow()
    }
  }

  private func shouldRunGroupSequence(_ event: NSEvent) -> Bool {
    return shouldRunGroupSequenceWithModifiers(event.modifierFlags)
  }

  private func shouldRunGroupSequenceWithModifiers(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
    let config = Defaults[.modifierKeyConfiguration]

    switch config {
    case .controlGroupOptionSticky:
      return modifierFlags.contains(.control)
    case .optionGroupControlSticky:
      return modifierFlags.contains(.option)
    }
  }

  private func isInStickyMode(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
    let config = Defaults[.modifierKeyConfiguration]

    switch config {
    case .controlGroupOptionSticky:
      return modifierFlags.contains(.option)
    case .optionGroupControlSticky:
      return modifierFlags.contains(.control)
    }
  }

  internal func charForEvent(_ event: NSEvent) -> String? {
    let forceEnglish = Defaults[.forceEnglishKeyboardLayout]

    // 1. If the user forces English, or if the key is non-printable,
    //    fall back to the hard-coded map.
    if forceEnglish {
      return englishGlyph(for: event)
    }

    // 2. For special keys like Enter, always use the mapped glyph
    if let entry = KeyMaps.entry(for: event.keyCode) {
      // For Enter, Space, Tab, arrows, etc. - use the glyph representation
      if event.keyCode == KeyHelpers.enter.rawValue || event.keyCode == KeyHelpers.space.rawValue
        || event.keyCode == KeyHelpers.tab.rawValue
        || event.keyCode == KeyHelpers.leftArrow.rawValue
        || event.keyCode == KeyHelpers.rightArrow.rawValue
        || event.keyCode == KeyHelpers.upArrow.rawValue
        || event.keyCode == KeyHelpers.downArrow.rawValue
      {
        return entry.glyph
      }
    }

    // 3. Use the system-translated character for regular keys.
    if let printable = event.charactersIgnoringModifiers,
      !printable.isEmpty,
      printable.unicodeScalars.first?.isASCII ?? false
    {
      return printable  // already contains correct case
    }

    // 4. For arrows, ␣, ⌫ … use map as last resort.
    return englishGlyph(for: event)
  }

  private func englishGlyph(for event: NSEvent) -> String? {
    guard let entry = KeyMaps.entry(for: event.keyCode) else {
      return event.charactersIgnoringModifiers
    }
    if entry.glyph.first?.isLetter == true && !entry.isReserved {
      return event.modifierFlags.contains(.shift)
        ? entry.glyph.uppercased()
        : entry.glyph
    }
    return entry.glyph
  }

  private func positionCheatsheetWindow() {
    guard let mainWindow = window, let cheatsheet = cheatsheetWindow else {
      return
    }

    cheatsheet.setFrameOrigin(
      mainWindow.cheatsheetOrigin(cheatsheetSize: cheatsheet.frame.size))
  }

  private func showCheatsheet() {
    if !window.hasCheatsheet {
      window.revealDetails()
      return
    }
    positionCheatsheetWindow()
    cheatsheetWindow?.orderFront(nil)
  }

  private func scheduleCheatsheet() {
    cheatsheetTimer?.invalidate()

    cheatsheetTimer = Timer.scheduledTimer(
      withTimeInterval: Double(Defaults[.cheatsheetDelayMS]) / 1000.0, repeats: false
    ) { [weak self] _ in
      self?.showCheatsheet()
    }
  }

  private func runGroup(_ group: Group) {
    for groupOrAction in group.actions {
      switch groupOrAction {
      case .group(let group):
        runGroup(group)
      case .action(let action):
        runAction(action)
      }
    }
  }

  // MARK: - Dynamic groups

  /// Fills a group that has a `source` command, once it has run. The group
  /// shows straight away and its items appear when the command returns.
  private func loadDynamicGroup(_ group: Group) {
    guard let source = group.source else { return }
    DynamicSource.load(source) { [weak self] result in
      guard let self,
        let index = self.userState.navigationPath.lastIndex(where: { $0.uiid == group.uiid })
      else { return }  // The user has moved on.

      var filled = self.userState.navigationPath[index]
      switch result {
      case .success(let items):
        filled.actions = items
      case .failure(let failure):
        filled.actions = []
        filled.label = "\(group.displayName): \(failure.summary)"
      }
      self.userState.navigationPath[index] = filled
    }
  }

  // MARK: - Prompted actions

  private func startPrompt(for action: Action) {
    cheatsheetWindow?.orderOut(nil)
    cheatsheetTimer?.invalidate()
    userState.prompt = PromptState(action: action)
    promptWindow.show(on: window.screen ?? NSScreen.main ?? NSScreen())
  }

  private func endPrompt() {
    userState.prompt = nil
    promptWindow.orderOut(nil)
  }

  /// Edits the prompt's text. Returns false for keys it leaves to the normal
  /// handling (⌘W, ⌘Q, ⌘,).
  private func handlePromptKey(_ event: NSEvent) -> Bool {
    guard var prompt = userState.prompt else { return false }

    if event.modifierFlags.contains(.command) {
      switch event.charactersIgnoringModifiers {
      case "v":
        if let pasted = NSPasteboard.general.string(forType: .string) {
          prompt.text += pasted.components(separatedBy: .newlines).joined(separator: " ")
          userState.prompt = prompt
        }
        return true
      case "\u{7F}":  // ⌘⌫ clears the text
        prompt.text = ""
        userState.prompt = prompt
        return true
      default:
        return false
      }
    }

    switch event.keyCode {
    case KeyHelpers.escape.rawValue:
      endPrompt()
    case KeyHelpers.enter.rawValue:
      let (action, environment) = ActionInput.fill(prompt.action, with: prompt.text)
      endPrompt()
      hide {
        self.runAction(action, environment: environment)
      }
    case KeyHelpers.backspace.rawValue:
      if event.modifierFlags.contains(.option) {
        prompt.text = Self.dropLastWord(prompt.text)
      } else if !prompt.text.isEmpty {
        prompt.text.removeLast()
      }
      userState.prompt = prompt
    default:
      let typed = (event.characters ?? "").filter { character in
        !character.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
      }
      prompt.text += typed
      userState.prompt = prompt
    }
    return true
  }

  static func dropLastWord(_ text: String) -> String {
    var result = text
    while result.last?.isWhitespace == true { result.removeLast() }
    while let last = result.last, !last.isWhitespace { result.removeLast() }
    return result
  }

  private func runAction(_ action: Action, environment: [String: String] = [:]) {
    switch action.type {
    case .application:
      NSWorkspace.shared.openApplication(
        at: URL(fileURLWithPath: action.value),
        configuration: NSWorkspace.OpenConfiguration())
    case .url:
      openURL(action)
    case .command:
      CommandRunner.run(action.value, environment: environment)
    case .folder:
      let path: String = (action.value as NSString).expandingTildeInPath
      NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    default:
      print("\(action.type) unknown")
    }

    if window.isVisible {
      window.makeKeyAndOrderFront(nil)
    }
  }

  private func clear() {
    userState.clear()
  }

  private func openURL(_ action: Action) {
    guard let url = URL(string: action.value) else {
      showAlert(
        title: "Invalid URL", message: "Failed to parse URL: \(action.value)")
      return
    }

    guard let scheme = url.scheme else {
      showAlert(
        title: "Invalid URL",
        message:
          "URL is missing protocol (e.g. https://, raycast://): \(action.value)"
      )
      return
    }

    if scheme == "http" || scheme == "https" {
      NSWorkspace.shared.open(
        url,
        configuration: NSWorkspace.OpenConfiguration())
    } else {
      NSWorkspace.shared.open(
        url,
        configuration: DontActivateConfiguration.shared.configuration)
    }
  }

  private func showAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}

class DontActivateConfiguration {
  let configuration = NSWorkspace.OpenConfiguration()

  static var shared = DontActivateConfiguration()

  init() {
    configuration.activates = false
  }
}

extension Screen {
  func getNSScreen() -> NSScreen? {
    switch self {
    case .primary:
      return NSScreen.screens.first
    case .mouse:
      return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    case .activeWindow:
      return NSScreen.main
    }
  }
}
