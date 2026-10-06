# start-qemu.sh

名前付き、再利用可能な設定プロファイルから QEMU 仮想マシンを起動する薄いラッパースクリプトです。

各 VM に対して長い `qemu-system-*` コマンドラインを覚える（またはコピー＆ペースト）必要がなく、設定ファイル内の名前付きセクションとして一度だけ VM を定義したら、次のように起動できます：

```sh
./start-qemu.sh ARCH/name
```

## 機能

- アーキテクチャ（`ARCH/name`）ごとにグループ化された名前付き VM プロファイルを、シンプルな INI 風の設定ファイルで定義。
- 名前が指定されていない場合や、指定された名前が見つからない場合は、インタラクティブな選択メニューを表示。
- `-l` フラグで、利用可能なプロファイル名を非インタラクティブに一覧表示。
- `-o 'option'` フラグで、一時的な QEMU オプションを追加（複数回指定可能）。
- 設定ファイル内で `$HOME`／`${HOME}` の展開を `envsubst` を使って限定的にサポート。
- 古い PID ファイルの検出：同じ VM が既に実行中の場合は起動を拒否し、クラッシュによって残った PID ファイルをクリーンアップ。
- `exec` を使って直接 `qemu-system-*` に制御を渡すため、ラッパー自身は余分なプロセスとして残らない。

## 要件

- `bash` >= 4.3（`declare -n` の名前参照を使用）
- [`envsubst`](https://www.gnu.org/software/gettext/)（Debian/Ubuntu では `gettext-base` パッケージ）
- `pgrep`／`ps`（Debian/Ubuntu では `procps` パッケージ）
- 設定するアーキテクチャに対応する `qemu-system-<ARCH>`（Debian/Ubuntu では `qemu-system-<arch>` パッケージ、例: `qemu-system-x86`）

## インストール

リポジトリをクローンするか、あるいは `start-qemu.sh` と `start-qemu.cfg` の 2 つのファイルを同じディレクトリにコピーしてください。設定ファイルはスクリプトと同じディレクトリに置き、ベース名を合わせる必要があります（すなわち `start-qemu.sh` に対しては同じディレクトリに `start-qemu.cfg` を置きます）。

```sh
git clone https://github.com/ktrarai/start-qemu.sh.git
cd start-qemu
chmod +x start-qemu.sh
```

## 使い方

```
usage: $0 [-h] [-l] [-o 'option'] ... [ARCH/name]
    -h: このヘルプメッセージを表示
    -l: 利用可能な名前を一覧表示
    -o 'option': QEMU に追加するオプション
    -h と -l は排他であり、最後に指定された方が有効になる。
    -l は ARCH/name が省略されているか見つからない場合のみ一覧を出力し、有効な ARCH/name が指定されている場合は無視され、VM が直接起動される。
    ARCH/name が指定されていないか見つからない場合は、スクリプトが名前の選択を促すインタラクティブメニューを表示する。
```

例：

```sh
# 設定済みのすべての VM プロファイルを一覧表示
./start-qemu.sh -l

# 特定のプロファイルを起動
./start-qemu.sh x86_64/debian

# 追加の一時オプションを付けてプロファイルを起動
./start-qemu.sh -o '-vnc :1' x86_64/debian

# 名前を指定しない場合：インタラクティブなメニューから選択
./start-qemu.sh
```

## 設定ファイルの形式

設定ファイル（例: `start-qemu.cfg`) はプレーンテキストで、以下の構造になります：

```ini
# イメージファイルは {LOCATION}/{section name} にあると仮定します。
LOCATION = ${HOME}/.local/share/qemu

[x86_64/debian]
-machine type=q35
-cpu host
-accel accel=kvm
-m size=2048
-name Debian 13 (Trixie)
-drive file=debian-13-nocloud-amd64.qcow2,if=virtio,format=qcow2
-snapshot
-nographic
-netdev user=id=net0,hostfwd=tcp::60022-:22
-device virtio-net-pci,netdev=net0
```

- **コメント**: `#` または `;` で始まる行および空行は無視されます。
- **`LOCATION`**: 各 VM の作業ディレクトリ (`{LOCATION}/{ARCH}/{name}`) のベースディレクトリを設定します。この値では `$HOME`／`${HOME}` のみが展開されます。
- **セクション**: `[ARCH/name]` 形式の行で新しいプロファイルが開始されます。`ARCH` は `qemu-system-<ARCH>` が受け入れるサフィックス（例: `x86_64`, `aarch64`）に一致する必要があります。`name` は任意のラベルです。同名のセクションが重複しても明示的に禁止されていませんが、最初にマッチしたセクションが使用されます。
- **オプション**: `[ARCH/name]` ヘッダーの後に続く、次のセクションヘッダーまでの非コメント・非空行は、それぞれ QEMU のオプションとなります。1 行につきちょうど 1 つのオプション（および省略可能な引数）を記述し、間は空白で区切ります。例：

  ```ini
  -drive file=debian-13-nocloud-amd64.qcow2,if=virtio,format=qcow2
  ```

  引数に空白が含まれても引用符で囲む必要はありません（引用符は文字通り扱われ、取り除かれません）。オプションの引数では `$HOME`／`${HOME}` のみが展開されます。

### 作業ディレクトリ

QEMU を起動前に、スクリプトは `{LOCATION}/{ARCH}/{name}`（例: `~/.local/share/qemu/x86_64/debian`）にディレクトリを変更します。このため、プロファイル内の `-drive file=...` オプションに指定した相対パスはそこから解決され、同じ場所に `qemu.pid` ファイルが書き込まれます。

## 注意点

- VM の作業ディレクトリに `qemu.pid` ファイルが存在し、対応するプロセスがまだ生きている場合、スクリプトは同じ VM の 2 番目のインスタンスの起動を拒否し、そのプロセスの `ps` 情報を表示します。プロセスが終了している場合は、古い PID ファイルは自動的に削除されます。
- 設定パーサーは意図的に最小限に抑えており、コメント/空行、`LOCATION=` 行、`[ARCH/name]` ヘッダーおよびそれに続くオプションの 3 種類の行しか理解しません。パース中に無効な行が見つかった場合は構文エラーとして扱われます。

## ライセンス

このスクリプトは [GNU General Public License](https://www.gnu.org/licenses/gpl-2.0.txt)（バージョン 2）の下でリリースされています。