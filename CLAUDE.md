# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

CatTap（App Store 名「きゃっぷ - 猫が遊ぶゲーム」）は、画面上を動く虫・鳥・魚を猫に叩かせて遊ぶ iOS アプリ。UIKit と Storyboard と SpriteKit で作られている。外部依存（SPM・CocoaPods など）はない。ローカライズは日本語（`ja`）のみで、コード中のコメントやコミットメッセージも日本語で書いている。

## コマンド

テストターゲットとリンターはない。シミュレータでアプリをビルドし、起動して動作を確かめる。

シミュレータ向けには次のコマンドでビルドする。署名は手動設定で名前付きのプロファイルを使うので、`CODE_SIGNING_ALLOWED=NO` を付ける。

```bash
xcodebuild -project CatTap.xcodeproj -scheme CatTap -configuration Release \
  -destination "platform=iOS Simulator,id=<SIMULATOR_UDID>" \
  -derivedDataPath work/DerivedData-simulator CODE_SIGNING_ALLOWED=NO build
```

`<SIMULATOR_UDID>` は `xcrun simctl list devices available` で調べる。

App Store 向けのアーカイブは、1.0.4 のときに次のコマンドで作った。

```bash
xcodebuild -project CatTap.xcodeproj -scheme CatTap -configuration Release \
  -destination generic/platform=iOS \
  -archivePath work/release/CatTap.xcarchive -derivedDataPath work/DerivedData-release \
  "CODE_SIGN_IDENTITY=Apple Distribution" PROVISIONING_PROFILE_SPECIFIER=CatTap_appstore_20261008 archive
```

pbxproj の Release に設定されたプロファイルは `CatTap_appstore` で、上のコマンドではコマンドライン引数で日付付きのプロファイルに置き換えている。プロファイルを作り直したら、この引数も合わせて変える。IPA は `xcodebuild -exportArchive` で書き出し、`-exportOptionsPlist` に `release/<version>/ExportOptions.plist` を渡す。書き出したときに実行したコマンドはログに残っていない。

## アーキテクチャ

### 画面遷移

`Main.storyboard` の UINavigationController が起点で、ルートは `TopViewController`。Top から設定画面（`SettingTableViewController`）とテスター紹介画面（`TesterViewController`）へは Storyboard の show segue で移る。

ゲーム画面の `FreeGameViewController` だけはコードから開く。`instantiateViewController(identifier:creator:)` で生成するときに、ゲーム終了時に呼ぶ `onEnd` クロージャを渡してから push する。`init(coder:)` は `fatalError()` にしてあるので、segue の遷移先にはできない。ゲーム画面では戻るボタンを隠しており、画面を閉じる方法は 2 本指ダブルタップ（Storyboard 上の UITapGestureRecognizer）だけ。ジェスチャーの説明画面（`GestureTutorialViewController`）は、`isNeverShow` が false のときに、ゲーム画面の `viewDidLoad` から segue `toGestureTutorialViewController` でモーダル表示する。この説明画面には、マナーモードを解除するとおもちゃの音が鳴ることも書いている。

設定画面の「もっとおもちゃ」ボタンを押すと、おもちゃの選択画面（`ToyPickerViewController`）をコードで生成して push する。この画面は Storyboard を使わず、コードだけで組んでいる。設定画面の表は行を選べない設定（`allowsSelection="NO"`）なので、画面を移る操作は行ではなくボタンに付けている。

プレミアムを持っていないときは、選択画面のいちばん上に「きゃっぷ プレミアム」の札を出す。札か鍵の付いたおもちゃを押すと、購入画面（`PaywallViewController`）をシートで開く。購入画面もコードだけで組んでいる。

`PreviewViewController` には Storyboard ID が付いているが、Swift のコードからは使われていない。

### 状態の持ち方

状態はシングルトンの `App.shared`（`Common/App.swift`）にまとめている。

