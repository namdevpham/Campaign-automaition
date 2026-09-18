import Foundation

struct LanguageCampaignProfile: Equatable {
    let language: CampaignLanguage
    let templateName: String
    let adAccountID: Int
    let externalAccountID: String
    let targetingLocales: [Int]?

    var summary: String {
        let localeText = targetingLocales?.map(String.init).joined(separator: ",") ?? "AUTO"
        return "\(templateName) • ad_account \(adAccountID) • locales \(localeText)"
    }
}

enum LanguageCampaignTemplateRouter {
    static func profile(
        for language: CampaignLanguage
    ) -> LanguageCampaignProfile {
        switch language {
        case .english:
            return LanguageCampaignProfile(
                language: .english,
                templateName: "Template_ETP_300_EN",
                adAccountID: 3727435,
                externalAccountID: "1730366391509645",
                targetingLocales: nil
            )
        case .russian:
            return LanguageCampaignProfile(
                language: .russian,
                templateName: "Template_ETP_301_RU",
                adAccountID: 3727428,
                externalAccountID: "1366664018402867",
                targetingLocales: [17]
            )
        case .arabic:
            return LanguageCampaignProfile(
                language: .arabic,
                templateName: "Template_ETP_302_AR",
                adAccountID: 3727434,
                externalAccountID: "1423878659586190",
                targetingLocales: [28]
            )
        case .romanian:
            return LanguageCampaignProfile(
                language: .romanian,
                templateName: "Template_ETP_303_RO",
                adAccountID: 3727429,
                externalAccountID: "1022535590782431",
                targetingLocales: [32]
            )
        case .croatian:
            return LanguageCampaignProfile(
                language: .croatian,
                templateName: "Template_ETP_304_HR",
                adAccountID: 3727441,
                externalAccountID: "1072505841928283",
                targetingLocales: [38]
            )
        }
    }

    static func campaignName(
        creativeRecordName: String,
        generatedJSON: String
    ) -> String {
        let creativeName = creativeRecordName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !creativeName.isEmpty {
            return creativeName
        }

        if let data = generatedJSON.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let internalName = root["name"] as? String {
            let clean = internalName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                return clean
            }
        }

