import SwiftUI

/// Who the app is currently placed in front of.
///
/// `Docs/03_product-design.md` section 6. The same screens are used in two contexts, so the layouts
/// are not lumped into one.
enum AppMode: String, CaseIterable, Identifiable {
    /// Catalogue of the 16 screens. For development and demos.
    case gallery
    /// Fixed script + Wizard of Oz where staff tap the next step. The bottom 200pt is the staff panel.
    case pilot
    /// A kiosk in front of the elder. **No staff elements on screen at all.**
    case deployment

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gallery:    "Gallery · 16 screens"
        case .pilot:      "Pilot · staff-driven"
        case .deployment: "Deployment · elder only"
        }
    }

    var detail: String {
        switch self {
        case .gallery:
            "A catalog for checking the design. Do not leave this in front of an elder."
        case .pilot:
            "The bottom 200pt is the staff panel. The choices are 20pt, "
            + "unreadable to an elder sitting 70cm away."
        case .deployment:
            "Every staff element disappears from the screen. "
            + "To get back, press anywhere with two fingers for 1.5 seconds."
        }
    }

    /// Eye-centre y on the elder stage. Deployment mode has no staff panel, so the stage is taller.
    var eyeCenterY: CGFloat {
        self == .deployment ? Theme.Layout.eyeCenterY : Theme.Layout.eyeCenterYPilot
    }

    /// The y where the line starts.
    var captionTop: CGFloat {
        self == .deployment ? Theme.Layout.captionTop : Theme.Layout.captionTopPilot
    }

    /// Height given to the elder stage.
    var stageHeight: CGFloat {
        self == .deployment ? DesignSpec.height : Theme.Layout.stageHeightPilot
    }

    var showsStaffPanel: Bool { self != .deployment }
}

/// Persist the mode on the device.
///
/// **The kiosk is switched off and on every day and also restarts for OS updates.** If staff had to
/// switch it back to deployment mode each time, one day it would sit in front of an elder still on the pilot screen.
@Observable
final class AppModeStore {
    private static let key = "AppMode.current"

    var mode: AppMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.key) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        mode = saved.flatMap(AppMode.init(rawValue:)) ?? .pilot
    }
}
