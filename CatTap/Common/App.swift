import Foundation

final class App {
    
    static let shared = App()
    /// おもちゃのサイズ
    var size: ToySize = .small
    /// おもちゃの種類
    var toy: Toy = .standard(.bug)
    /// おもちゃの数
    var count = 1
    /// 透明モード
    var isHiddenMode = false
    ///間隔の時間
    var intervalTime = 5
    /// 消えている時間
    var hiddenTime = 5
    
    /// ジェスチャチュートリアルを表示しないか
    @Storage("isNeverShowKey", defaultValue: false)
    var isNeverShow: Bool
    /// 特定のスコア以上を取得して画面を戻った回数
    @Storage("satisfyScore", defaultValue: 0)
    var satisfyScore: Int
    /// AppStoreにレビューしてくれたか
    @Storage("isAppReview", defaultValue: false)
    var isAppReview: Bool
    /// ベストスコア
    @Storage("bestScore", defaultValue: 0)
    var bestScore: Int
    /// レコーディングするか
    @Storage("isRecording", defaultValue: false)
    var isRecording: Bool
    /// 写真から作ったおもちゃのID（登録した順）
    @Storage("photoToyIDs", defaultValue: [])
    var photoToyIDs: [UUID]

    private init() {}
}
