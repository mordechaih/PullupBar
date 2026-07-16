import SwiftUI

/// Shared visual + interaction vocabulary for the row "chips" across every tab (PR rows and
/// branch rows). Extracted so both `PullRequestChip` and `BranchChip` share one hover/animation
/// language instead of each rolling its own.

/// A frosted-glass scrim anchored to the trailing edge that sits beneath the hover pill and fades
/// out to the left. Material samples and blurs the row text behind it, so the text dissolves into
/// a blur behind the icons instead of colliding with them. The gradient mask (clear on the left,
/// opaque on the right) makes the blur "extend left" of the pill and taper away. Fades in on hover.
struct ChipBlurScrim: View {
    let isHovered: Bool

    /// Width of the frosted scrim: covers the 3-icon pill (~112pt) plus a fade region to its left.
    private static let scrimWidth: CGFloat = 200

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(width: Self.scrimWidth)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.45)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .allowsHitTesting(false)
            // Flatten the frosted material to an offscreen layer BEFORE fading it. Applying opacity
            // straight to a Material blends its vibrancy live at every intermediate alpha, and a
            // partially-faded material over the card's own material peaks brighter than either the
            // hidden or fully-shown state — a visible flash mid-transition. compositingGroup rasters
            // the scrim once at full strength so opacity then fades that flat image linearly.
            .compositingGroup()
            .opacity(isHovered ? 1 : 0)
            // easeInOut (not the ancestor's bouncy hover spring) keeps the fade monotonic so the
            // flattened scrim never overshoots its target opacity.
            .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}

/// Stacks row "chips" into a single frosted card: rows sit flush against each other separated by
/// hairline dividers, with one shared material backing and only the group's outer corners rounded —
/// the same grouped-list treatment the settings folder list uses. Rows supply their own content and
/// hover overlays but no longer carry an individual card background/clip, so a lane or tab reads as
/// one list instead of a stack of separate cards.
struct ChipGroup<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder let row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 1)
                }
                row(element)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .chipTopHighlight()
    }
}

extension View {
    /// A hairline highlight along the top edge that fades to transparent toward the bottom — the
    /// subtle "lit from above" edge every chip shares.
    func chipTopHighlight(cornerRadius: CGFloat = 8) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }
}

/// A quick pop-and-settle scale pulse fired whenever `trigger` changes — tap feedback for icon
/// buttons (works on custom Octicon shapes and SF Symbols alike).
struct TapBounceModifier: ViewModifier {
    let trigger: Int
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: trigger) { _ in
                withAnimation(.spring(response: 0.15, dampingFraction: 0.35)) { scale = 1.35 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { scale = 1 }
                }
            }
    }
}

extension View {
    func tapBounce(_ trigger: Int) -> some View {
        modifier(TapBounceModifier(trigger: trigger))
    }
}

/// Circular hover treatment for an icon button: a faint circle backing plus a gentle scale-up.
struct IconHoverModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 16))
            .padding(6)
            .background(Circle().fill(isHovering ? Color.secondary.opacity(0.18) : Color.clear))
            .scaleEffect(isHovering ? 1.15 : 1)
            .onHover { hovering in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    isHovering = hovering
                }
            }
    }
}

extension View {
    func iconHoverEffect() -> some View {
        modifier(IconHoverModifier())
    }
}

/// Scales an item in from its center with a per-index delay so a row of items pops in on a
/// stagger. The delay only applies on the way in; on the way out everything collapses together.
struct StaggeredScaleModifier: ViewModifier {
    let isActive: Bool
    let index: Int
    private static let perItemDelay: Double = 0.05

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 1 : 0.3)
            .opacity(isActive ? 1 : 0)
            .animation(
                .spring(response: 0.3, dampingFraction: 0.6)
                    .delay(isActive ? Double(index) * Self.perItemDelay : 0),
                value: isActive
            )
    }
}

extension View {
    func staggeredScale(isActive: Bool, index: Int) -> some View {
        modifier(StaggeredScaleModifier(isActive: isActive, index: index))
    }
}
