import Cocoa
import Combine
import Defaults
import SwiftUI

/// Pie / radial menu: bindings arranged on rings around the centre of the
/// screen, with the current group shown in the hub.
///
/// Design notes, drawn from marking-menu research (Kurtenbach & Buxton) and
/// existing pie menus (Blender, Kando, Fly-Pie):
/// - At most 8 items per ring; anything past two rings goes in a plain list.
/// - The wheel can stay collapsed to a small hub until the user hesitates, so
///   people who know their keys never see it (follows the cheatsheet setting).
/// - A trail above the wheel shows the groups entered so far.
enum Radial {
  static let wheelSize = 600.0
  static let trailHeight = 44.0
  static let overflowHeight = 150.0
  static let windowSize = NSSize(
    width: wheelSize, height: trailHeight + wheelSize + overflowHeight)

  static let hubRadius = 70.0
  static let collapsedHubRadius = 28.0
  static let singleRingRadius = 175.0
  static let innerRingRadius = 135.0
  static let outerRingRadius = 235.0
  static let ringCapacity = 8
  static let overflowColumns = 3
  static let overflowMaxRows = 5
  static let iconSize = NSSize(width: 20, height: 20)

  /// Whether the full wheel is showing or only the collapsed hub.
  final class Model: ObservableObject {
    @Published var expanded = true
  }

  class Window: MainWindow {
    override var hasCheatsheet: Bool { return false }

    private let model = Model()
    private var revealTimer: Timer?
    private var navigationSubscription: AnyCancellable?

    required init(controller: Controller) {
      // Fixed-size window: everything is drawn inside it, so navigating never
      // needs to resize or re-centre it. Empty areas are fully transparent.
      super.init(
        controller: controller,
        contentRect: NSRect(origin: .zero, size: Radial.windowSize))
      let view = MainView()
        .environmentObject(controller.userState)
        .environmentObject(model)
      contentView = NSHostingView(rootView: view)

      // Each key press that enters a group restarts the reveal delay, like the
      // cheatsheet timer does.
      navigationSubscription = controller.userState.$navigationPath
        .dropFirst()
        .sink { [weak self] _ in
          guard let self, self.isVisible, !self.model.expanded else { return }
          self.scheduleReveal()
        }
    }

    private func scheduleReveal() {
      revealTimer?.invalidate()
      guard Defaults[.autoOpenCheatsheet] == .delay else { return }
      revealTimer = Timer.scheduledTimer(
        withTimeInterval: Double(Defaults[.cheatsheetDelayMS]) / 1000.0,
        repeats: false
      ) { [weak self] _ in
        self?.revealDetails()
      }
    }

    override func revealDetails() {
      revealTimer?.invalidate()
      withAnimation(.spring(duration: 0.25)) {
        model.expanded = true
      }
    }

    override func show(on screen: NSScreen, after: (() -> Void)?) {
      // Refresh animations always show the full wheel so the pulse is visible.
      let setting = Defaults[.autoOpenCheatsheet]
      model.expanded = setting == .always || controller.userState.isShowingRefreshState
      if !model.expanded {
        scheduleReveal()
      }

      // Centre the wheel (not the whole window) on the screen.
      let center = screen.center()
      setFrameOrigin(
        NSPoint(
          x: center.x - Radial.wheelSize / 2,
          y: center.y - Radial.wheelSize / 2 - Radial.overflowHeight))

      makeKeyAndOrderFront(nil)

      fadeIn {
        after?()
      }
    }

    override func hide(after: (() -> Void)?) {
      revealTimer?.invalidate()
      fadeOut {
        self.close()
        after?()
      }
    }

    override func notFound() {
      shake()
    }
  }

  struct Placement {
    let item: ActionOrGroup
    let point: CGPoint
  }

  struct Layout {
    let placements: [Placement]
    let overflow: [ActionOrGroup]
  }

