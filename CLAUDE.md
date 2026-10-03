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

### 公式リファレンス計算 — **公開データからの実測値 (2026-08-20 訂正)**

`bhns_20252103.tar.gz` に同梱の `bhns_gw230529.out` (Carpet ログ + SLURM
エピローグ) と `mp_psi4_l2_m2_r500.00.asc` を直接読んで確定した値。
**事前調査時の記述 (256 コア / 30 時間 / 7,700 core-hours) は誤りだった**。

| 項目 | 実測値 | 備考 |
| --- | --- | --- |
| 並列度 | **480 rank** (12 ノード × 40 コア) | `Carpet is running on 480 processes` |
| 実行時間 | **46.4 時間で t=3041 M** | SLURM Elapsed 1-22:26:06 |
| 平均速度 | **3.30 sec/iter** (dt=0.06 M) | = 5.5 分/M |
| t=2000 M 到達 | 約 30.5 時間 = **約 14,600 core-hours** | 想定の約 2 倍 |
| メモリ | **438.5 GB** (12 ノード合計、SLURM 申告) | 従来「約 140 GB」としていた値の出所は不明 |
| 実際の終了時刻 | **t = 3041 M** | parfile の 2000 M を超えて延長実行されている |

- 公開出力: `bhns_20252103.tar.gz` (547 MB) — 検証比較のリファレンスに使う
  (GW150914 での Zenodo N=28 比較と同じ手法)

#### 合体時刻 (参照波形から実測)

`mp_psi4_l2_m2_r500.00.asc` の |ψ4| ピークが **t = 1213 M**。tortoise 座標
r* = r + 2M ln(r/2M − 1) (M ≈ 5) で遅延時間 r* = 538.9 M を引くと、
**ソースでの合体は t ≈ 674 M**。

- **【訂正 2026-10-03】従来の「t ≈ 713 M」は `t − r` で遅延時間を引いた値**で、
  tortoise 補正 (r=500 で 38.9 M) が抜けていた。Phase 3 run の共通ホライズン
  初検出 679.0 M、ρ_max の 50% 落下時刻 669.6 M (参照ログ) とも整合するのは
  674 M のほう
- **2000 M のうち後半約 1325 M はポストマージャー** (ringdown + 円盤進化)
- 波形が r=500 M に到達するのは t ≳ 500 M。**t=500 M で計算を止めると
  参照波形との重なりが 0 になる**。短縮 run の終点を決める際の制約
- 参照側の出力頻度: ψ4 は 256 iter = 15.4 M ごと、`rho.xy.h5` は
  1024 iter = 61.4 M ごと、NS 表面 VTK は 256 iter ごと

#### メモリのクラウド側への含意

SLURM 申告の 438.5 GB は 480 rank 時の全ノード合計で、rank 数が減れば
ghost zone の重複が減るため単純比例はしない。とはいえ **c7a.48xlarge の
384 GB に対して余裕があるとは言えない**。Phase 5 の実測は「形式的確認」ではなく
**go/no-go を左右する関門**として扱うこと。np=192 でメモリが載らない場合、
マルチノード化は「学習目的の選択肢」から「必要条件」に格上げされる。

