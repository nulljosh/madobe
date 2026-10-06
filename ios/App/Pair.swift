import SwiftUI

/// Two pages side by side in one window. The first is the tab you came from.
@MainActor
final class PairModel: ObservableObject {
    static let splitRange = 0.25...0.75

    @Published var first: Page
    @Published var second: Page
    /// The share of the window the first page gets, between 0.25 and 0.75.
    @Published private(set) var split = 0.5

    init(first: Page, second: Page) {
        self.first = first
        self.second = second
    }

    func setSplit(_ value: Double) {
        split = min(max(value, PairModel.splitRange.lowerBound), PairModel.splitRange.upperBound)
    }

    func swap() { (first, second) = (second, first) }

    /// The divider position as a share of the window, from a drag at `offset` points of `length`.
    static func fraction(offset: Double, length: Double) -> Double {
        length > 0 ? offset / length : 0.5
    }

    /// Side by side when the window is wider than tall (landscape) or has room for two pages across
    /// (iPad in any orientation); stacked on a portrait iPhone.
    static func sideBySide(width: Double, height: Double, roomy: Bool = false) -> Bool { roomy || width > height }
}

#if os(iOS)
struct PairView: View {
    @ObservedObject var tabs: Tabs
    @ObservedObject var pair: PairModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let handle: CGFloat = 16

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = PairModel.sideBySide(width: geo.size.width, height: geo.size.height, roomy: sizeClass == .regular)
                let length = (wide ? geo.size.width : geo.size.height) - handle
                let a = length * pair.split
                let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    PairPane(page: pair.first).id(pair.first.id)
                        .frame(width: wide ? a : nil, height: wide ? nil : a)
                    divider(wide: wide, length: length)
                    PairPane(page: pair.second).id(pair.second.id)
                }
            }
            .coordinateSpace(name: "pair")
            // Like the main address bar: tapping an address selects all of it.
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
                guard let field = note.object as? UITextField else { return }
                DispatchQueue.main.async { field.selectAll(nil) }
            }
            .navigationTitle("Pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { pair.swap() } label: { Label("Swap", systemImage: "arrow.left.arrow.right") }
                        .accessibilityLabel("Swap the two pages")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { tabs.endPair() } }
            }
        }
    }

    private func divider(wide: Bool, length: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color.accentColor)
            Capsule().fill(.white).frame(width: wide ? 4 : 36, height: wide ? 36 : 4)
        }
        .frame(width: wide ? handle : nil, height: wide ? nil : handle)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(coordinateSpace: .named("pair"))
                .onChanged { v in
                    let at = wide ? v.location.x : v.location.y
                    pair.setSplit(PairModel.fraction(offset: Double(at - handle / 2), length: Double(length)))
                }
        )
        .accessibilityLabel("Divider")
        .accessibilityAdjustableAction { dir in
            pair.setSplit(pair.split + (dir == .increment ? 0.05 : -0.05))
        }
    }
}

/// One side of a pair: its own back, forward and address field above the page.
struct PairPane: View {
    @ObservedObject var page: Page
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { page.web.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!page.canBack).accessibilityLabel("Back")
                Button { page.web.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!page.canForward).accessibilityLabel("Forward")
                HStack(spacing: 6) {
                    Image(systemName: page.secure ? "lock.fill" : "magnifyingglass")
                        .foregroundStyle(.secondary).font(.footnote)
                    TextField("Search or enter address", text: $page.address)
                        .textFieldStyle(.plain)
                        .focused($editing)
                        .onSubmit { page.go(page.address); editing = false }
                        .keyboardType(.webSearch).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button { if page.loading { page.web.stopLoading() } else { page.web.reload() } } label: {
                    Image(systemName: page.loading ? "xmark" : "arrow.clockwise")
                }
                .accessibilityLabel(page.loading ? "Stop" : "Reload")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.bar)
            WebView(web: page.web)
        }
        .clipped()
    }
}
#endif