        return "Ethopex_Campaign"
    }

    static func buildPayload(
        language: CampaignLanguage,
        campaignName: String,
        contentID: String,
        creativeID: String,
        facebookPage: EthopexFacebookPageAsset
    ) throws -> Data {
        let profile = profile(for: language)

        guard let contentInt = Int(contentID),
              let creativeInt = Int(creativeID) else {
            throw NSError(
                domain: "EthopexWorkspace",
                code: 3100,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "content_id/creative_id không phải số hợp lệ."
                ]
            )
        }

        guard let externalPageID = Int64(facebookPage.externalID) else {
            throw NSError(
                domain: "EthopexWorkspace",
                code: 3102,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Facebook Page external_id không hợp lệ: \(facebookPage.externalID)"
                ]
            )
        }

        var targeting: [String: Any] = [
            "geo_locations": [
                "countries": [
                    "US", "CA", "GB", "AU", "NZ", "DE", "FR", "NL", "CH", "AT",
                    "BE", "DK", "NO", "SE", "SG", "ES", "IT", "PL", "JP", "KR",
                    "FI", "IE", "PT", "CZ", "HU", "RO", "HR", "SK", "SI", "EE",
                    "LT", "LV", "CY", "MT", "TW", "HK", "AE", "SA", "QA"
                ],
                "location_types": ["home", "recent"]
            ],
            "brand_safety_content_filter_levels": [
                "FACEBOOK_RELAXED",
                "AN_RELAXED"
            ],
            "targeting_automation": [
                "advantage_audience": 1,
                "individual_setting": [
                    "age": 1,
                    "gender": 1
                ]
            ],
            "device_platforms": ["mobile", "desktop"],
            "publisher_platforms": [
                "facebook",
                "instagram",
                "messenger",
                "whatsapp",
                "threads"
            ],
            "facebook_positions": [
                "feed",
                "profile_feed",
                "marketplace",
                "right_hand_column",
                "biz_disco_feed",
                "notification",
                "story",
                "facebook_reels",
                "instream_video",
                "facebook_reels_overlay",
                "search"
            ],
            "instagram_positions": [
                "stream",
                "profile_feed",
                "explore_home",
                "story",
                "reels",
                "ig_search"
            ],
            "threads_positions": ["threads_stream"],
            "messenger_positions": ["story"],
            "whatsapp_positions": ["status"]
        ]

        if let locales = profile.targetingLocales {
            targeting["locales"] = locales
        }

        // These five profiles are copied from the user's five HAR templates.
        // Only dynamic campaign/content/creative/page identifiers are replaced.
        let payload: [String: Any] = [
            "name": campaignName,
            "pixel_id_arb": 5,
            "ad_account_id": profile.adAccountID,
            "facebook_page_id": externalPageID,
            "external_account_id": profile.externalAccountID,
            "campaign": [
                "source_payload": [
                    "name": campaignName,
                    "objective": "OUTCOME_SALES",
                    "status": "PAUSED",
                    "buying_type": "AUCTION",
                    "bid_strategy": "LOWEST_COST_WITHOUT_CAP",
                    "daily_budget": 1,
                    "special_ad_categories": [],
                    "special_ad_category_country": [],
                    "dsa_beneficiary": "MAYBIC LIMITED",
                    "dsa_payor": "MAYBIC LIMITED"
                ],
                "ad_groups": [[
                    "type_run": "tomorrow",
                    "source_payload": [
                        "name": "New Sales Ad Set",
                        "status": "PAUSED",
                        "optimization_goal": "VALUE",
                        "billing_event": "IMPRESSIONS",
                        "attribution_spec": [
                            [
                                "event_type": "CLICK_THROUGH",
                                "window_days": 7
                            ],
                            [
                                "event_type": "VIEW_THROUGH",
                                "window_days": 1
                            ],
                            [
                                "event_type": "ENGAGED_VIDEO_VIEW",
                                "window_days": 1
                            ]
                        ],
                        "promoted_object": [
                            "pixel_id": 2324585647945259,
                            "custom_event_type": "PURCHASE"
                        ],
                        "destination_type": "WEBSITE",
                        "targeting": targeting,
                        "regional_regulated_categories": [
                            "TAIWAN_UNIVERSAL",
                            "SINGAPORE_UNIVERSAL"
                        ],
                        "dsa_beneficiary": "MAYBIC LIMITED",
                        "dsa_payor": "MAYBIC LIMITED"
                    ],
                    "ads": [[
                        "content_id": contentInt,
                        "creative_id": creativeInt,
                        "facebook_page_id": facebookPage.id,
                        "domain": "",
                        "source_payload": [
                            "name": "New Sales Ad",
                            "status": "ACTIVE"
                        ]
                    ]]
                ]]
            ]
        ]

        try validatePayload(
            payload,
            profile: profile
        )

        return try JSONSerialization.data(
            withJSONObject: payload,
            options: [
                .prettyPrinted,
                .sortedKeys,
                .withoutEscapingSlashes
            ]
        )
    }

    private static func validatePayload(
        _ payload: [String: Any],
        profile: LanguageCampaignProfile
    ) throws {
        guard payload["ad_account_id"] as? Int == profile.adAccountID,
              payload["external_account_id"] as? String == profile.externalAccountID else {
            throw NSError(
                domain: "EthopexWorkspace",
                code: 3190,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "TEMPLATE MISMATCH — \(profile.language.shortLabel): account routing không đúng."
                ]
            )
        }

        guard let campaign = payload["campaign"] as? [String: Any],
              let adGroups = campaign["ad_groups"] as? [[String: Any]],
              let first = adGroups.first,
              let sourcePayload = first["source_payload"] as? [String: Any],
              let targeting = sourcePayload["targeting"] as? [String: Any] else {
            throw NSError(
                domain: "EthopexWorkspace",
                code: 3191,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "TEMPLATE MISMATCH — thiếu targeting payload."
                ]
            )
        }

        let locales = targeting["locales"] as? [Int]
        if locales != profile.targetingLocales {
            throw NSError(
                domain: "EthopexWorkspace",
                code: 3192,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "TEMPLATE MISMATCH — \(profile.language.shortLabel): locales không đúng."
                ]
            )
        }
    }
}

// Backward-compatible symbol for old UI/debug paths.
struct DefaultFacebookCampaignTemplateV1 {
    static let name = "Language Router — EN/RU/AR/RO/HR"

    static func campaignName(
        creativeRecordName: String,
        generatedJSON: String
    ) -> String {
        LanguageCampaignTemplateRouter.campaignName(
            creativeRecordName: creativeRecordName,
            generatedJSON: generatedJSON
        )
    }
}
