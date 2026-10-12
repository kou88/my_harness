import Foundation

/// ページ番号は1始まり。表紙は単独、本文は2–3、4–5…の順で開く。
struct BookPageLayout {
    let pageCount: Int
    let spread: Bool

    func visiblePages(_ page: Int) -> ClosedRange<Int> {
        let selected = min(max(1, page), pageCount)
        guard spread, selected > 1 else { return selected...selected }
        let first = selected - selected % 2
        return first...min(first + 1, pageCount)
    }

    func previous(_ page: Int) -> Int {
        let first = visiblePages(page).lowerBound
        return max(1, first - (spread && first > 2 ? 2 : 1))
    }

    func next(_ page: Int) -> Int {
        min(pageCount, visiblePages(page).upperBound + 1)
    }

    /// 見えている左右のページに加え、その前後2ページを保持する。
    func preparedPages(_ page: Int) -> ClosedRange<Int> {
        let visible = visiblePages(page)
        return max(1, visible.lowerBound - 2)...min(pageCount, visible.upperBound + 2)
    }
}
