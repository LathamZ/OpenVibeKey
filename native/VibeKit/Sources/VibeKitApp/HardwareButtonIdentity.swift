import SwiftUI

/// Fixed physical legends, verified against the bundled AU05 product photo (top to bottom).
enum HardwareButtonIdentity {
    static func symbol(_ id: String) -> String? {
        switch id { case "btn1": return "mic"; case "btn2": return "checkmark.circle"; case "btn3": return "xmark.circle"; default: return nil }
    }
    static func name(_ id: String) -> String {
        switch id { case "btn1": return "按钮 1"; case "btn2": return "按钮 2"; case "btn3": return "按钮 3"; default: return id }
    }
}
struct HardwareButtonLabel: View {
    let id: String
    var body: some View {
        Label(HardwareButtonIdentity.name(id), systemImage: HardwareButtonIdentity.symbol(id) ?? "circle")
            .labelStyle(.titleAndIcon)
    }
}
