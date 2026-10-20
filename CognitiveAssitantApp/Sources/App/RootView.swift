import SwiftUI

/// The app shell.
///
/// **The mode decides what is shown** (`Docs/03_product-design.md` section 6).
/// In deployment mode only the session screen remains and even the switch button disappears — the physical
/// implementation of principle 1, that the screen placed in front of the elder must have no staff elements at all.
struct RootView: View {

    /// What to view inside gallery mode.
    enum GallerySection: String, CaseIterable, Identifiable {
        case elder, staff

        var id: String { rawValue }

        var label: String {
            switch self {
            case .elder: "Elder screens (12)"
            case .staff: "Staff · family screens (4)"
            }
        }
    }

    @State private var modeStore = AppModeStore()
    @State private var gallerySection: GallerySection = .elder
    @State private var chromeHidden = false
    @State private var probe: Probe? = Probe.fromLaunchArguments
    /// Catalogue screen number given as a launch argument. **For remote checking.**
    @State private var pinnedScreen: Int? = RootView.pinnedScreenFromLaunchArguments

    private var mode: AppMode { modeStore.mode }

    /// **Opens a probe screen directly from a launch argument.**
    ///
    /// Staff settings sit behind a two-finger long press, and that gesture can't be
    /// reproduced in the simulator. If a person has to press the device every time a prompt changes,
    /// checks don't get run, so this opens one path that can be triggered automatically.
    ///
    /// ```bash
    /// xcrun simctl launch <device> com.tictechtoe.RobotForElders -probe understanding
    /// ```
    ///
    /// **Lives only in `DEBUG`.** Left in a release build, the kiosk in front of the elder could open a staff screen
    /// with a single launch argument.
    /// **Don't stack several `fullScreenCover`s.** With three on one view,
    /// the third silently failed to open — no error, no log. Take them through a single `item:`.
    enum Probe: String, Identifiable {
        case understanding, reply, plan
        var id: String { rawValue }

        static var fromLaunchArguments: Probe? {
            #if DEBUG
            UserDefaults.standard.string(forKey: "probe").flatMap(Probe.init(rawValue:))
            #else
            nil
            #endif
        }
    }

    /// **Opens one screen directly from a launch argument.**
    ///
    /// ```bash
    /// xcrun simctl launch <device> com.tictechtoe.RobotForElders -screen 15
    /// ```
    ///
    /// The four staff screens live inside the gallery, and reaching them requires a person to tap menus.
    /// Without a way to check remotely that a screen actually appears, we'd move on **knowing nothing
    /// except that the build passed**.
    ///
    /// **Lives only in `DEBUG`.** Left in a release build, the kiosk in front of the elder opens a staff screen
    /// with a single launch argument.
    static var pinnedScreenFromLaunchArguments: Int? {
        #if DEBUG
        let value = UserDefaults.standard.integer(forKey: "screen")
        return value > 0 ? value : nil
        #else
        nil
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            content

            // Deployment mode doesn't even have this button. The only way back is the session screen's
            // two-finger long press.
            if mode != .deployment {
                if chromeHidden {
                    // How to bring the bar back after hiding it: double-tap the top-left corner.
                    restoreTapTarget
                } else {
                    // Lines on the elder screens gather in the centre, so the bar goes in the bottom-left corner.
                    switcher
                        .padding(.leading, 20)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Theme.paper)
        .ignoresSafeArea()
        .fullScreenCover(item: $probe) { which in
            switch which {
            case .understanding: UnderstandingCheckView()
            case .reply:         ReplyLatencyView()
            case .plan:          ReplyPlanView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chromeHidden)
        .animation(.easeInOut(duration: 0.2), value: modeStore.mode)
    }

    @ViewBuilder
    private var content: some View {
        if let pinnedScreen {
            ScreenCatalog.view(number: pinnedScreen)
        } else {
            modeContent
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .pilot, .deployment:
            SessionView(modeStore: modeStore)
        case .gallery:
            switch gallerySection {
            case .elder:
                ScreenGalleryView(screens: ScreenCatalog.elderScreens, columns: 3)
            case .staff:
                ScreenGalleryView(screens: ScreenCatalog.staffScreens, columns: 2)
            }
        }
    }

    /// Shown only as a single small button so it doesn't cover the lines on the elder screens.
    private var switcher: some View {
        Menu {
            Picker("Mode", selection: $modeStore.mode) {
                ForEach(AppMode.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            if mode == .gallery {
                Divider()
                Picker("Screens", selection: $gallerySection) {
                    ForEach(GallerySection.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
            }
            Divider()
            // In front of the elder, even this button is removed, leaving a pure face screen.
            Button("Hide the switcher", systemImage: "eye.slash") {
                chromeHidden = true
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.cream(0.75))
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.55))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.cream(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
        .menuStyle(.borderlessButton)
    }

    private var restoreTapTarget: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: 90, height: 90)
            .onTapGesture(count: 2) { chromeHidden = false }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("Root") {
    RootView()
}
