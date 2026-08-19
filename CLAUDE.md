# GW230529 BH-NS Einstein Toolkit Simulation

## プロジェクト概要

本プロジェクトでは **Einstein Toolkit** を用いて、ブラックホール–中性子星 (BH-NS)
連星合体イベント **GW230529** を数値相対論シミュレーションで再現する。
公式ギャラリーの BH-NS example をベースとする。

参考資料: <https://einsteintoolkit.org/gallery/bhns/index.html>

**引用義務**: parfile / example データを利用する成果物では
**arXiv:2603.07374** および関連 ET thorn 論文を引用すること (parfile ヘッダの要請)。

### 方針・スコープ

- **目的**: GW150914 プロジェクト ([../gw150914-einstein-toolkit](../gw150914-einstein-toolkit))
  の後継。定性的な波形・合体の再現ができれば成功。
- **実行戦略**: ローカル (16 コア / 80 GB コンテナ) では低解像度で開発・検証し、
  **本番のフル解像度計算は AWS スポットインスタンス**で実行する。
- **予算**: クラウド利用の総額上限 **300 USD**。50 USD 刻みでアラート
  (AWS Budgets) + Cost Anomaly Detection を併用。
- **成果物の持ち帰り**: 図表 (MB オーダー) のみローカル転送。最終成果物は
  tar.gz にまとめて S3 → Deep Archive へライフサイクル移行。中間生成物は
  検証後に削除 (egress 0.09 USD/GB を発生させない)。

## GW230529 の物理パラメータ (公式ギャラリー)

| 項目 | 値 |
| --- | --- |
| BH 質量 | 3.6 M☉ |
| NS 質量 | 1.4 M☉ |
| 質量比 | q = 2.57 (BH/NS)、parfile 表記では 0.388889 (NS/BH) |
| スピン | 両者ゼロ (χeff = 0) |
| EOS | Γ-law polytrope, Γ=2, K=100 |
| 初期分離 | 45 km = 30 M (マージャー前約 1.5 軌道) |
| 初期角運動量 | J0 = 17.04 M☉² |
| 進化時間 | cctk_final_time = 2000 M |

### 公式リファレンス計算 (COSMA8 / DiRAC)

- 並列度: 256 コア (2 ノード)、**np=256 × OMP=1 の pure MPI**
- 実行時間: 約 30 時間 = **約 7,700 core-hours**
- メモリ: 約 140 GB
- 公開出力: `bhns_20252103.tar.gz` (547 MB) — 検証比較のリファレンスに使う
  (GW150914 での Zenodo N=28 比較と同じ手法)

## 技術スタック

- **初期データ**: FUKA/Kadath の**事前計算済み解を import** (KadathImporter /
  KadathThorn)。Kadath ソルバーの実行は不要。`.info` ファイル内の
  `/path/to/` を `gam2.polytrope` の実パスに書き換える必要あり
- **Hydro**: IllinoisGRMHD (+ ID_converter_ILGRMHD, Convert_to_HydroBase,
  EOS_Omni, VolumeIntegrals_GRMHD)
- **時空進化**: ML_CCZ4 (McLachlan)
- **グリッド**: Carpet + CarpetRegrid2、**Llama multipatch 不使用**
  (3 centres × 8 levels、粗グリッド dx=19.2 M、領域 ±672 M、最細 dx=0.15 M)
- **診断**: AHFinderDirect, QuasiLocalMeasures, PunctureTracker,
  WeylScal4 + Multipole (l_max=8, 抽出半径 100–500 M)
