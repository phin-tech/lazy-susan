import Cocoa
import Combine
import Defaults
import SwiftUI

/// Spacemacs / which-key style: a full-width panel docked to the bottom of the
/// screen listing every binding at the current level in columns.
enum WhichKey {
  static let margin = 8.0
  static let columnWidth = 220.0
  static let iconSize = NSSize(width: 16, height: 16)

  final class Layout: ObservableObject {
    @Published var width: CGFloat = 800
  }

  class Window: MainWindow {
    override var hasCheatsheet: Bool { return false }

    private let layout = Layout()
    private var targetScreen: NSScreen?
    private var resizeObserver: NSObjectProtocol?

    required init(controller: Controller) {
      super.init(controller: controller, contentRect: NSRect(x: 0, y: 0, width: 800, height: 0))
      let view = MainView()
        .environmentObject(controller.userState)
        .environmentObject(layout)
      contentView = NSHostingView(rootView: view)

      // Content height changes as the user navigates groups; keep the panel
      // pinned to the bottom edge of the screen whenever that happens.
      resizeObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didResizeNotification, object: self, queue: .main
      ) { [weak self] _ in
        self?.pinToBottom()
      }
    }

    deinit {
      if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    private func pinToBottom() {
      guard let screen = targetScreen else { return }
      let visible = screen.visibleFrame
      let origin = NSPoint(
        x: visible.minX + WhichKey.margin,
        y: visible.minY + WhichKey.margin)
      if frame.origin != origin {
        setFrameOrigin(origin)
      }
    }

    override func show(on screen: NSScreen, after: (() -> Void)?) {
      self.targetScreen = screen
      layout.width = screen.visibleFrame.width - WhichKey.margin * 2
      pinToBottom()

      makeKeyAndOrderFront(nil)

      fadeIn {
        after?()
      }
    }

    override func hide(after: (() -> Void)?) {
      fadeOut {
        self.close()
        after?()
      }
    }

    override func notFound() {
      shake()
    }
  }

  struct MainView: View {
    @EnvironmentObject var userState: UserState
    @EnvironmentObject var layout: Layout

    var items: [ActionOrGroup] {
      userState.currentGroup?.actions ?? userState.userConfig.root.actions
    }

    /// Splits items into columns filled top-to-bottom, like which-key does.
    var columns: [[ActionOrGroup]] {
      let usable = layout.width - 32
      let spacing = 16.0
      let maxColumns = max(1, Int((usable + spacing) / (WhichKey.columnWidth + spacing)))
      let rows = max(1, Int((Double(items.count) / Double(maxColumns)).rounded(.up)))
      return stride(from: 0, to: items.count, by: rows).map { start in
        Array(items[start..<min(start + rows, items.count)])
      }
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 16) {
          ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
            VStack(alignment: .leading, spacing: 6) {
              ForEach(column, id: \.uiid) { item in
                Binding_(item: item)
              }
            }
            .frame(width: WhichKey.columnWidth, alignment: .leading)
          }
        }

        Divider()

        StatusLine()
      }
      .padding(16)
      .frame(width: layout.width, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .font(.system(size: 13, design: .monospaced))
      .background(
        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
      )
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }

  /// One "key → description" cell.
  struct Binding_: View {
    let item: ActionOrGroup
    @Default(.showAppIconsInCheatsheet) var showIcons

    var key: String {
      let raw = item.item.key ?? "●"
      return KeyMaps.glyph(for: raw) ?? raw
    }

    var isGroup: Bool {
      if case .group = item { return true }
      return false
    }

    var body: some View {
      HStack(spacing: 6) {
        Text(key)
          .fontWeight(.bold)
          .foregroundStyle(Color.accentColor)
          .frame(minWidth: 14, alignment: .trailing)

        Text("→")
          .foregroundStyle(.tertiary)

        if showIcons {
          actionIcon(item: item, iconSize: WhichKey.iconSize)
        }

        Text(isGroup ? "+\(item.item.displayName)" : item.item.displayName)
          .foregroundStyle(isGroup ? Color.purple : Color.primary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
  }

  /// Bottom line mirroring Spacemacs' prefix echo, e.g. "␣ b w-".
  struct StatusLine: View {
    @EnvironmentObject var userState: UserState

    var body: some View {
      HStack(spacing: 6) {
        let keys = userState.navigationPath.compactMap { group in
          group.key.map { KeyMaps.glyph(for: $0) ?? $0 }
        }
        let prefix = (["●"] + keys).joined(separator: " ") + "-"

        let text = Text(prefix).fontWeight(.bold)
        if userState.isShowingRefreshState {
          text.pulsate()
        } else {
          text
        }

        if let group = userState.currentGroup {
          Text(group.displayName)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Text("⌫ top  esc quit")
          .foregroundStyle(.tertiary)
      }
      .font(.system(size: 12, design: .monospaced))
    }
  }
}
