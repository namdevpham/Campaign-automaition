import Foundation

enum CreativeDisplayLinkPreset: String, CaseIterable {
    case search = "search.com"
    case results = "results.com"
    case info = "info.com"

    var displayName: String {
        switch self {
        case .search: return "search.com"
        case .results: return "results.com"
        case .info: return "info.com"
        }
    }
}

final class CreativeDisplayLinkConfig {
    static let shared = CreativeDisplayLinkConfig()
    private let key = "creative.display.link.preset"

    private init() {}

    var selected: CreativeDisplayLinkPreset {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key) else {
                return .search
            }

            // V0.16 migration: old versions stored https://search.com etc.
            let normalized = raw
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            return CreativeDisplayLinkPreset(rawValue: normalized) ?? .search
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    var url: String {
        selected.rawValue
    }
}

final class EthopexConfig {
    static let shared = EthopexConfig()
    let tokenAccount = "ethopex.api.token"

    private init() {}

    var token: String? {
        SecureStore.shared.read(account: tokenAccount)
    }

    func save(token: String) throws {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            try SecureStore.shared.save(clean, account: tokenAccount)
        }
    }
}

enum EthopexContentRemoteState {
    case exists
    case missing
}

struct EthopexContentLinkResult {
    let url: String
    let source: String
    let rawResponse: String?
}

struct EthopexContentResult {
    let groupID: String
    let contentID: String
    let rawResponse: String
}

struct EthopexCoverAsset {
    let assetID: String
    let name: String
    let filePath: String
    let publicURL: String
    let rawResponse: String
}

struct EthopexMediaResult {
    let mediaID: String
    let fileURL: String
    let filePath: String
    let rawResponse: String
}

struct EthopexCreativeResult {
    let creativeID: String
    let rawResponse: String
}

struct EthopexCampaignResult {
    let campaignID: String
    let adSetID: String
    let adID: String
    let rawResponse: String
}

enum EthopexAPIError: Error, LocalizedError {
    case missingToken
    case invalidURL
    case badStatus(Int, String)
    case invalidResponse
    case noContentID
    case coverAssetNotFound(String)
    case noMediaURL
    case noCreativeID
    case noCampaignID

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Chưa có Ethopex Bearer Token."
        case .invalidURL:
            return "Ethopex API URL không hợp lệ."
        case .badStatus(let code, let body):
            return "Ethopex HTTP \(code): \(body)"
        case .invalidResponse:
            return "Ethopex trả response không đọc được."
        case .noContentID:
            return "Ethopex tạo Content nhưng response không có content_id."
        case .coverAssetNotFound(let name):
            return "Không tìm thấy Cover '\(name)' trong Ethopex Media Library."
        case .noMediaURL:
            return "Upload ảnh thành công nhưng response không có file_url."
        case .noCreativeID:
            return "Create Creative thành công nhưng response không có id."
        case .noCampaignID:
            return "Create Campaign thành công nhưng response thiếu campaign/ad group/ad id."
        }
    }
}

final class EthopexAPIClient {
    let contentURL = "https://api-multi-be.ethopex.dev/api/v2/blog/contents/bulk"
    let assetsURL = "https://api-multi-be.ethopex.dev/api/v2/assets"
    let assetCDNBaseURL = "https://acdn.dofez.com"
    let permissionsURL = "https://api.ethopex.dev/api/v1/profile/permissions"
    let uploadURL = "https://api.ethopex.dev/api/v1/storage/r2-arb/upload"
    let creativeURL = "https://api.ethopex.dev/api/v1/creatives"
    let facebookCampaignURL = "https://api.ethopex.dev/api/v1/campaigns/facebook"
    let facebookPagesURL = "https://api.ethopex.dev/api/v1/my-asset-groups/fb-pages"

    private func bearerToken() throws -> String {
        guard let token = EthopexConfig.shared.token,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EthopexAPIError.missingToken
        }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func authorizedJSONRequest(url: URL, method: String, body: Data? = nil) throws -> URLRequest {
        let token = try bearerToken()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body
        request.timeoutInterval = 120
        return request
    }