- **追加 thorn**: Boost (<https://github.com/dradice/Boost>, LocalThorns/Boost)

## 事前調査で確定している技術知見 (2026-08-19)

1. **Llama 不使用のため GW150914 で苦労した grid 制約
   (sphere_inner_radius / inter-patch 境界) は存在しない**。
   解像度ノブは `coordbase::dx` のみ。制約は `1344/dx` が整数になること。
   - dx=24.0 → 0.80× (推定 ~72 GB)
   - **dx=28.0 → 0.686× (推定 ~45 GB) ← ローカル開発用に採用決定**
   - dx=33.6 → 0.571× (推定 ~26 GB、フォールバック)
   - メモリ推定は公式 140 GB × f³ の外挿。要実測
2. **Fuka/KadathImporter と Fuka/KadathThorn は Kruskal (ET_2025_05) manifest に
   `#DISABLED` として収載済み**。有効化 (ギャラリーの sed コマンド参照) +
   Boost thorn 追記で、GW150914 repo の Docker ビルド基盤が流用できる。
   ギャラリー最終テストは 2025-12-22 なので新しいリリース前提の可能性あり、
   Kruskal で動くかは smoke で判明する
3. **GW150914 repo の cactus.cfg は `-O2` のみ (march 指定なし)** →
   ローカルビルドの Docker image がクラウド CPU (AMD Genoa 等) でそのまま動く。
   ECR 経由の image 配布が成立する
4. **checkpoint 構成は GW150914 と同型** (CarpetIOHDF5, `recover=autoprobe`,
   `../CHECKPOINTS`)。spot 用に `IO::checkpoint_every_walltime_hours = 29`
   を 0.5〜1.0 に変更する
5. **最重要リスク: np≥2 での HDF5 checkpoint lock**。GW150914 ローカル環境では
   HDF5 1.10.4 + np≥2 で POSIX lock 衝突が発生した (np=1 は問題なし)。
   公式 BH-NS は np=256 で走っているため上流環境では成立しているが、
   自前 Docker スタックでの np≥2 checkpoint write/restart 検証が
   クラウド移行の前提条件 (Phase 2 の go/no-go)
6. NS 解像度の目安: フル解像度で ~55 点/NS 半径、0.686× で ~38 点、
   0.571× で ~31 点。低解像度では潮汐破壊 vs plunge の定性が変わりうる点に留意

## Phase 計画

| Phase | 内容 | 予算 | 状態 |
| --- | --- | --- | --- |
| 0 | プロジェクト初期化・資材調査 | $0 | ✅ 完了 (2026-08-19) |
| 1 | Docker image ビルド (Fuka 有効化 thornlist) | $0 | 未着手 |
| 2 | ローカル低解像度 (dx=28) smoke + **np≥2 checkpoint 検証** | $0 | 未着手 |
| 3 | ローカル低解像度 run + 解析パイプライン dry-run (参照データ比較) | $0 | 未着手 |
| 4 | クラウド Stage 1: 小型 spot で ops loop 検証 (S3 sync / 中断 / 復旧) | $5–15 | 未着手 |
| 5 | クラウド Stage 2: c7a.48xlarge spot でフル解像度実測 → go/no-go | $10–30 | 未着手 |
| 6 | クラウド Stage 3: 本番 2000 M + クラウド内解析 + Deep Archive 格納 | $100–250 | 未着手 |
| 7 | 3D 可視化 (オプション) | - | 未着手 |

Phase 5 の go/no-go 基準: 実測 sec/iter からの外挿で総額が 300 USD 以内に収まること。

## クラウド実行戦略 (Phase 4–6)

- **リージョン**: 起動時に spot 価格履歴で選択 (us-east-2 / us-west-2 が有力)。
  S3 / Deep Archive も同一リージョン
- **計算**: c7a.48xlarge (192 core / 384 GB) spot 単一ノード。マルチノード /
  EFA 不要。spot 上限価格はオンデマンド (~$9.85/h) を天井、実効 $2–4/h 想定
- **イメージ配布**: ローカルビルド → ECR push (5–8 GB, ~$0.8/月)
- **データ正本は S3**: EBS gp3 (500 GB) は作業領域。sidecar タイマーで
  15–30 分毎に checkpoint + 出力を `aws s3 sync`。spot 中断 (2 分警告) では
  新規 checkpoint は書かず sync のみ (15 GB 級は 2 分で書けない)
- **再開**: launch template + user-data (ECR pull → S3 復元 → autoprobe 再開)。
  当面は手動再投入スクリプト。中断頻発時に ASG (capacity-rebalance) 化を検討
- **監視**: SSM Session Manager のみ (inbound port なし)。cron で physical_time /
  メモリを S3 heartbeat に push
- **コストガードレール**:
  - AWS Budgets: アラート専用 budget は無料。1 budget あたり閾値 5 個までなので
    **2 本作成して $50/$100/$150/$200/$250/$300 の 6 閾値**をカバー
  - **Cost Anomaly Detection** (無料) を有効化して急激な課金増を検知
  - 注意: 課金データは 8–24 時間遅延するため、リアルタイムの暴走防止は
    **spot 上限価格 + run 完了時の自動 poweroff** が本命。Budgets は事後検知
  - 全リソースに `Project=gw230529` タグ
- **Terraform**: 判断保留中。Phase 4–5 は AWS CLI + launch template JSON +
  user-data シェルで実施し、それを後日の Terraform 化の仕様書とする。
  Phase 6 開始前に再判断

## 外部データ管理

GW150914 repo と同じポリシー: 上流 ET 著作物は git 管理外
(`upstream/` は gitignore)。取得 URL と sha256 は `upstream/SHA256SUMS` に記録
(将来 make fetch ターゲット + sidecar 方式に移行予定)。

| ファイル | URL |
| --- | --- |
| bhns_gw230529.par | <https://einsteintoolkit.org/gallery/bhns/bhns_gw230529.par> |
| bhns.th | <http://einsteintoolkit.org/gallery/bhns/bhns.th> |
| bhns_gw230529_ID.tar.gz | <https://einsteintoolkit.org/gallery/bhns/bhns_gw230529_ID.tar.gz> |
| scripts.tar.gz | <https://einsteintoolkit.org/gallery/bhns/scripts.tar.gz> |
| bhns_20252103.tar.gz (参照データ 547 MB) | <https://bitbucket.org/einsteintoolkit/www/downloads/bhns_20252103.tar.gz> |
| Zenodo 補足データ | <https://zenodo.org/record/18940220> |

## 言語設定

このプロジェクトでは**日本語**での応答を行ってください。コード内のコメント、
ログメッセージ、エラーメッセージ、ドキュメンテーション文字列などは**英語**で
記述してください。

## 開発ルール

### コーディング規約

- Python: PEP 8準拠
- 関数名: snake_case
- クラス名: PascalCase
- 定数: UPPER_SNAKE_CASE
- Docstring: Google Style

## Git運用

- ブランチ戦略: feature/*, fix/*, refactor/*
- コミットメッセージ: 英文を使用、動詞から始める
- PRはmainブランチへ

## 開発ガイドライン

### ドキュメント更新プロセス

機能追加やPhase完了時には、以下のドキュメントを同期更新する：

1. **CLAUDE.md**: プロジェクト全体状況、Phase完了記録、技術仕様
2. **README.md**: ユーザー向け機能概要、実装状況、使用方法
3. **Makefile / makefiles/**: コマンドヘルプテキスト（## コメント）の更新

### コミットメッセージ規約

#### コミット粒度

- **1コミット = 1つの主要な変更**: 複数の独立した機能や修正を1つのコミットにまとめない
- **論理的な単位でコミット**: 関連する変更は1つのコミットにまとめる
- **段階的コミット**: 大きな変更は段階的に分割してコミット

#### プレフィックスと絵文字

- ✨ feat: 新機能
- 🐞 fix: バグ修正
- 📚 docs: ドキュメント
- 🎨 style: コードスタイル修正
- 🛠️ refactor: リファクタリング
- ⚡ perf: パフォーマンス改善
- ✅ test: テスト追加・修正
- 🏗️ chore: ビルド・補助ツール
- 🚀 deploy: デプロイ
- 🔒 security: セキュリティ修正
- 📝 update: 更新・改善
- 🗑️ remove: 削除

**重要**: Claude Codeを使用してコミットする場合は、必ず以下の署名を含める：

```text
🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## 成果物の扱い

- シミュレーション出力（HDF5等）は GB〜TB 規模になりうるため **git管理外**
- クラウド側成果物は S3 → Deep Archive。ローカルへは図表のみ転送
- PDF等の参考資料も `.gitignore` で除外済み（`*.pdf`）
