# iPad対応

## 対応範囲

- アプリ、Widget、共有拡張のDebug / Releaseを `TARGETED_DEVICE_FAMILY = "1,2"` とし、iPhoneとiPadに同じアプリを配布する。
- iPadは既存の4方向の回転設定を使用する。iPhoneの向き制御は従来どおり。`UIRequiresFullScreen` は設定せず、ウインドウのサイズ変更を妨げない。
- タブはSwiftUIのネイティブ表示を使用する。本棚は既存のadaptive grid、記事本文は既存の最大幅720ptを使用する。
- PDF閲覧は横長ウインドウで左右見開き、縦長では単ページを使用する。前後2ページを画面解像度で先行描画する。詳細は [本棚とPDF閲覧](pdf-library.md) を参照。
- AI画面は最大960pt、新規チャットの入力領域は最大720ptで中央に配置する。画面が狭い場合は利用可能な幅まで縮む。履歴は開閉式ドロワーを維持する。
- テレビはコンテンツ幅900pt以上かつ横長の場合に、映像と幅320ptのチャンネル一覧を並べる。それ以外は縦に並べ、映像の高さを利用可能な高さの55%以内に収める。

## 検証（2026-10-12）

- XcodeBuildMCP、`MyHarness.xcworkspace` / `MyHarness` / Debug、iPad (A16)、iOS 26.4、UDID `388ABFEE-FEE9-4B83-AF02-EEDA6650BBB2` でビルド成功。
- 生成したアプリと両拡張の `UIDeviceFamily = [1, 2]` を確認。
- 署名なしSimulatorビルドではApp Groupが利用できず初回起動が終了した。Simulator用の成果物だけをApp Group付きでadhoc再署名し、再インストール後の実画面を確認。配布用署名やprojectのentitlementsは変更していない。
- 未ログイン状態で、縦向きの「今日」表示、タブ切り替え、横向きの本棚、AI画面と履歴ドロワー、テレビの二列表示を実画面で確認。
- `swift test --jobs 2`: XCTest 39件、Swift Testing 70件が成功。
- `git diff --check` 成功。

## 未検証事項

- 実機iPad、ウインドウ縮小・Split View、ログイン後のチャット送信、実書籍のPDF閲覧、Widget配置と共有拡張の操作。
- テレビの接続先はSimulatorでTLSエラーとなったため、二列のエラー表示を確認した。映像再生と実チャンネル一覧の確認は別途必要。

Appleのサイズ変更対応指針: [TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key)
