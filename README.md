# Network Monitor for iOS/iPadOS

ネットワーク上のデバイスの死活監視を行う SwiftUI 製の iOS/iPadOS アプリです。  
Python/FastAPI 製の Linux 版 [network-monitor2](https://github.com/Shigeyukii/network-monitor2) の SwiftUI 移植版です。

## スクリーンショット

| ダッシュボード | ネットワークマップ | レポート |
|:-:|:-:|:-:|
| デバイス一覧・ステータス確認 | 星座風トポロジービュー | 稼働率レポート・CSV出力 |

## 主な機能

### 監視
- **Ping 監視** — ICMP echo による死活確認（応答時間 ms 表示）
- **TCP ポート監視** — 任意のポートへの接続確認（複数ポート対応）
- **自動グループ化** — デバイスをグループ単位で管理・フィルタ

### アラート
- **ローカル通知** — UP↔DOWN の状態変化をバナー通知（フォアグラウンド中も表示）
- **Webhook 通知** — Microsoft Teams / Slack へのアラート送信
- **バックグラウンド監視** — BGTaskScheduler による定期チェック（最短 15 分間隔）

### 可視化・レポート
- **応答時間グラフ** — Swift Charts による時系列グラフ（1h / 6h / 24h）
- **稼働率バー** — 直近 24 時間の UP/DOWN 割合を表示
- **稼働率レポート** — 期間別（1h / 24h / 7d / 30d）の統計をリスト表示
- **CSV エクスポート** — ShareSheet 経由でメール・AirDrop・Files に共有

### ネットワークマップ
- **星座風ビジュアライゼーション** — デバイスを星として夜空風に表示
- **ステータスカラー** — UP: 水色グロー / DOWN: 赤 / 未確認: グレー
- **ドラッグ配置** — 星をドラッグして自由に配置、位置は自動保存
- **グループ接続線** — 同一グループのデバイスを破線で接続

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
| ネットワーク | Darwin BSD Sockets (ICMP), Network.framework (TCP) |
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

> **注意**: バックグラウンド監視と通知は実機でのみ完全動作します。  
> シミュレーターでは Xcode の **Debug → Simulate Background Fetch** で動作確認できます。

## アプリの使い方

1. **デバイスを追加** — ダッシュボード右上の **＋** からデバイス名・IPアドレスを入力
2. **監視開始** — アプリ起動と同時に自動で監視が始まります
3. **アラート設定** — 設定タブで Webhook URL を入力し、アラートを有効化
4. **ウィジェット追加** — ホーム画面長押し → ウィジェット追加 → Network Monitor

## データ保持期間

| データ種別 | 保持期間 |
|---|---|
| Ping 履歴 | 7日間 |
| TCP 確認履歴 | 7日間 |

## ライセンス

MIT License

## 作者

Shigeyuki Metoki — [@Shigeyukii](https://github.com/Shigeyukii)

---

> Linux 版（Python/FastAPI）はこちら → [network-monitor2](https://github.com/Shigeyukii/network-monitor2)