- おもちゃの大きさ・種類（`toy`）・数と、透明モードの設定（オン・オフ、間隔の時間、消えている時間）は `@Storage` を付けていないので、メモリにしか持たない。アプリを起動し直すと初期値に戻る。
- `@Storage` を付けたプロパティ（`isNeverShow`、`bestScore`、`satisfyScore`、`isAppReview`、`isRecording`、`photoToyIDs`、`motionStyle`）は、値を JSON にエンコードした `Data` として UserDefaults に保存する。

設定画面が `App.shared` に値を書き込み、`ToyScene.didMove(to:)` がゲーム開始時にその値を読む。

### ゲーム画面

`FreeGameViewController` の `containerView` には Storyboard で `customClass="SKView"` を指定してある。この SKView で `ToyScene.sks` から読み込んだシーンを表示する。`ToyScene` は `.sks` 内のノードを名前（`toy`、`pointEffect`、`pointLabel`、`bestLabel`）で取り出すので、`.sks` 側でノード名を変えるとコードも直す必要がある。

- おもちゃは `toy` ノードを `copy()` して設定された数まで増やし、そのあとで `setUp(_:as:)` がすべての `toy` ノードに見た目と大きさを設定する。新しい種類のおもちゃの設定もここに書き、複製したノードにも同じ設定が入るようにする。しのび足のときは、ぶつかり方の円（`setUpPhysics(_:)`）も、おもちゃの大きさに合わせてノードごとに作り直す。
- 動き方は設定画面の「おもちゃの動き」で「すいすい」（`.classic`）と「しのび足」（`.stealthy`、初期値）から選び、`App.shared.motionStyle`（`ToyMotion.Style`）に保存する。
- 「すいすい」は 1.0.4 までの動き。`impulseInterval` 秒ごとにすべてのおもちゃを乱数の向きと強さで押し出し、0〜10 秒の乱数の間隔ですべて止める。ねずみ・レーザーポインター・ちょうちょは、押し出す間隔と強さを変えている。画面のどこを叩いても、最初のおもちゃを押し出す。ぶつかり方は `ToyScene.sks` の円をそのまま使い、壁は右と上だけ画面の外まで広げている。体の向きはねずみだけ走る向きに合わせる。
- 「しのび足」では、おもちゃは獲物らしく動く。ノードごとに、素早く走る・ぴたっと止まる・その場でぴくぴく動く・こっそり歩いてから急に走り出す・いちばん近い画面の端に半分ほど隠れて顔を出す、を組み合わせて繰り返す。走り出すときは短い時間をかけて速くなり、ぴたっと止まるおもちゃは止まる直前に速さを少しゆるめ、隠れていたあとは速いほうの速さで飛び出す。叩かれたおもちゃと、すぐ近くを叩かれたおもちゃは、叩かれた場所から離れる向きに逃げてから少し止まる。速さや割合は `ToyMotion`（`Scene/FreeGame/ToyMotion.swift`）がおもちゃの種類ごとに決め、動かす処理は `ToyScene` の SKAction（キー `motion`）にある。画面の縁の壁は、おもちゃが半分ほど隠れられるように少し外側に置いている。
- しのび足では、iPad でも iPhone と同じくらいの勢いに見えるように、走る・歩く・逃げる速さは画面の短い辺の長さに合わせて変える（幅 390pt の iPhone を 1 倍として 0.9〜1.8 倍）。
- しのび足では体の向きを `update(_:)` で進む向きに合わせる。虫は頭を進む向きへ回し、魚とねずみは左右を反転し、毛糸玉は転がる速さに合わせて回す。ほかのおもちゃは回さない（写真のおもちゃがさかさまにならないように）。
- おもちゃの種類は `Toy`（`Entity/Toy.swift`）で表す。無料の虫・鳥・魚は `.standard(ToyKind)`、プレミアムのおもちゃは `.mouse`（ねずみ）、`.butterfly`（ちょうちょ）、`.laser`（レーザーポインター）、`.teaser`（ねこじゃらし）、`.yarn`（毛糸玉）、`.photo(UUID)`（写真のおもちゃ）。
- 虫・鳥・魚のテクスチャ名は `String(describing: kind)` で決めている。そのため `ToyKind` の case 名と Assets のイメージセット名（`bug`、`bird`、`fish`）をそろえておく必要がある。写真のおもちゃ以外のプレミアムのおもちゃは画像素材を使わず、`ToyImage`（`Scene/FreeGame/ToyImage.swift`）がコードで描く。
- ゲームを始めるとき、プレミアムを持っていないときと写真のファイルが見つからないときは、選ばれているおもちゃの代わりに虫を出す。
- `ToyKind`・`ToySize`・`ToyMotion.Style` の rawValue は設定画面の UISegmentedControl のセグメント番号と対応している。case の順番を変えると、画面上の選択肢とずれる。
- ゲームを終えるとき、スコアが 3 を超えていれば `satisfyScore` を 1 増やす。`satisfyScore` が 3 を超えていて `isAppReview` が false なら、`SKStoreReviewController` でレビューを依頼し、`isAppReview` を true にする。そのため、依頼は一度しか出ない。

