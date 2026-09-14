import SwiftUI

extension View {
    @ViewBuilder
    /// Adds an equal padding amount to specific edges of this view without clipping scrollable views.
    /// - parameters:
    ///     - edges: Edges to add paddings
    ///     - length: The amount of padding to be added to edges.
    /// - Returns: A view that’s padded by the specified amount on specified edges.
    ///
    /// This modifier uses safe area as paddings, making both non-scrollable and scrollable content looks great in any context.
    public func contentPadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        if #available(macOS 14.0, *) {
            safeAreaPadding(edges, length)
        } else {
            safeAreaInset(edge: .top) {
                EmptyView().frame(width: 0, height: 0)
                    .padding(.top, edges.contains(.top) ? length : 0)
            }
            .safeAreaInset(edge: .bottom) {
                EmptyView().frame(width: 0, height: 0)
                    .padding(.bottom, edges.contains(.bottom) ? length : 0)
            }
            .safeAreaInset(edge: .leading) {
                EmptyView().frame(width: 0, height: 0)
                    .padding(.leading, edges.contains(.leading) ? length : 0)
            }
            .safeAreaInset(edge: .trailing) {
                EmptyView().frame(width: 0, height: 0)
                    .padding(.trailing, edges.contains(.trailing) ? length : 0)
            }
        }
    }
    
    /// Adds an equal padding amount to all edges of this view without clipping scrollable views.
    /// - parameters:
    ///     - length: The amount of padding to be added to edges.
    /// - Returns: A view that’s padded by the specified amount on all edges.
    ///
    /// This modifier uses safe area as paddings, making both non-scrollable and scrollable content looks great in any context.
    public func contentPadding(_ length: CGFloat) -> some View {
        contentPadding(.all, length)
    }
}