    func testConnection(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: permissionsURL) else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        do {
            let request = try authorizedJSONRequest(url: url, method: "GET")

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    DispatchQueue.main.async {
                        completion(.failure(EthopexAPIError.invalidResponse))
                    }
                    return
                }

                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

                guard (200...299).contains(http.statusCode) else {
                    DispatchQueue.main.async {
                        completion(.failure(
                            EthopexAPIError.badStatus(http.statusCode, String(raw.prefix(700)))
                        ))
                    }
                    return
                }

                DispatchQueue.main.async {
                    completion(.success("Đã kết nối Ethopex • Token hợp lệ"))
                }
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }


    func findImageAsset(
        named assetName: String,
        completion: @escaping (Result<EthopexCoverAsset, Error>) -> Void
    ) {
        guard var components = URLComponents(string: assetsURL) else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: "12"),
            URLQueryItem(name: "content_type_id", value: "4"),
            URLQueryItem(name: "file_type", value: "image"),
            URLQueryItem(name: "search", value: assetName)
        ]

        guard let url = components.url else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        do {
            let request = try authorizedJSONRequest(url: url, method: "GET")

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(EthopexAPIError.invalidResponse))
                    return
                }

                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

                guard (200...299).contains(http.statusCode) else {
                    completion(.failure(
                        EthopexAPIError.badStatus(http.statusCode, String(raw.prefix(1800)))
                    ))
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["data"] as? [[String: Any]] else {
                    completion(.failure(EthopexAPIError.invalidResponse))
                    return
                }

                let cleanTarget = assetName.trimmingCharacters(in: .whitespacesAndNewlines)

                let exact = items.first { item in
                    let name = (item["name"] as? String ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.compare(
                        cleanTarget,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame
                }

                guard let found = exact,
                      let filePath = found["file_path"] as? String,
                      !filePath.isEmpty else {
                    completion(.failure(EthopexAPIError.coverAssetNotFound(assetName)))
                    return
                }

                // The Library API returns only file_path.
                // HAR confirms the public asset is served from:
                // https://acdn.dofez.com/<file_path>
                let publicURL: String
                if let direct = Self.firstPublicURL(in: found) {
                    publicURL = direct
                } else {
                    let cleanPath = filePath.hasPrefix("/")
                        ? String(filePath.dropFirst())
                        : filePath
                    publicURL = "\(self.assetCDNBaseURL)/\(cleanPath)"
                }

                guard Self.isPublicHTTPURL(publicURL) else {
                    completion(.failure(EthopexAPIError.noMediaURL))
                    return
                }

                completion(.success(
                    EthopexCoverAsset(
                        assetID: Self.stringValue(found["id"]) ?? "",
                        name: found["name"] as? String ?? assetName,
                        filePath: filePath,
                        publicURL: publicURL,
                        rawResponse: raw
                    )
                ))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }


    func resolveContentLink(
        contentID: String,
        completion: @escaping (Result<EthopexContentLinkResult, Error>) -> Void
    ) {
        let cleanID = contentID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanID.isEmpty else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        // First try Content detail API. If it exposes a public URL, use it.
        let detailString =
            "https://api-multi-be.ethopex.dev/api/v2/blog/contents/\(cleanID)"

        guard let detailURL = URL(string: detailString) else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        do {
            let request = try authorizedJSONRequest(url: detailURL, method: "GET")

            URLSession.shared.dataTask(with: request) { data, response, error in
                let fallback = EthopexContentLinkResult(
                    url: "https://app.ethopex.dev/content/\(cleanID)/edit?category=blog-content",
                    source: "integration-fallback",
                    rawResponse: data.flatMap { String(data: $0, encoding: .utf8) }
                )

                // A resolver failure must not block Creative creation.
                // We only need a non-empty http(s) display link at this integration stage.
                if error != nil {
                    completion(.success(fallback))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.success(fallback))
                    return
                }

                guard (200...299).contains(http.statusCode),
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) else {
                    completion(.success(fallback))
                    return
                }

                if let found = Self.findContentPublicURL(in: json) {
                    completion(.success(
                        EthopexContentLinkResult(
                            url: found,
                            source: "content-api",
                            rawResponse: String(data: data, encoding: .utf8)
                        )
                    ))
                    return
                }

                completion(.success(fallback))
            }.resume()

        } catch {
            completion(.success(
                EthopexContentLinkResult(
                    url: "https://app.ethopex.dev/content/\(cleanID)/edit?category=blog-content",
                    source: "integration-fallback",
                    rawResponse: nil
                )
            ))
        }
    }