**【決着 2026-08-21 実測】この懸念は杞憂だった**。np=192 のフルレゾ probe で
Carpet 申告 125.3 GByte / ノード RSS 137 GiB。480 rank の 438.5 GB は
ghost zone の重複が支配的だったということ。**c7a.48xlarge の 384 GiB で
十分な余裕があり、マルチノード化は「必要条件」にならない**。

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
   解像度ノブは `coordbase::dx` のみ。制約は 2 つ:
   - **(a) `1344/dx` が整数**になること (粗グリッドが ±672 M のため)
   - **(b) 粗グリッドのセル数が MPI rank 数の 3D 分割に耐えること** (Phase 1 実測)。
     Carpet は `1344/dx` セルを 3 次元に分割し、各 chunk が
     `Carpet::ghost_size = 3` より広い必要がある。足りないと初期化時に
     `The grid structure is inconsistent.` (ml=0 rl=0) で abort する。
     **実測: dx=67.2 (20 セル) は np=4 で通り np=16 で失敗**。
     dx と rank 数は独立に決められない
   - **(c) dx を粗くすると refinement box が「痩せる」** (Phase 1 実測)。
     `Carpetregrid2::radius_*[N]` は M 単位で固定 (300, 150, 75, 37.5, 20, 15, 10)
     なので、dx を上げてもボックスの物理サイズは変わらず**セル数だけ減る**。
     `ghost_size = 3` と prolongation buffer を引くと有効領域が消え、
     初期データが健全でも evolution 1 歩目で NaN になる
     (`GRHayL: u^0 evaluated to NaN`)。**dx=67.2 で実際に発生**

   | dx | 粗グリッド | level 1 の dx | level 1 のセル数 (直径 600 M) | 推定メモリ |
   | --- | --- | --- | --- | --- |
   | 19.2 (上流) | 70 | 9.6 | 62 | 140 GB (公式実測) |
   | 24.0 | 56 | 12.0 | 50 | ~72 GB |
   | **28.0** | **48** | **14.0** | **43** | **37.1 GB (実測)** ← 採用 |
   | 33.6 | 40 | 16.8 | 36 | ~26 GB |
   | 67.2 | 20 | 33.6 | 17 | 11.6 GB — **NaN で失敗。使用不可** |

   - dx は上表の検討済みの範囲から選ぶこと。安易に粗くすると (b)(c) の両方に抵触する
   - dx=28.0 のメモリは **37.066 GByte** (Carpet 申告) / RSS 35.8 GiB を実測。
     公式 140 GB × f³ の外挿 (~45 GB) より良好だった
   - 低解像度 parfile の生成は
     `scripts/make_smoke_par.sh <dx> [itlast] [levels] [checkpoint_id]`
     (上流 parfile は再配布しないため、生成スクリプト側を版管理する)
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
5. **【解決済み】np≥2 問題の真因は MPI 二重リンクだった** (Phase 1 で判明)。
   GW150914 から引き継いだ Dockerfile は `update-alternatives --set mpi → mpich`
   を **Cactus ビルドより後**に置いていたため、ビルド時には `/usr/bin/mpic++` が
   Open MPI を指し、Cactus と ADIOS2 が Open MPI を、HDF5 が MPICH を掴んで
   **1 バイナリに 2 つの MPI スタックが同時にリンク**されていた。
   MPICH の hydra から起動すると Open MPI 側の `MPI_Init` が singleton 初期化に
   フォールバックし、各プロセスが**独立した 1-rank ジョブ**として走る
   (ログに `Carpet is running on 1 processes` が rank 数だけ出る)。
   - GW150914 で記録された「np≥2 の HDF5 POSIX lock 衝突」は、独立した N 個の
     ジョブが同一 checkpoint ファイルを開いていただけ。HDF5 1.10.4 のバグではない
   - 同じく「np≥2 の OOM」は各 rank がフルグリッドを確保していたため。
     np=1 の peak 43 GiB × 2 = 86 GiB > 上限 80 GiB と数値が一致する。
     当時の説明 (Multipole/WeylScal4 バッファの複製) は誤診
   - GW150914 の本番 run は全て np=1 なので**計算結果自体は正しい**
   - **対策**: alternatives の MPICH 固定を全ビルドより前に移動、ADIOS2/openPMD の
     CMake に MPI コンパイラを明示、さらに `ldd` によるビルド時アサーションを追加
     (Open MPI が混入したらビルドを失敗させる)
   - **検証方法**: `MPI_Init` の成否では不十分。`make docker-check` が
     `par/mpi_check.par` を np=2 で走らせ、Carpet が報告する process 数を検証する
   - Phase 2 の go/no-go は依然 np≥2 の checkpoint write/restart 実証だが、
     公式と同じ pure MPI 構成が使える見込みになった
6. NS 解像度の目安: フル解像度で ~55 点/NS 半径、0.686× で ~38 点、
   0.571× で ~31 点。低解像度では潮汐破壊 vs plunge の定性が変わりうる点に留意
7. **【重要 2026-08-20 実測】`OMP_NUM_THREADS` を明示しないと 65 倍遅くなる**。
   Cactus は OpenMP 有効でビルドされているため、未設定だと**各 rank が
   「見えているコア数」だけスレッドを起動する**。np=16 を 16 コアで走らせると
   **16 rank × 16 threads = 256 スレッドが 16 コアを奪い合う**。
   - **失敗せず、遅くなるだけ**なのが最悪の性質。NaN も異常終了も出ない
   - 実測: 0.113 M/hour (2790 sec/iter) 対 正常時 6.9–7.2 M/hour (43–46 sec/iter)。
     checkpoint recover も 56 秒が **5 時間以上**に伸びた
   - 検知方法は起動ログの `INFO (Carpet): There are N threads per process`。
     **pure MPI なら必ず 1**。`There are 16 threads in total` (= rank 数) も確認
   - 対策として **Dockerfile に `ENV OMP_NUM_THREADS=1` を焼き込んだ**
     (2026-08-20)。ただし**この修正を含むイメージは未ビルド**なので、
     再ビルドまでは起動コマンド側で明示すること
   - **クラウドではさらに深刻**。192 rank × 192 threads = 36,864 スレッドになる。
     Phase 5 は sec/iter を測る場なので、これに気づかないと
     **go/no-go を誤った数字で判断する**
   - 併せて `cactus_sim` は PATH に無い (実体 `/home/etuser/Cactus/exe/cactus_sim`)。
     こちらも Dockerfile の `ENV PATH` で対処済み (未ビルド)

