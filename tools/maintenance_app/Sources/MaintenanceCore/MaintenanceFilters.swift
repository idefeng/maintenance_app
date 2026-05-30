import Foundation

public struct CleanupCandidateFilter: Equatable, Sendable {
    public let searchText: String
    public let status: String?
    public let category: String?

    public init(searchText: String = "", status: String? = nil, category: String? = nil) {
        self.searchText = searchText
        self.status = status
        self.category = category
    }

    public func apply(to candidates: [CleanupCandidate]) -> [CleanupCandidate] {
        candidates.filter { candidate in
            matches(candidate.status, filter: status)
                && matches(candidate.category, filter: category)
                && SearchMatcher.matches(
                    searchText,
                    in: [
                        candidate.path,
                        candidate.category,
                        candidate.reason,
                        candidate.riskLevel,
                        candidate.status,
                        candidate.error ?? ""
                    ]
                )
        }
    }
}

public struct LoginItemFilter: Equatable, Sendable {
    public let searchText: String
    public let category: String?
    public let duplicateOnly: Bool

    public init(searchText: String = "", category: String? = nil, duplicateOnly: Bool = false) {
        self.searchText = searchText
        self.category = category
        self.duplicateOnly = duplicateOnly
    }

    public func apply(to section: LoginItemsSection) -> [LoginItem] {
        let duplicateNames = Set(section.duplicateDisplayNames.map { SearchMatcher.normalized($0.displayName) })
        return section.items.filter { item in
            matches(item.category, filter: category)
                && (!duplicateOnly || duplicateNames.contains(SearchMatcher.normalized(item.displayName)))
                && SearchMatcher.matches(
                    searchText,
                    in: [
                        item.displayName,
                        item.name ?? "",
                        item.developerName ?? "",
                        item.itemType ?? "",
                        item.disposition ?? "",
                        item.identifier ?? "",
                        item.urlPath ?? "",
                        item.executablePath ?? "",
                        item.category,
                        item.suggestedAction,
                        item.riskLevel,
                        item.classificationReason
                    ]
                )
        }
    }
}

private func matches(_ value: String, filter: String?) -> Bool {
    guard let filter, !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return true
    }
    return SearchMatcher.normalized(value) == SearchMatcher.normalized(filter)
}

enum SearchMatcher {
    static func matches(_ query: String, in values: [String]) -> Bool {
        let tokens = query
            .split(whereSeparator: \.isWhitespace)
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            return true
        }

        // 多关键词搜索采用 AND 语义，避免宽泛查询把无关条目一起带出来。
        let haystack = normalized(values.joined(separator: " "))
        return tokens.allSatisfy { haystack.contains($0) }
    }

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
