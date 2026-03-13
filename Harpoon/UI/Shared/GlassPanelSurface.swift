import AppKit
import SwiftUI

struct GlassPanelSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let content: Content

    init(
        cornerRadius: CGFloat = 18,
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.blendingMode = blendingMode
        self.content = content()
    }

    var body: some View {
        content
            .background {
                ZStack {
                    VisualEffectMaterialView(material: material, blendingMode: blendingMode)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipShape(shape)
            }
            .overlay {
                shape
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.22))
            }
            .clipShape(shape)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

private struct VisualEffectMaterialView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.blendingMode = blendingMode
        view.material = material
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