func checkContentExists(
        contentID: String,
        completion: @escaping (Result<EthopexContentRemoteState, Error>) -> Void
    ) {
        let cleanID = contentID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanID.isEmpty,
              let url = URL(
                string: "https://api-multi-be.ethopex.dev/api/v2/blog/contents/\(cleanID)/pages"
              ) else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        do {
            let request = try authorizedJSONRequest(url: url, method: "GET")

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(EthopexAPIError.invalidResponse))
                    return
                }

                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

                switch http.statusCode {
                case 200...299:
                    completion(.success(.exists))

                case 404, 410:
                    // Content no longer exists remotely.
                    completion(.success(.missing))

                default:
                    // Never recreate blindly on auth/server/validation errors.
                    completion(.failure(
                        EthopexAPIError.badStatus(
                            http.statusCode,
                            String(raw.prefix(1200))
                        )
                    ))
                }
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    func createContent(
        payloadData: Data,
        completion: @escaping (Result<EthopexContentResult, Error>) -> Void
    ) {
        guard let url = URL(string: contentURL) else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        do {
            let request = try authorizedJSONRequest(url: url, method: "POST", body: payloadData)

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(EthopexAPIError.invalidResponse))
                    return
                }

                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

                guard (200...299).contains(http.statusCode) else {
                    completion(.failure(
                        EthopexAPIError.badStatus(http.statusCode, String(raw.prefix(2000)))
                    ))
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(EthopexAPIError.invalidResponse))
                    return
                }

                let groupID = EthopexAPIClient.stringValue(json["group_id"]) ?? ""
                let items = json["items"] as? [[String: Any]] ?? []
                guard let first = items.first,
                      let contentID = EthopexAPIClient.stringValue(first["content_id"]),
                      !contentID.isEmpty else {
                    completion(.failure(EthopexAPIError.noContentID))
                    return
                }

                completion(.success(
                    EthopexContentResult(
                        groupID: groupID,
                        contentID: contentID,
                        rawResponse: raw
                    )
                ))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    func uploadMedia(
        fileURL: URL,
        completion: @escaping (Result<EthopexMediaResult, Error>) -> Void
    ) {
        guard let url = URL(string: uploadURL) else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        do {
            let token = try bearerToken()
            let fileData = try Data(contentsOf: fileURL)
            let boundary = "Boundary-\(UUID().uuidString)"
            let mimeType = Self.mimeType(for: fileURL.pathExtension)
            let filename = fileURL.lastPathComponent

            var body = Data()

            func append(_ text: String) {
                if let data = text.data(using: .utf8) {
                    body.append(data)
                }
            }

            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
            append("Content-Type: \(mimeType)\r\n\r\n")
            body.append(fileData)
            append("\r\n--\(boundary)--\r\n")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            request.timeoutInterval = 180

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(EthopexAPIError.invalidResponse))
                    return
                }

                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

                guard (200...299).contains(http.statusCode) else {
                    completion(.failure(
                        EthopexAPIError.badStatus(http.statusCode, String(raw.prefix(2000)))
                    ))
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["data"] as? [[String: Any]],
                      let first = items.first,
                      let fileURL = first["file_url"] as? String,
                      !fileURL.isEmpty else {
                    completion(.failure(EthopexAPIError.noMediaURL))
                    return
                }

                completion(.success(
                    EthopexMediaResult(
                        mediaID: Self.stringValue(first["id"]) ?? "",
                        fileURL: fileURL,
                        filePath: first["file_path"] as? String ?? "",
                        rawResponse: raw
                    )
                ))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    func createCreative(
        payloadData: Data,
        completion: @escaping (Result<EthopexCreativeResult, Error>) -> Void
    ) {
        guard let url = URL(string: creativeURL) else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        do {
            let request = try authorizedJSONRequest(url: url, method: "POST", body: payloadData)

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(EthopexAPIError.invalidResponse))
                    return
                }

                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

                guard (200...299).contains(http.statusCode) else {
                    completion(.failure(
                        EthopexAPIError.badStatus(http.statusCode, String(raw.prefix(2500)))
                    ))
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let creativeID = Self.stringValue(json["id"]),
                      !creativeID.isEmpty else {
                    completion(.failure(EthopexAPIError.noCreativeID))
                    return
                }

                completion(.success(
                    EthopexCreativeResult(
                        creativeID: creativeID,
                        rawResponse: raw
                    )
                ))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }



    func fetchFacebookPages(
        completion: @escaping (Result<[EthopexFacebookPageAsset], Error>) -> Void
    ) {
        fetchFacebookPagesPage(
            page: 1,
            accumulated: [],
            completion: completion
        )
    }

    private func fetchFacebookPagesPage(
        page: Int,
        accumulated: [EthopexFacebookPageAsset],
        completion: @escaping (Result<[EthopexFacebookPageAsset], Error>) -> Void
    ) {
        guard var components = URLComponents(string: facebookPagesURL) else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        components.queryItems = [
            URLQueryItem(name: "sort_by", value: "display_name"),
            URLQueryItem(name: "sort_order", value: "asc"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: "200")
        ]

        guard let url = components.url else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        do {
            let request = try authorizedJSONRequest(
                url: url,
                method: "GET"
            )

            URLSession.shared.dataTask(with: request) {
                data,
                response,
                error in

                if let error {
                    completion(.failure(error))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(EthopexAPIError.invalidResponse))
                    return
                }

                let raw = data.flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? ""

                guard (200...299).contains(http.statusCode) else {
                    completion(.failure(
                        EthopexAPIError.badStatus(
                            http.statusCode,
                            String(raw.prefix(2500))
                        )
                    ))
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(
                        with: data
                      ) as? [String: Any],
                      let items = json["data"] as? [[String: Any]] else {
                    completion(.failure(EthopexAPIError.invalidResponse))
                    return
                }

                let parsed: [EthopexFacebookPageAsset] = items.compactMap {
                    item in

                    guard let idString = Self.stringValue(item["id"]),
                          let id = Int(idString),
                          let externalID = Self.stringValue(
                            item["external_id"]
                          ),
                          !externalID.isEmpty else {
                        return nil
                    }

                    let name =
                        (item["display_name"] as? String ?? "")
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                    guard !name.isEmpty else { return nil }

                    let status =
                        item["status"] as? String ?? ""

                    let pictureURL =
                        item["picture_url"] as? String ?? ""

                    let available =
                        item["available"] as? Bool ?? true

                    return EthopexFacebookPageAsset(
                        id: id,
                        externalID: externalID,
                        displayName: name,
                        status: status,
                        pictureURL: pictureURL,
                        available: available
                    )
                }

                let combined = accumulated + parsed

                let meta = json["meta"] as? [String: Any]
                let totalPages =
                    Int(Self.stringValue(meta?["total_pages"]) ?? "1")
                    ?? 1

                if page < totalPages {
                    self.fetchFacebookPagesPage(
                        page: page + 1,
                        accumulated: combined,
                        completion: completion
                    )
                    return
                }

                let final = combined
                    .filter {
                        $0.available &&
                        $0.status.lowercased() != "inactive"
                    }
                    .sorted {
                        $0.displayName.localizedCaseInsensitiveCompare(
                            $1.displayName
                        ) == .orderedAscending
                    }

                completion(.success(final))
            }.resume()

        } catch {
            completion(.failure(error))
        }
    }


    func createFacebookCampaign(
        payloadData: Data,
        completion: @escaping (Result<EthopexCampaignResult, Error>) -> Void
    ) {
        guard let url = URL(string: facebookCampaignURL) else {
            completion(.failure(EthopexAPIError.invalidURL))
            return
        }

        do {
            let request = try authorizedJSONRequest(
                url: url,
                method: "POST",
                body: payloadData
            )

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(EthopexAPIError.invalidResponse))
                    return
                }

                let raw = data.flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? ""

                guard (200...299).contains(http.statusCode) else {
                    completion(.failure(
                        EthopexAPIError.badStatus(
                            http.statusCode,
                            String(raw.prefix(3500))
                        )
                    ))
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let campaign = json["campaign"] as? [String: Any],
                      let campaignID = Self.stringValue(campaign["id"]),
                      let adGroups = json["ad_groups"] as? [[String: Any]],
                      let firstGroup = adGroups.first,
                      let adSetID = Self.stringValue(firstGroup["id"]),
                      let ads = json["ads"] as? [[String: Any]],
                      let firstAd = ads.first,
                      let adID = Self.stringValue(firstAd["id"]),
                      !campaignID.isEmpty,
                      !adSetID.isEmpty,
                      !adID.isEmpty else {
                    completion(.failure(EthopexAPIError.noCampaignID))
                    return
                }

                completion(.success(
                    EthopexCampaignResult(
                        campaignID: campaignID,
                        adSetID: adSetID,
                        adID: adID,
                        rawResponse: raw
                    )
                ))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    private static func isPublicHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return false
        }
        return true
    }

    private static func firstPublicURL(in object: Any) -> String? {
        let preferredKeys = [
            "file_url",
            "public_url",
            "url",
            "image_url",
            "preview_url",
            "thumbnail_url",
            "cdn_url"
        ]

        if let dict = object as? [String: Any] {
            for key in preferredKeys {
                if let value = dict[key] as? String, isPublicHTTPURL(value) {
                    return value
                }
            }

            for value in dict.values {
                if let found = firstPublicURL(in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = firstPublicURL(in: value) {
                    return found
                }
            }
        } else if let text = object as? String, isPublicHTTPURL(text) {
            return text
        }

        return nil
    }


    private static func findContentPublicURL(in object: Any) -> String? {
        let preferredKeys = [
            "link_url",
            "public_url",
            "landing_url",
            "display_url",
            "preview_url",
            "share_url",
            "url"
        ]

        if let dict = object as? [String: Any] {
            for key in preferredKeys {
                if let value = dict[key] as? String,
                   isUsableContentURL(value) {
                    return value
                }
            }

            for value in dict.values {
                if let found = findContentPublicURL(in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = findContentPublicURL(in: value) {
                    return found
                }
            }
        }

        return nil
    }

    private static func isUsableContentURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host?.lowercased() else {
            return false
        }

        // Never use backend API or media files as an ad destination URL.
        if host == "api.ethopex.dev" ||
           host == "api-multi-be.ethopex.dev" ||
           host.hasSuffix(".r2.dev") ||
           host == "acdn.dofez.com" {
            return false
        }

        let path = url.path.lowercased()
        let mediaExtensions = [
            ".jpg", ".jpeg", ".png", ".webp", ".gif",
            ".mp4", ".mov", ".avi", ".webm"
        ]
        if mediaExtensions.contains(where: { path.hasSuffix($0) }) {
            return false
        }

        return true
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? Int { return String(value) }
        if let value = value as? Int64 { return String(value) }
        if let value = value as? Double {
            if value.rounded() == value { return String(Int(value)) }
            return String(value)
        }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
}