### 録画

設定で録画をオンにしておくと、Top でゲームを始めるときに `Recording.shared.start()` がフロントカメラで録画を始める。動画は `Documents/neko<yyyyMMddHHmmss>.mov` に保存する。ゲームを終えると `onEnd` で録画を止め、Top 画面にプレビューボタンを出す。このボタンから QuickLook で動画を再生できる。プレビューを閉じると、その動画ファイルは削除される。Info.plist で `UIFileSharingEnabled` と `LSSupportsOpeningDocumentsInPlace` を有効にしているので、Documents の中身は「ファイル」アプリからも見える。

### プレミアム（課金）

ねずみ・ちょうちょ・レーザーポインター・ねこじゃらし・毛糸玉と写真のおもちゃは、買い切りの課金アイテム（商品ID `kayashida.CatTap.premium`、非消耗型）を買うと使える。虫・鳥・魚とほかの設定は無料のまま使える。

- `PremiumStore`（`Common/PremiumStore.swift`）が StoreKit 2 で購入・復元・購入状態の判定をする。購入したかどうかは端末に保存せず、起動時（`AppDelegate`）と購入状況が変わったときに `Transaction.currentEntitlements` から判定し直す。状態が変わると `PremiumStore.didChangeNotification` を送る。
- 購入と復元は購入画面（`Scene/Paywall/PaywallViewController.swift`）でする。購入ボタンは画面の下に固定し、上の窓では `PaywallPreviewScene` がプレミアムのおもちゃを動かして見せる。購入か復元が終わると、購入ボタンに「使えるようになりました」と出してから画面を閉じる。
- 購入画面は、どこから開いたか（`PaywallViewController.Context`）で見出しと窓の主役を変える。鍵の付いたおもちゃから開いたときはそのおもちゃを大きく動かし、写真のおもちゃから開いたときは切り抜いた写真の見本（Assets の `photo_toy_sample`。テスターのこまちの写真を切り抜いたもの）を出す。
- 見た目は控えめにしている。明るい背景で、目立たせるのは金色の王冠と、軽く脈打つピンクの購入ボタンだけ。視差効果を減らす設定のときは、ボタンと紹介の動きを止める。
- プレミアムのおもちゃには、おもちゃごとの効果音がある（`Common/ToySound.swift`）。音の素材は使わず、`Synth` で本物の鳴き声や物音に似せて合成し、`ToySoundPlayer` が `AVAudioEngine` で鳴らす。当たったときの音と、動き出したときにときどき小さく鳴らす音の 2 種類があり、おもちゃの左右の位置に合わせて音を左右に振る。無料の虫・鳥・魚は今までどおり `papa.mp3` を鳴らす。
- 効果音は 1 つにつき鳴り方が 4 つ（`ToySound.variantCount`）あり、鳴らすたびに直前とは違うものを選ぶ。合成は初めて鳴らすときに裏のスレッドでするので、その音の最初の 1 回は合成が終わってから鳴る。音の大きさは `Synth.hitLoudness` と `Synth.moveLoudness` でそろえている。
- 効果音を鳴らし始めるときに、オーディオセッションを `.ambient` にする。消音モードでは鳴らず、ほかのアプリの音楽も止めない。
- 購入ボタンには App Store から読み込んだ `Product.displayPrice` を表示する。価格はコードに書かない。
- 写真のおもちゃは `PhotoToyStore`（`Common/PhotoToyStore.swift`）が作る。iOS 17 以上では Vision で写っている猫や物を切り抜き、それより前の iOS と切り抜けなかったときは丸く切り抜く。画像は `Application Support/PhotoToys/<UUID>.png` に保存し、登録した順番は `App.shared.photoToyIDs` に持つ。登録できるのは 3 つまで。
- Debug ビルドでは起動引数 `-PremiumDebugUnlock` を付けるとプレミアムを解放できる。シミュレータで見た目と動きを確かめるためのもので、Release ビルドには入らない。
- 課金のテストには `CatTap/Premium.storekit` を使う。このファイルはアプリに含めず、共有スキームの Run に設定してある。そのため Xcode から実行したときだけ効き、`xcodebuild` でビルドして `simctl` で起動したときは商品を読み込めない。

