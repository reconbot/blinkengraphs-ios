import BlinkengraphsCore
import Foundation

enum AppGroup {
    /// The group ID comes from the `AppGroup` Info.plist key, which the build fills from `APP_GROUP`.
    static var snapshotStore: VerdictSnapshotStore? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String,
              let defaults = UserDefaults(suiteName: id)
        else { return nil }
        return VerdictSnapshotStore(defaults: defaults)
    }
}
