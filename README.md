# Network Monitor for iOS/iPadOS

ネットワーク上のデバイスの死活監視を行う SwiftUI 製の iOS/iPadOS アプリです。  
Python/FastAPI 製の Linux 版 [network-monitor2](https://github.com/Shigeyukii/network-monitor2) の SwiftUI 移植版です。

## スクリーンショット

| ダッシュボード | ネットワークマップ | レポート | トラップ |
|:-:|:-:|:-:|:-:|
| デバイス一覧・ステータス確認 | 星座風トポロジービュー | 稼働率レポート・CSV出力 | SNMP トラップ受信履歴 |

## 主な機能

### 監視
- **Ping 監視** — ICMP echo による死活確認（応答時間 ms 表示）
- **TCP ポート監視** — 任意のポートへの接続確認（複数ポート対応）
- **SNMP トラフィック監視** — v1/v2c による帯域グラフ（in/out, 1h/6h/24h）
- **SNMP トラップ受信** — デバイスからの能動的通知を受信・履歴管理（v1/v2c 対応）
- **自動グループ化** — デバイスをグループ単位で管理・フィルタ
- **メンテナンスモード** — 選択したデバイスを一時的に監視対象から除外

### アラート
- **ローカル通知** — UP↔DOWN の状態変化をバナー通知（フォアグラウンド中も表示）
- **Webhook 通知** — Microsoft Teams / Slack へのアラート送信
- **トラップ通知** — SNMP トラップ受信時にもローカル通知を送信
- **バックグラウンド監視** — BGTaskScheduler による定期チェック（最短 15 分間隔）

### 可視化・レポート
- **応答時間グラフ** — Swift Charts による時系列グラフ（1h / 6h / 24h）
- **稼働率バー** — 直近 24 時間の UP/DOWN 割合を表示
- **稼働率レポート** — 期間別（1h / 24h / 7d / 30d）の統計をリスト表示
- **CSV エクスポート** — ShareSheet 経由でメール・AirDrop・Files に共有

### ネットワークマップ
- **星座風ビジュアライゼーション** — デバイスを星として夜空風に表示
- **ステータスカラー** — UP: 水色グロー / DOWN: 赤 / メンテナンス: オレンジ / 未確認: グレー
- **トラフィック連動サイズ** — SNMP 帯域幅に応じて星の大きさが変化（対数スケール）
- **ドラッグ配置** — 星をドラッグして自由に配置、位置は自動保存
- **グループ接続線** — 同一グループのデバイスを破線で自動接続
- **手動接続線** — 長押し → タップで任意のデバイス間を実線で接続・削除

### デバイス管理
- **設定 JSON エクスポート** — デバイス設定を JSON ファイルとして書き出し
- **設定 JSON インポート** — JSON ファイルからデバイス設定を一括復元
- **メンテナンスモード** — リスト左スワイプまたは詳細画面のトグルで切り替え

### ホーム画面ウィジェット
- **Small** — 全体の UP/総数をコンパクト表示
- **Medium** — 上位 4 デバイスのステータス一覧
- **Large** — 上位 8 デバイスのステータス一覧

### iPad 対応
- **NavigationSplitView** — サイドバー + 詳細の 2 ペインレイアウト
- iPhone では TabView に自動切り替え

## 技術スタック

| カテゴリ | 使用技術 |
|---|---|
| UI | SwiftUI, Swift Charts |
| データ永続化 | SwiftData |
| 非同期処理 | Swift Concurrency (async/await, TaskGroup) |
| ネットワーク | Darwin BSD Sockets (ICMP / SNMP), Network.framework (TCP / UDP) |
| SNMP | ASN.1 BER エンコード/デコード フルスクラッチ実装 |
| バックグラウンド | BackgroundTasks (BGAppRefreshTask) |
| 通知 | UserNotifications |
| ウィジェット | WidgetKit |
| アラート | URLSession (Teams / Slack Webhook) |
| データ共有 | App Groups (UserDefaults) |

## 動作環境

- **iOS / iPadOS 26.2 以降**
- **Xcode 26.3 以降**
- Swift 5.0 / SwiftData

## セットアップ

### 1. リポジトリをクローン

```bash
git clone https://github.com/Shigeyukii/network-monitor.git
cd network-monitor
```

### 2. Xcode でプロジェクトを開く

```
open network-monitor.xcodeproj
```

### 3. 開発チームを設定

各ターゲット（`network-monitor` / `network-monitorWidget`）の  
**Signing & Capabilities → Team** を自分のアカウントに変更してください。

### 4. App Groups を設定（ウィジェット使用時）

両ターゲットの **Signing & Capabilities → App Groups** に  
`group.starmanblog.net.network-monitor` を追加してください。

> ウィジェットなしで使う場合はこの手順は不要です。

### 5. ビルド & 実行

シミュレーターまたは実機でビルドしてください（`⌘R`）。

> **注意**: バックグラウンド監視・通知・SNMP トラップ受信は実機でのみ完全動作します。  
> シミュレーターでは Xcode の **Debug → Simulate Background Fetch** で動作確認できます。

## アプリの使い方

1. **デバイスを追加** — ダッシュボード右上の **＋** からデバイス名・IPアドレスを入力
2. **監視開始** — アプリ起動と同時に自動で監視が始まります
3. **アラート設定** — 設定タブで Webhook URL を入力し、アラートを有効化
4. **SNMP 設定** — デバイス詳細の **…** メニュー → **SNMP 設定** から community 文字列・IF 番号を設定
5. **トラップ受信** — 設定タブで「SNMP トラップ受信」を有効化し、ポート番号（デフォルト: 10162）をネットワーク機器に設定
6. **ウィジェット追加** — ホーム画面長押し → ウィジェット追加 → Network Monitor

## SNMP トラップ受信について

標準のトラップポート 162 は権限が必要なため、**ポート 10162**（変更可能）で受信します。  
ネットワーク機器側のトラップ送信先を `<iPhone/iPadのIP>:10162` に設定してください。

対応するトラップ種別：

| トラップ名 | 内容 |
|---|---|
| `coldStart` / `warmStart` | デバイス再起動 |
| `linkDown` | インターフェースダウン |
| `linkUp` | インターフェースアップ |
| `authenticationFailure` | 認証失敗 |
| `egpNeighborLoss` | BGP ネイバーロスト |
| エンタープライズ固有 | ベンダー独自トラップ |

## データ保持期間

| データ種別 | 保持期間 |
|---|---|
| Ping 履歴 | 7日間 |
| TCP 確認履歴 | 7日間 |
| SNMP トラフィック履歴 | 7日間 |
| トラップ履歴 | 手動削除まで保持 |

## ライセンス

MIT License

## 作者

Shigeyuki Metoki — [@Shigeyukii](https://github.com/Shigeyukii)

---

> Linux 版（Python/FastAPI）はこちら → [network-monitor2](https://github.com/Shigeyukii/network-monitor2)
