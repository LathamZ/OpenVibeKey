import SwiftUI
import AppKit
import VibeKitHost

/// Original product artwork, bundled so the catalog also works on a fresh recipient Mac.
struct WorkflowAppIcon: View {
    let target: WorkflowTargetID
    var size: CGFloat = 30
    var body: some View {
        Group {
            if let image = Self.image(target) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Text(String(WorkflowCatalog.target(target).name.prefix(2))).font(.system(size: size * 0.36, weight: .semibold))
            }
        }.frame(width: size, height: size)
            .accessibilityLabel(WorkflowCatalog.target(target).name)
    }
    static func name(_ target: WorkflowTargetID) -> String {
        switch target {
        case .codex: return "workflow-codex"
        case .deepSeek: return "workflow-deepseek"
        case .claudeCode: return "workflow-claude"
        case .weChat: return "workflow-wechat"
        }
    }
    static func resourceURL(_ target: WorkflowTargetID, bundle: Bundle = .main) -> URL? {
        let file = name(target) + ".png"
        for root in [bundle.resourceURL, bundle.bundleURL.appendingPathComponent("Contents/Resources")].compactMap({ $0 }) {
            for relative in ["VibeKit_VibeKitApp.bundle/" + file, "VibeKit_VibeKitApp.bundle/Contents/Resources/" + file] {
                let path = root.appendingPathComponent(relative)
                if FileManager.default.isReadableFile(atPath: path.path) { return path }
            }
        }
        return nil
    }
    static func image(_ target: WorkflowTargetID) -> NSImage? {
        resourceURL(target).flatMap { NSImage(contentsOf: $0) }
    }
    static func verifyBundledIcons() -> Bool {
        WorkflowTargetID.allCases.allSatisfy { target in
            guard let image = image(target) else { return false }
            return image.isValid && image.size.width >= 128 && image.size.height >= 128
        }
    }
}
