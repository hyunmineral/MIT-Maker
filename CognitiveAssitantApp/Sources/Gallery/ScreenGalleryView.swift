import SwiftUI

/// Lays the screen list out as thumbnails and expands one to real size when pressed.
/// Corresponds to the `1b` · `1c` sheets of the original design document.
struct ScreenGalleryView: View {
    var screens: [ScreenSpec]
    var columns: Int

    @State private var expanded: ScreenSpec?

    private static let padding: CGFloat = 28
    private static let gap: CGFloat = 26

    private var grid: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: columns)
    }

    /// Thumbnail width is computed from the actual available width. On a portrait canvas thumbnails get tall,
    /// so a fixed value overflows or leaves gaps depending on the column count.
    private func thumbnailWidth(in totalWidth: CGFloat) -> CGFloat {
        let usable = totalWidth - Self.padding * 2 - Self.gap * CGFloat(columns - 1)
        return max(80, usable / CGFloat(columns))
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVGrid(columns: grid, alignment: .leading, spacing: Self.gap) {
                    ForEach(screens) { spec in
                        Button {
                            expanded = spec
                        } label: {
                            cell(spec, width: thumbnailWidth(in: geo.size.width))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Self.padding)
                // Leave room so the last row isn't hidden behind the switch bar at the bottom left.
                .padding(.bottom, 60)
            }
        }
        .background(Theme.paper)
        .fullScreenCover(item: $expanded) { spec in
            ScreenDetailView(spec: spec)
        }
    }

    private func cell(_ spec: ScreenSpec, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ScreenThumbnail(width: width) {
                spec.view
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(spec.numberLabel) \(spec.title)").bold()
                    .font(.kr(12))
                    .foregroundStyle(Theme.gray4A)
                Text(spec.note)
                    .font(.kr(12))
                    .foregroundStyle(Theme.gray8A)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .cssLineHeight(1.5, 12)
        }
    }
}

/// Full screen shown when a thumbnail is pressed. Exactly the size it appears on a real iPad.
struct ScreenDetailView: View {
    var spec: ScreenSpec
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DesignCanvas {
                spec.view
            }
            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .font(.kr(15, .semibold))
                    .foregroundStyle(Theme.cream(0.8))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.45))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cream(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(24)
        }
        .statusBarHidden()
    }
}