## Phase 計画

| Phase | 内容 | 予算 | 状態 |
| --- | --- | --- | --- |
| 0 | プロジェクト初期化・資材調査 | $0 | ✅ 完了 (2026-08-19) |
| 1 | Docker image ビルド (Fuka 有効化 thornlist) | $0 | ✅ 完了 (2026-08-19、MPI 二重リンク修正込み) |
| 2 | ローカル低解像度 (dx=28) smoke + **np≥2 checkpoint 検証** | $0 | ✅ 完了 (2026-08-20、np=16 で write / recover 双方を実証) |
| 3 | ローカル低解像度 run **896 M まで** + 解析パイプライン dry-run (参照データ比較) | $0 | ✅ 完了 (2026-08-25 完走、2026-08-26 解析。下記「Phase 3 の結果」) |
| 4 | クラウド Stage 1: 小型 spot で ops loop 検証 (S3 sync / 中断 / 復旧) | $5–15 | ✅ 完了 (2026-08-20、インフラ側。**実 spot 中断も捕捉**) |
| 5 | クラウド Stage 2: c7a.48xlarge spot でフル解像度実測 → go/no-go | $10–30 | 🚧 ほぼ完了 (2026-08-21 実測 $7.1。**4.16 sec/iter → 2000 M で 38.5 h / 115 USD、go 圏内**。残は recover のクラウド検証 = インフラ issue #3) |
| 6 | クラウド Stage 3: 本番 (シングルノード) + クラウド内解析 + Deep Archive 格納 | $100–250 | 未着手 |
| 7 | 3D 可視化 (オプション) | - | 未着手 |
| 8 | **マルチノード MPI 実験** (本番とは切り離した学習目的) | $10–20 | 未着手 (Phase 6 の後) |

Phase 5 の go/no-go 基準: 実測 sec/iter からの外挿で総額が 300 USD 以内に収まること。
**→ 2026-08-21 のフルレゾ probe (dx=19.2 / np=192 / c7a.48xlarge、90 分) で実測済み**:
4.16 sec/iter (壁時計平均、checkpoint 税 +10.9% 込み)、メモリは Carpet 125.3 GByte /
ノード RSS 137 GiB。**c7a.48xlarge の 384 GiB に対し余裕があり、t=2000 M でも
38.5 h / 115 USD と予算内に収まる**。詳細はインフラ repo の
`2026-08-21-full-resolution-throughput.md`。ただし測定は t=0–63 M の純 inspiral で、
merger 期のコスト増は未測定 (38.5 h は下限に近い値として扱う。もっとも Phase 3 の
ローレゾ実測では merger 期の減速は観測されなかった — 下記)。

### Phase 3 の方針: 2000 M 完走ではなく 896 M で打ち切る (2026-08-20 決定)

**ローカルでローレゾ 2000 M (11.4 日) を完走させる価値は薄い**と判断した。

- フル解像度が完走することは**参照 tarball 自体が既に証明している**。
  ローカルのローレゾ完走はクラウドのフルレゾ成功の予測にならない
  (知見 6 の通り、merger 物理は解像度依存)
- ローカル run の役割は (a) smoke の 22 M を超えた長時間安定性、
  (b) 解析パイプラインの dry-run、(c) 参照との定性比較。2000 M は要らない
- **終点 896 M (itlast=10240) を選んだ理由**: 合体が ~675 M なので
  inspiral–merger–ringdown が完結する。500 M で切ると (1) 参照 ψ4 との
  重なりが 0、(2) merger 期のコードパス (AH が残骸ホライズンを掴む、
  潮汐破壊時の regrid、物質が refinement 境界を横切る) を**時給ゼロの
  ローカルで一度も踏まないまま** $2–4/h のクラウドに持ち込むことになる
- 所要時間は 43 sec/iter × 9976 iter ≈ **5.0 日**。ただし merger 期は
  regrid と AHFinder の負荷が上がるため 5–7 日を見込む

**実行コマンド** (it_264 の checkpoint から autoprobe recover して継続):

```bash
bash scripts/make_smoke_par.sh 28.0 10240 8 no 6 512
docker exec -d gw230529-et bash -lc \
  'cd /home/etuser/simulations/dx28/run && export OMP_NUM_THREADS=1 && \
   { /usr/bin/time -v mpirun.mpich -genv OMP_NUM_THREADS 1 -np 16 \
     /home/etuser/Cactus/exe/cactus_sim \
     /home/etuser/work/upstream/par-smoke/bhns_smoke_dx28p0_l8_it10240.par; \
     echo "PHASE3 EXIT: $?"; } > run_it10240.log 2>&1'
```

**`OMP_NUM_THREADS=1` は必須** (知見 7)。最初の起動でこれを落として
5 時間 55 分を無駄にした。起動したら必ず
`grep "threads per process" run_it10240.log` が **1** を返すことを確認する。
`-genv` は MPICH の hydra が全 rank に環境変数を配る指定。

### Phase 3 の結果 (2026-08-25 完走 / 2026-08-26 解析)

**run 実績**: it_264 の checkpoint から recover して 2026-08-20 起動、
2026-08-25 01:06 UTC に it=10240 / t=896 M へ正常終了 (exit 0)。
9976 iteration を wall clock 115h17m で消化 = **41.6 sec/iter**
(起動 + recover + 6 時間ごと checkpoint 込み)。見積り 43 sec/iter を下回り、
**merger 期 (regrid + AHFinder 負荷増) でも減速は観測されなかった**。
これは Phase 5 実測 (t=0–63 M の純 inspiral) を 2000 M へ外挿する際の
不安材料を 1 つ消す材料になる。

**解析パイプライン**: `scripts/analyze_phase3.py` (コンテナ内で実行、
kuibit で 2D AMR を読む)。`make analyze-phase3` 1 発で図 4 枚 +
`reports/phase3/summary.md` を生成する。Phase 6 のクラウド内解析の
リハーサルを兼ねる。

**参照データ (bhns_20252103, dx=19.2) との比較**:

| 項目 | run (dx=28) | 参照 (dx=19.2) |
| --- | --- | --- |
| 合体時刻 (ソースフレーム、\|ψ4\| ピーク、tortoise 補正) | **675.4 M** (r=100 抽出から) | 674.4 M (r=500 から) |
| ずれ | **+1.0 M = +0.15%** (M=4.9–5.0 で +0.7〜+1.0 M) | — |
| 共通ホライズン (ah2) 初検出 | 679.0 M | — (tarball に AH データなし) |
| ρ_max が初期値の 50% に落ちる時刻 | 669.9 M | 669.6 M |
| ρ_max が初期値の 10% に落ちる時刻 | 840.7 M | 838.3 M |
| inspiral 中の ρ_max の変動 (t<550 M) | −13.0%〜+1.0% | −12.6%〜+1.2% |
| 残骸 BH の m_irr (t=896 M) | 4.384 M☉ | — |
| NS バリオン質量保存 (inspiral, t<600 M) | drift 2.05% | — |
| 合体後に NS 追跡球へ残る質量 | 4.0% (円盤/テール) | — |

- **ψ4 の inspiral 波形 (r=500、retarded time) は参照とほぼ重なる**。
  注意: r=500 抽出には合体波が届かない (到達は t=1213 M > 896 M)。
  合体を含むのは r=100 抽出のみ
- **2D 密度 (xy 面) の潮汐破壊の形態が 4 時刻すべてで参照と定性一致**
  (NS → 潮汐伸長 → 三日月状破壊 → 残骸テール/円盤)。知見 6 の懸念
  「ローレゾで潮汐破壊 vs plunge の定性が変わる」は **dx=28 では顕在化しない**
- **【訂正 2026-10-03】合体時刻の「−15.8 M = −2.2% のずれ」は解析側の見かけ**
  だった。`analyze_phase3.py` の `load_psi4` が遅延時間を `u = t − r` で
  計算しており、抽出半径の違う run (r=100) と参照 (r=500) の比較に
  tortoise 補正の差 16.9 M (22.0 M 対 38.9 M) がそのまま乗っていた。
  補正すると**ずれは +1 M**。上表の数値は手計算で補正した値で、
  スクリプトと `reports/phase3/summary.md` は未修正のまま
  - ただし ψ4 の出力間隔は run 22.4 M / 参照 15.4 M で、ピーク時刻は
    放物線補間による推定。**+1 M という値そのものは出力間隔より細かく、
    言えるのは「サンプリング精度の範囲で一致」まで**。時刻一致の精度を
    主張するなら ρ_max の 50% 落下時刻 (IOBasic は 4 iter ごと出力、
    差 0.3 M ≈ 1.5 μs) を使う
- **物質の進化は座標時刻で参照と定量的に一致する** (2026-10-03 追加)。
  参照ログ `bhns_gw230529.out` の IOBasic 表 (`IllinoisGRMHD::rho_b` の max、
  4 iter ごと) と run の `hydrobase-rho.maximum.asc` を比較すると、
  ρ_max/ρ_max(0) の比は t=500–890 M でおおむね 2% 以内、最大でも t≈850 M の 8%。
  潮汐破壊の進行は**座標時刻で 2〜3 M 以内**に揃う。これが合体時刻のずれが
  見かけだと判断した独立の根拠
  - 比較の限界: ρ_max は一点の量。円盤質量・降着率は参照に VolumeIntegrals
    出力が無いため比較不能。W_lorentz の max は低密度大気のノイズを拾うため
    流出の指標にならない (ピーク時刻が run 834 M / 参照 529 M とばらばら)
  - 2D スナップショットは出力間隔 (run 44.8 M / 参照 61.4 M) の都合で
    比較時刻が最大 18 M ずれている (t=448 vs 430)。見た目の差はその影響を含む
- **本番 1500 M 打ち切り案への含意**: run では merger + ~200 M で ah2 質量が
  平坦化し、残骸円盤の形成まで見えた。1500 M (= merger + ~825 M) なら
  IMR + 初期円盤進化まで余裕で収まる

parfile の上流からの差分は 3 行のみ (`cctk_itlast`, `out2D_every`,
`checkpoint_every_walltime_hours`)。後ろ 2 つは Phase 3 のために
`make_smoke_par.sh` に第 5・第 6 引数として追加した:

- **checkpoint 6 時間ごと** (上流は 29 時間 = COSMA8 の 30 時間ジョブ制限向け)。
  5 日の無人 run でホストが落ちると 29 時間分を失う。checkpoint 1 回は
  約 60 秒なので 6 時間間隔でも wall clock の 0.3%
- **2D 出力 512 iter ごと** (= 44.8 M、上流は 1024 = 89.6 M)。
  参照の `rho.xy.h5` が 61.4 M ごとなので、比較点を増やすため。
  容量増は約 2 GB で無視できる
- ψ4 と 0D/1D ASCII は上流のまま 256 iter = **22.4 M ごと**。
  「50 M ごとに参照と比較」という検証要求はこれで満たせる

### Phase 2 実測値 (2026-08-19、dx=28 / np=16 × OMP=1 / 16 コア)

| 項目 | 実測値 | 備考 |
| --- | --- | --- |
| 必要メモリ | 37.066 GByte (Carpet 申告) / RSS 39.1 GiB | 推定 45 GB より良好 |
| FUKA ID import | 1493 秒 = 24.9 分 (8 レベル合計) | rank 数でのみ短縮可。OpenMP 非対応 |
| **evolution 速度** | **43 sec/iter** | 256 iter 全体の平均。dt = 0.0875 M/iter |
| checkpoint | **25 GB / 16 ファイル** (rank ごと 1 ファイル) | POSIX lock エラーなし |
| AH 質量 | m_irreducible = 3.599979 | BH 3.6 M☉ と 6 桁一致 |

**ローカルで 2000 M を完走する場合の外挿**: 43 sec/iter ÷ 0.0875 M/iter
= 493 秒/M → 2000 M で **約 11.4 日**。GW150914 の stage 分割運用と同程度。

**注意**: 当初 30 sec/iter と記録したが、これは iter 32→36 の早期サンプルで
**平均を 44% 過小評価していた**。run 全体 (3h44m09s) からフェーズを切り出すと、
起動+ID import+it_0 checkpoint が 2065 秒、残る 11383 秒が 256 iteration。
終了時 checkpoint を 250〜450 秒のどこに置いても 42.7〜43.5 sec/iter に収まる。
**短い区間のサンプリングで sec/iter を決めないこと。**

**クラウド側への含意 (Phase 4–6 の計画に反映が必要)**:

- **checkpoint サイズの想定が過小**。クラウド戦略の記述は「15 GB 級」を
  前提にしているが、dx=28 で既に 25 GB。フル解像度 dx=19.2 では
  25 × (28/19.2)³ ≈ **78 GB** になる。`checkpoint_keep = 2` なら
  ディスク上 156 GB (EBS gp3 500 GB には収まる)
- 【対応済み 2026-08-20】78 GB の読み出しは gp3 125 MB/s なら 10.4 分だが、
  **gp3 の throughput を 1000 MB/s (IOPS 4000) に上げて 1.3 分**にした。
  追加費用は 30h run で約 1.4 USD。Terraform 側の既定値に反映済み
- 【対応済み 2026-08-20】**S3 側の checkpoint 蓄積が真のコスト要因だった**。
  push-only mirror だと 60 世代 × 78 GB = 4.7 TB、lifecycle 到達まで約 25 USD
  (予算の 8%)。**slot-a / slot-b の 2 面交互書き + `CURRENT` マーカー**方式に
  変更し、S3 常駐を 156 GB に固定。転送料自体は同一リージョンなので 0
- 【重要】`CURRENT` マーカーは**千切れた checkpoint の復元事故を防ぐため**。
  78 GB のアップロード中に spot 中断されると S3 に不完全なセットが残り、
  `recover = autoprobe` は「最新だから」それを選んでしまう。
  マーカーはアップロード成功後にのみ書くので、常に完全なセットを指す
- 【決定 2026-08-20】**checkpoint は 1 時間ごと、sync は 5 分ごと**。
  78 GB の書き込みは全 rank を 78 秒止めるので、30 分間隔だと wall clock の
  4.3%、1 時間間隔なら 2.2%。30h run で確定 38 分の節約に対し、中断 1 回
  あたりの追加ロスは約 15 分。score 9 のプールで中断 1 回以下が見込みなら
  1 時間が有利。sync は変更が無ければ LIST のみで終わるため短くて構わない
- spot 中断の 2 分警告で新規 checkpoint を書かない方針は正しい (78 GB は論外)
- ID import 24.9 分 (ローカル) はフル解像度・np=192 でも数十分規模で残る。
  **spot 中断のたびに払わないよう、`IO::checkpoint_ID = "yes"` で
  初期データを checkpoint 化してから本計算に入ること**
- **【実証済み 2026-08-20】checkpoint からの recover が機能する**。
  `recover = "autoprobe"` で it_256 を拾い、Kadath import を **0 回**に抑えて
  iteration 256 (t=22.400 M) から正確に再開。recover 読み込み + 終了時
  checkpoint 書き込みで 94 秒、cold start の 2065 秒に対し **33 分の節約**。
  spot 中断からの復帰は成立する
- **`checkpoint_keep = 2` は run をまたいで効かない**。2 回の run 後に
  it_0 / it_256 / it_264 の 3 世代 77 GB が残った。フル解像度では
  1 世代 78 GB なので、**再開のたびに世代が増えてディスクと S3 を圧迫する**。
  sidecar 側で明示的に世代を刈る運用が要る

## クラウド実行戦略 (Phase 4–6)

- **リージョン**: **us-west-2 に確定 (2026-08-19 実測)**。AZ は
  **us-west-2d (`usw2-az4`)** 優先、次点 us-west-2a → us-west-2c。
  「起動時に選択」は不可 (ECR/S3 がリージョン束縛のため実質固定)。
  S3 / Deep Archive も同一リージョン。実測値と選定根拠は sibling repo の
  `docs/architecture.md`「Region and instance selection」
- **インスタンス**: **c7a.48xlarge (192 core / 384 GiB) に確定**
  (2026-08-21 変更、インフラ側 commit `12c5c5c`)。一時 m7a.48xlarge (768 GiB) を
  既定にしていた (参照 run の 438.5 GB 実測から OOM を警戒) が、
  Phase 5 の np=192 実測でノード RSS 137 GiB と判明し、
  「working set が 384 GiB を十分下回ったら c7a に降格」の条件が成立した。
  spot 実効 c7a 2.978 / m7a 3.747 USD/h。
  **c7i.48xlarge は代替にならない** — 192 vCPU が物理 96 コア + HT で
  メモリ 8ch (c7a/m7a は物理 192 コア・12ch)。実質半分の機械になる
- **計算**: spot **単一ノードで確定 (2026-08-20 決定)**。
  spot 上限価格はオンデマンドを天井、実効は c7a 2.978 / m7a 3.747 USD/h。
  マルチノードは本番から切り離す (下記)
- **イメージ配布**: ローカルビルド → ECR push。
  **ローカルの非圧縮サイズは 17 GB** (従来「5–8 GB」と記載していたのは誤り)。
  ECR は圧縮後で課金するので 6–8 GB に収まりうるが、**初回 push 時に実測して
  両 repo の数字を直す** (ECR 月額と再 push コストの見積りがこの値に乗る)
- **クラウド用 parfile の必須要件** (インフラ側は parfile を書き換えない。
  書き換えるのは `.info` の `eosfile` のみ):

  ```text
  IO::checkpoint_ID                   = "yes"   # ID import 24.9 分を中断のたびに払わない
  IO::checkpoint_every_walltime_hours = 1.0     # 6 は spot には長すぎる
  IO::checkpoint_keep                 = 2
  IO::recover                         = "autoprobe"
  ```

  `scripts/make_smoke_par.sh 19.2 <itlast> 8 yes 1.0 <out2d>` で全部満たせる
  (keep と recover は上流のまま)。ローカル Phase 3 が 6 時間なのは
  無人 run のホスト障害対策で、**spot では中断の期待損失が
  `checkpoint間隔/2 + sync間隔/2` なので 1.0 でなければならない**
- **データ正本は S3**: EBS gp3 (500 GB / 1000 MB/s / 4000 IOPS) は作業領域。
  sidecar タイマーで **5 分毎**に sync、**checkpoint は 1 時間毎**。
  checkpoint は `slot-a` / `slot-b` の 2 面交互 + `CURRENT` マーカー方式
  (詳細は Phase 2 実測値の項)。spot 中断 (2 分警告) では新規 checkpoint は
  書かず sync のみ (78 GB は 2 分で書けない)
- **再開**: launch template + user-data
  (ECR pull → `CURRENT` が指すスロットから復元 → autoprobe 再開)。
  再投入は `make run` (= `terraform apply -var run_enabled=true`) 1 発。
  中断頻発時に ASG (capacity-rebalance) 化を検討
- **監視**: SSM Session Manager のみ (inbound port なし)。cron で physical_time /
  メモリを S3 heartbeat に push
- **コストガードレール**:
  - AWS Budgets: アラート専用 budget は無料。1 budget あたり閾値 5 個までなので
    **2 本作成して $50/$100/$150/$200/$250/$300 の 6 閾値**をカバー
  - **Cost Anomaly Detection** (無料) を有効化して急激な課金増を検知
  - **【要注意 2026-08-20】core-hours の想定が 2 倍に増えた**。参照実測
    14,600 core-hours (t=2000 M) ÷ 192 コア、per-core 性能を参照比 1.0–2.0 倍
    と仮定した見積り (インフラ側算出):

    | | 38 h | 51 h | 76 h |
    | --- | --- | --- | --- |
    | c7a @ 2.978 USD/h | 113 USD | 152 USD | 226 USD |
    | m7a @ 3.747 USD/h | 142 USD | 190 USD | **285 USD** |

    **悲観端は 300 USD 枠を使い切る**。逃げ道は**合体が t≈675 M なので
    2000 M ではなく ~1500 M で打ち切る** (約 25% 節約)。ringdown は余裕で
    収まる。Phase 3 が 896 M で IMR を通すので、その結果が判断材料になる
  - **【実測で更新 2026-08-21/26】上表は実測で楽観端に確定した**。
    フルレゾ probe の実測 4.16 sec/iter → **t=2000 M で 38.5 h / 115 USD**
    (c7a)。1500 M 打ち切りなら **約 29 h / 86 USD**。probe は inspiral のみの
    測定だが、Phase 3 のローレゾ完走では merger 期の減速が観測されなかったため、
    大幅な上振れは考えにくい。本番 run 中も `make throughput` で監視する
  - **sec/iter は最低 1 時間回してから外挿すること**。Phase 2 で iter 32→36 の
    早期サンプルが平均を 44% 過小評価した前例がある。加えて知見 7 の
    `OMP_NUM_THREADS` 未設定は**遅くなるだけで失敗しない**ため、
    測定前に `threads per process` が 1 であることを必ず確認する
  - 注意: 課金データは 8–24 時間遅延するため、リアルタイムの暴走防止は
    **spot 上限価格 + run 完了時の自動 poweroff** が本命。Budgets は事後検知
  - 全リソースに `Project=gw230529` タグ
- **Terraform**: **採用決定 (2026-08-19)**。sibling repo
  [../gw230529-einstein-toolkit-aws-tf](../gw230529-einstein-toolkit-aws-tf)
  で管理する。当初は「Phase 4–5 は CLI + launch template JSON で実施し
  Phase 6 前に再判断」だったが、前倒しして Terraform 化した。
  スタックは**環境別ではなく寿命別**に 3 分割 (bootstrap / foundation /
  compute)。compute の destroy が S3 データと ECR イメージに届かないのが要点。
  設計根拠は同 repo の `docs/architecture.md`
- **spot vCPU クォータ**: 【確認済み・対応不要】`L-34B43A08` は
  us-east-1 / us-west-2 とも既に **256 vCPU**。192 vCPU の単一インスタンスは
  そのまま起動できる。us-east-2 のみ 5 vCPU なので、同リージョンを使うなら
  緩和申請が必要 (承認まで数時間〜数日)

## マルチノード MPI の位置づけ (Phase 8 / 2026-08-20 決定)

**本プロジェクトの本番 (Phase 6) はシングルノードで確定**。マルチノードは
学習目的の独立した後続実験 (Phase 8) として、本番の完了後に切り出す。
**学習実験と本番を同じ run に混ぜない**のが要点。

### 本番をマルチノード化しない理由

- メモリもコア数も単一ノードで足りる見込み (ただし Phase 5 で要実測)
- スケーリング効率は必ず 100% を切るので **$/科学 は確実に悪化**する
- spot 中断の期待回数が 2 倍。1 台落ちれば MPI ジョブ全体が死に、
  再開には**2 台同時の spot 容量**が要る
- まともな性能には EFA が必要で、それは libfabric 対応の MPI 再ビルド
  = Phase 1 で踏んだのと同じ class のビルド外科手術
- slot-a/b checkpoint 設計を共有ファイルシステム (FSx for Lustre 等)
  前提に作り直す必要がある

### それでも Phase 8 としてやる理由

「BH-NS を題材にクラウドで大規模科学計算をやる経験を作る」という本来の目的に
照らすと、**マルチノード MPI は単一ノードでは絶対に学べないクラウド HPC の
核心スキル**。参照 run 自体が 12 ノードだったという事実もある。

- 題材は本番ではなく **dx=28 のローレゾ問題**を流用する
- 構成: 2 × c7a.16xlarge spot、**EFA なしの TCP + 現行 MPICH イメージ +
  hostfile**。「TCP だとどれだけ悲惨か」を実測すること自体が一級の成果
- 予算 $10–20 (本番完了後の残予算で実施)
- **次の題材 (BNS 等) で本格的にマルチノードを使うかの判断材料**にする

### Phase 5 に組み込む分岐条件

参照実測のメモリ 438.5 GB (480 rank 合計) を踏まえると、
**np=192 で c7a.48xlarge の 384 GB に載らないシナリオは現実にありうる**。
480 → 192 rank で集約メモリ帯域も約 1/5 になり、ET は帯域律速なので
sec/iter が想定より悪化する可能性もある。したがって Phase 5 の測定設計に
**「単一ノードでメモリ超過または予算超過なら 2 ノード TCP を試す」という
分岐を最初から書いておく**。この場合マルチノードは「趣味」ではなく
「必要条件」に変わる。

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

### 英語で書くもの / 日本語で書くもの (プロジェクト規約)

**英語必須** — リポジトリにコミットされる成果物の中身:

- ソース・設定ファイルのコメント全般
  (`Dockerfile`, `docker-compose.yml`, `.env.example`, `.dockerignore`,
  `Makefile`, `makefiles/*.mk`, `docker/cactus.cfg`, `requirements.txt`,
  `par/*.par`, Python/シェルスクリプト)
- `make` ターゲットのヘルプテキスト (`## コメント`) と `echo` 出力
- ログメッセージ、エラーメッセージ、docstring、コミットメッセージ
- `README.md` (対外向け)

**日本語で可** — 人間が読む記録:

- `CLAUDE.md` (本ファイル)
- `.claude-notes/` のセッションノート
- チャット上の応答

**重要**: 他リポジトリ (例: `../gw150914-einstein-toolkit`) からファイルを
コピーして流用する場合も、**コピー元の日本語コメントは必ず英語に書き換える**こと。
コピーしたファイルは「既存コード」ではなく新規成果物として扱う。
Phase 1 で GW150914 repo から Docker 基盤を移植した際、
日本語コメントをそのまま持ち込んで規約違反を作り込んだ実績がある。

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
