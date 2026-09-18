import Foundation

struct EthopexFacebookPageAsset: Equatable {
    let id: Int
    let externalID: String
    let displayName: String
    let status: String
    let pictureURL: String
    let available: Bool

    var menuTitle: String {
        "\(id) · \(displayName) · \(externalID)"
    }
}

final class FacebookPageSelectionConfig {
    static let shared = FacebookPageSelectionConfig()

    private let internalIDKey = "campaign.facebook.page.internal_id"
    private let externalIDKey = "campaign.facebook.page.external_id"
    private let nameKey = "campaign.facebook.page.name"

    let fallback = EthopexFacebookPageAsset(
        id: 1295446,
        externalID: "119394474601402",
        displayName: "The Quiz Library",
        status: "active",
        pictureURL: "",
        available: true
    )

    private init() {}

    var selectedPage: EthopexFacebookPageAsset {
        get {
            let internalID = UserDefaults.standard.integer(forKey: internalIDKey)
            let externalID = UserDefaults.standard.string(forKey: externalIDKey) ?? ""
            let name = UserDefaults.standard.string(forKey: nameKey) ?? ""

            guard internalID > 0,
                  !externalID.isEmpty,
                  !name.isEmpty else {
                return fallback
            }

            return EthopexFacebookPageAsset(
                id: internalID,
                externalID: externalID,
                displayName: name,
                status: "active",
                pictureURL: "",
                available: true
            )
        }
        set {
            UserDefaults.standard.set(newValue.id, forKey: internalIDKey)
            UserDefaults.standard.set(newValue.externalID, forKey: externalIDKey)
            UserDefaults.standard.set(newValue.displayName, forKey: nameKey)
        }
    }
}