  /// Up to 8 items on one ring; up to 16 across an inner and an outer ring,
  /// with the outer ring rotated half a slot so items don't line up; the rest
  /// overflow. Items start at 12 o'clock and go clockwise in config order, so
  /// each binding keeps the same position every time the menu opens.
  static func layout(for items: [ActionOrGroup], in size: CGSize) -> Layout {
    let center = CGPoint(x: size.width / 2, y: size.height / 2)

    func ring(_ slice: ArraySlice<ActionOrGroup>, radius: Double, offset: Double)
      -> [Placement]
    {
      let count = slice.count
      guard count > 0 else { return [] }
      return slice.enumerated().map { index, item in
        let angle = (Double(index) + offset) / Double(count) * 2 * .pi - .pi / 2
        return Placement(
          item: item,
          point: CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)))
      }
    }

    if items.count <= ringCapacity {
      return Layout(
        placements: ring(items[...], radius: singleRingRadius, offset: 0),
        overflow: [])
    }

    let inner = items.prefix(ringCapacity)
    let outer = items.dropFirst(ringCapacity).prefix(ringCapacity)
    return Layout(
      placements: ring(inner, radius: innerRingRadius, offset: 0)
        + ring(outer, radius: outerRingRadius, offset: 0.5),
      overflow: Array(items.dropFirst(ringCapacity * 2)))
  }

  static func glyph(_ key: String?) -> String {
    let key = key ?? "●"
    return KeyMaps.glyph(for: key) ?? key
  }

  struct MainView: View {
    @EnvironmentObject var userState: UserState
    @EnvironmentObject var model: Model

    var items: [ActionOrGroup] {
      userState.currentGroup?.actions ?? userState.userConfig.root.actions
    }

    var body: some View {
      let size = CGSize(width: Radial.wheelSize, height: Radial.wheelSize)
      let layout = Radial.layout(for: items, in: size)

      VStack(spacing: 0) {
        Trail()
          .frame(height: Radial.trailHeight, alignment: .bottom)

        ZStack {
          if model.expanded {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
              .clipShape(Circle())
              .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
              .transition(.scale(scale: 0.2).combined(with: .opacity))

            ForEach(layout.placements, id: \.item.uiid) { placement in
              Slice(item: placement.item, compact: items.count > Radial.ringCapacity)
                .position(placement.point)
                .transition(.opacity)
            }
          }

          Hub(collapsed: !model.expanded)
            .position(x: size.width / 2, y: size.height / 2)
        }
        .frame(width: size.width, height: size.height)
        .animation(.spring(duration: 0.25), value: userState.navigationPath.count)

        Overflow(items: model.expanded ? layout.overflow : [])
          .frame(height: Radial.overflowHeight, alignment: .top)
      }
      .frame(width: Radial.windowSize.width, height: Radial.windowSize.height)
    }
  }

  struct Hub: View {
    @EnvironmentObject var userState: UserState
    let collapsed: Bool

    var body: some View {
      let radius = collapsed ? Radial.collapsedHubRadius : Radial.hubRadius

      ZStack {
        if collapsed {
          VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            .clipShape(Circle())
        }
        Circle().fill(.white.opacity(0.08))

        VStack(spacing: 2) {
          let text = Text(Radial.glyph(userState.currentGroup?.key))
            .font(.system(size: collapsed ? 16 : 22, weight: .bold, design: .rounded))
            .foregroundStyle(userState.currentGroup == nil ? .secondary : .primary)

          if userState.isShowingRefreshState {
            text.pulsate()
          } else {
            text
          }

          if !collapsed {
            Text(userState.currentGroup?.displayName ?? "Lazy Susan")
              .font(.system(size: 11, weight: .medium, design: .rounded))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.tail)
              .padding(.horizontal, 10)
          }
        }
      }
      .frame(width: radius * 2, height: radius * 2)
    }
  }

  /// Breadcrumb of entered groups, drawn as linked bubbles: ● — o — b  Name
  struct Trail: View {
    @EnvironmentObject var userState: UserState

    var body: some View {
      if !userState.navigationPath.isEmpty {
        HStack(spacing: 0) {
          bubble(Radial.glyph(nil), current: false)
          ForEach(Array(userState.navigationPath.enumerated()), id: \.offset) { index, group in
            Rectangle()
              .fill(.white.opacity(0.25))
              .frame(width: 14, height: 1.5)
            bubble(
              Radial.glyph(group.key),
              current: index == userState.navigationPath.count - 1)
          }
          Text(userState.currentGroup?.displayName ?? "")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .lineLimit(1)
            .padding(.leading, 8)
            .padding(.trailing, 4)
        }
        .padding(4)
        .background(
          VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            .clipShape(Capsule())
        )
        .padding(.bottom, 6)
        .transition(.opacity)
      }
    }

    func bubble(_ text: String, current: Bool) -> some View {
      Text(text)
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(current ? .primary : .secondary)
        .frame(width: 22, height: 22)
        .background(
          Circle().fill(current ? Color.accentColor.opacity(0.45) : .white.opacity(0.1)))
    }
  }

  struct Slice: View {
    let item: ActionOrGroup
    let compact: Bool
    @Default(.showAppIconsInCheatsheet) var showIcons

    var isGroup: Bool {
      if case .group = item { return true }
      return false
    }

    var body: some View {
      VStack(spacing: 3) {
        ZStack {
          Circle()
            .fill(isGroup ? Color.accentColor.opacity(0.35) : .white.opacity(0.12))
          if showIcons && !compact {
            actionIcon(item: item, iconSize: Radial.iconSize)
          } else {
            Text(Radial.glyph(item.item.key))
              .font(.system(size: 15, weight: .bold, design: .rounded))
          }
        }
        .frame(width: 34, height: 34)
        .overlay(alignment: .topTrailing) {
          // With icons on, the key moves to a small corner badge.
          if showIcons && !compact {
            Text(Radial.glyph(item.item.key))
              .font(.system(size: 10, weight: .bold, design: .rounded))
              .padding(.horizontal, 4)
              .background(Capsule().fill(.black.opacity(0.6)))
              .offset(x: 6, y: -4)
          }
        }

        Text(isGroup ? "\(item.item.displayName) ›" : item.item.displayName)
          .font(.system(size: compact ? 10 : 11, weight: .medium, design: .rounded))
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: compact ? 76 : 96)
      }
    }
  }

  /// Items beyond the two rings, as a compact key list under the wheel.
  struct Overflow: View {
    let items: [ActionOrGroup]

    var visible: [ActionOrGroup] {
      Array(items.prefix(Radial.overflowColumns * Radial.overflowMaxRows))
    }

    var body: some View {
      if !items.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          LazyVGrid(
            columns: Array(
              repeating: GridItem(.flexible(), spacing: 12, alignment: .leading),
              count: Radial.overflowColumns),
            alignment: .leading, spacing: 4
          ) {
            ForEach(visible, id: \.uiid) { item in
              HStack(spacing: 6) {
                Cheatsheet.KeyBadge(key: item.item.key ?? "●")
                Text(item.item.displayName)
                  .lineLimit(1)
                  .truncationMode(.tail)
              }
            }
          }
          if items.count > visible.count {
            Text("+\(items.count - visible.count) more")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .font(.system(size: 12, design: .rounded))
        .padding(10)
        .background(
          VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 8)
        .padding(.horizontal, 40)
        .transition(.opacity)
      }
    }
  }
}
