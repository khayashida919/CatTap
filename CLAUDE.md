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

ゲーム画面の `FreeGameViewController` だけはコードから開く。`instantiateViewController(identifier:creator:)` で生成するときに、ゲーム終了時に呼ぶ `onEnd` クロージャを渡してから push する。`init(coder:)` は `fatalError()` にしてあるので、segue の遷移先にはできない。ゲーム画面では戻るボタンを隠しており、画面を閉じる方法は 2 本指ダブルタップ（Storyboard 上の UITapGestureRecognizer）だけ。ジェスチャーの説明画面（`GestureTutorialViewController`）は、`isNeverShow` が false のときに、ゲーム画面の `viewDidLoad` から segue `toGestureTutorialViewController` でモーダル表示する。

`PreviewViewController` には Storyboard ID が付いているが、Swift のコードからは使われていない。

### 状態の持ち方

状態はシングルトンの `App.shared`（`Common/App.swift`）にまとめている。

- おもちゃの大きさ・種類・数と、透明モードの設定（オン・オフ、間隔の時間、消えている時間）は `@Storage` を付けていないので、メモリにしか持たない。アプリを起動し直すと初期値に戻る。
- `@Storage` を付けたプロパティ（`isNeverShow`、`bestScore`、`satisfyScore`、`isAppReview`、`isRecording`）は、値を JSON にエンコードした `Data` として UserDefaults に保存する。

設定画面が `App.shared` に値を書き込み、`ToyScene.didMove(to:)` がゲーム開始時にその値を読む。

### ゲーム画面

`FreeGameViewController` の `containerView` には Storyboard で `customClass="SKView"` を指定してある。この SKView で `ToyScene.sks` から読み込んだシーンを表示する。`ToyScene` は `.sks` 内のノードを名前（`toy`、`pointEffect`、`pointLabel`、`bestLabel`）で取り出すので、`.sks` 側でノード名を変えるとコードも直す必要がある。

- おもちゃは `toy` ノードを `copy()` して設定された数まで増やす。`DispatchQueue.main.asyncAfter` を再帰で呼び、`name == "toy"` のノードすべてに力を加える処理と止める処理を、それぞれ繰り返す。
- テクスチャ名は `String(describing: App.shared.kind)` で決めている。そのため `ToyKind` の case 名と Assets のイメージセット名（`bug`、`bird`、`fish`）をそろえておく必要がある。
- `ToyKind` と `ToySize` の rawValue は設定画面の UISegmentedControl のセグメント番号と対応している。case の順番を変えると、画面上の選択肢とずれる。
- ゲームを終えるとき、スコアが 3 を超えていれば `satisfyScore` を 1 増やす。`satisfyScore` が 3 を超えていて `isAppReview` が false なら、`SKStoreReviewController` でレビューを依頼し、`isAppReview` を true にする。そのため、依頼は一度しか出ない。

### 録画

設定で録画をオンにしておくと、Top でゲームを始めるときに `Recording.shared.start()` がフロントカメラで録画を始める。動画は `Documents/neko<yyyyMMddHHmmss>.mov` に保存する。ゲームを終えると `onEnd` で録画を止め、Top 画面にプレビューボタンを出す。このボタンから QuickLook で動画を再生できる。プレビューを閉じると、その動画ファイルは削除される。Info.plist で `UIFileSharingEnabled` と `LSSupportsOpeningDocumentsInPlace` を有効にしているので、Documents の中身は「ファイル」アプリからも見える。

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

## リリース作業用のディレクトリ

- `release/<version>/`: そのバージョンの ExportOptions.plist、App Store のメタデータ（`ja.json`。名前・サブタイトル・キーワード・新機能など）、提出時の確認結果を JSON で置く。
- `work/`: アーカイブ、DerivedData、ビルドログ、検索結果用の動画など、作業中のファイルを置く場所。git では無視している。
- `screenshot/`: App Store 用のスクリーンショット（2022 年に撮ったもの。画面サイズごとにフォルダを分けている）。