### テスター紹介画面

テスターの猫（こまち・ひげよし）を紹介する画面。`Neko.resources`（`Scene/Tester/Type/NekoType.swift`）は、`<rawValue>_<0〜7>.jpg` と `<rawValue>_<0〜7>.MOV` をバンドルから探して返す。写真は `Resource/Photo/`、動画は `Resource/Video/` に置いてある。写真や動画を足すときはこの命名規則に合わせる。

## プロジェクト設定の注意点

- `project.pbxproj` はグループ形式で、フォルダの中身と自動では同期しない。新しいファイルを足すときは、PBXFileReference・PBXGroup・PBXBuildFile と、Sources か Resources のビルドフェーズに手で登録する。
- Info.plist は `GENERATE_INFOPLIST_FILE = YES` で生成する。大半のキー（表示名、カメラの利用目的 `NSCameraUsageDescription`、画面の向きなど）はビルド設定の `INFOPLIST_KEY_*` にあり、Debug と Release の両方に同じ値が書かれている。`CatTap/Info.plist` に書いてあるのはフォントの登録（`UIAppFonts`）・ローカライズ・ファイル共有の設定だけ。
- バージョン（`MARKETING_VERSION`）とビルド番号（`CURRENT_PROJECT_VERSION`）も、Debug と Release の両方を書き換える。
- デプロイメントターゲットは iOS 15.0。
- 署名は手動。Debug は `Apple Development` と `WildCard_dev`、Release は `iPhone Distribution` と `CatTap_appstore` を使う（Team ID は `DU45P949ZD`、Bundle ID は `kayashida.CatTap`）。
- `PrivacyInfo.xcprivacy` で申告している API は UserDefaults（理由 `CA92.1`）だけ。ほかの Required Reason API を使い始めたら、ここにも書き足す。
- シミュレータにはカメラがないので、録画は実機で確かめる。2 本指ダブルタップでゲームを閉じる操作も、実機で確かめる。
- iOS 26.5 のシミュレータでは Vision の切り抜きが働かず、写真のおもちゃは丸い切り抜きになった。切り抜きは実機で確かめる。

## リリース作業用のディレクトリ

- `release/<version>/`: そのバージョンの ExportOptions.plist、App Store のメタデータ（`ja.json`。名前・サブタイトル・キーワード・新機能など）、提出時の確認結果を JSON で置く。
- `work/`: アーカイブ、DerivedData、ビルドログ、検索結果用の動画など、作業中のファイルを置く場所。git では無視している。
- `screenshot/`: App Store 用のスクリーンショット（2022 年に撮ったもの。画面サイズごとにフォルダを分けている）。
