import Cocoa
import SwiftUI

/// Prompted actions: a command or URL containing `{input}` asks for text before
/// it runs, e.g. `cubicle rename {input}` or `https://duckduckgo.com/?q={input}`.
enum ActionInput {
  static let placeholder = "{input}"
  /// Commands get the typed text through this environment variable rather than
  /// pasted into the command line, so it can't be read as shell syntax in any
  /// shell (sh, zsh, bash or fish).
  static let environmentKey = "LAZYSUSAN_INPUT"

  static func needsInput(_ action: Action) -> Bool {
    switch action.type {
    case .command, .url:
      return action.value.contains(placeholder)
    default:
      return false
    }
  }

  /// The action to run once the user has typed `input`, plus any environment
  /// the command needs.
  static func fill(_ action: Action, with input: String) -> (
    action: Action, environment: [String: String]
  ) {
    var filled = action
    switch action.type {
    case .command:
      filled.value = action.value.replacingOccurrences(
        of: placeholder, with: "\"$\(environmentKey)\"")
      return (filled, [environmentKey: input])
    case .url:
      // Encode everything but RFC 3986's unreserved characters, so the text
      // works in a path, a query value or a custom scheme alike.
      var unreserved = CharacterSet.alphanumerics
      unreserved.insert(charactersIn: "-._~")
      let encoded = input.addingPercentEncoding(withAllowedCharacters: unreserved) ?? input
      filled.value = action.value.replacingOccurrences(of: placeholder, with: encoded)
      return (filled, [:])
    default:
      return (action, [:])
    }
  }
}

/// The text being typed for a prompted action.
struct PromptState: Equatable {
  let action: Action
  var text: String = ""
}

/// A small panel, like Spotlight's, showing what's being typed. It never takes
/// focus: the theme window stays key and the controller feeds it keystrokes.
enum Prompt {
  static let width = 480.0
  static let height = 104.0

  class Window: PanelWindow {
    init(userState: UserState) {
      super.init(contentRect: NSRect(x: 0, y: 0, width: Prompt.width, height: Prompt.height))
      level = .floating
      contentView = NSHostingView(rootView: PromptView().environmentObject(userState))
    }

    func show(on screen: NSScreen) {
      let visible = screen.visibleFrame
      setFrameOrigin(
        NSPoint(
          x: visible.midX - Prompt.width / 2,
          y: visible.maxY - visible.height * 0.28 - Prompt.height))
      orderFront(nil)
    }
  }

  struct PromptView: View {
    @EnvironmentObject var userState: UserState

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        if let prompt = userState.prompt {
          HStack(spacing: 8) {
            Cheatsheet.KeyBadge(key: prompt.action.key ?? "●")
            Text(prompt.action.displayName)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          HStack(spacing: 1) {
            if prompt.text.isEmpty {
              Caret()
              Text("Type, then press ↩")
                .foregroundStyle(.tertiary)
            } else {
              Text(prompt.text)
                .lineLimit(1)
                .truncationMode(.head)
              Caret()
            }
            Spacer()
            Text("esc back")
              .font(.system(size: 11, design: .rounded))
              .foregroundStyle(.tertiary)
          }
          .font(.system(size: 20, weight: .medium, design: .rounded))
        }
      }
      .padding(16)
      .frame(width: Prompt.width, height: Prompt.height, alignment: .topLeading)
      .background(
        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
      )
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
  }

  struct Caret: View {
    @State private var visible = true

    var body: some View {
      Rectangle()
        .fill(Color.accentColor)
        .frame(width: 2, height: 22)
        .opacity(visible ? 1 : 0)
        .onAppear {
          withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
            visible = false
          }
        }
    }
  }
}
