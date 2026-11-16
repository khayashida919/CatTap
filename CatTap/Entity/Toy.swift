import Foundation

/// ゲームで使うおもちゃ
enum Toy: Equatable {
    /// 無料で使える虫・鳥・魚
    case standard(ToyKind)
    /// レーザーポインター（プレミアム）
    case laser
    /// ねこじゃらし（プレミアム）
    case teaser
    /// ねずみ（プレミアム）
    case mouse
    /// ちょうちょ（プレミアム）
    case butterfly
    /// 毛糸玉（プレミアム）
    case yarn
    /// 利用者が写真から作ったおもちゃ（プレミアム）
    case photo(UUID)

    /// 写真のおもちゃ以外のプレミアムのおもちゃ。選択画面と購入画面はこの順に並べる
    static let premiumToys: [Toy] = [.mouse, .butterfly, .laser, .teaser, .yarn]

    /// プレミアムを買わないと使えないか
    var isPremium: Bool {
        if case .standard = self {
            return false
        }
        return true
    }
}
