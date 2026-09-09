# start-qemu

A thin wrapper script for launching QEMU virtual machines from named,
reusable configuration profiles.

Instead of remembering (or copy-pasting) a long `qemu-system-*` command
line for each VM, define each VM once as a named section in a config
file, then start it with:

```sh
./start-qemu.sh ARCH/name
```

## Features

- Named VM profiles, grouped by architecture (`ARCH/name`), defined in
  a simple INI-like config file.
- Interactive selection menu when no name is given, or when the given
  name isn't found.
- `-l` flag to list all available profile names non-interactively.
- `-o 'option'` flag to append extra, one-off QEMU options on the
  command line (can be given multiple times).
- Limited `$HOME`/`${HOME}` expansion inside the config file via `envsubst`.
- Stale PID file detection: refuses to start a VM that's already
  running, and cleans up leftover PID files from crashed runs.
- Uses `exec` to hand off directly to `qemu-system-*`, so the wrapper
  doesn't linger as an extra process.

## Requirements

- `bash` >= 4.3 (uses `declare -n` namerefs)
- [`envsubst`](https://www.gnu.org/software/gettext/) (Debian/Ubuntu
  package: `gettext-base`)
- `pgrep`/`ps` (Debian/Ubuntu package: `procps`)
- `qemu-system-<ARCH>` for whichever architectures you configure
  (Debian/Ubuntu package: `qemu-system-<arch>`, e.g. `qemu-system-x86`)

## Installation

Clone the repository, or just copy the two files (`start-qemu.sh` and
`start-qemu.cfg`) into the same directory. The config file must sit
next to the script and share its basename, i.e. for `start-qemu.sh`
the script looks for `start-qemu.cfg` in the same directory.

```sh
git clone https://github.com/<you>/start-qemu.git
cd start-qemu
chmod +x start-qemu.sh
```

## Usage

```
usage: $0 [-h] [-l] [-o 'option'] ... [ARCH/name]
    -h: show this help message
    -l: list the available names
    -o 'option': additional option for QEMU
    -h and -l are mutually exclusive; whichever is given last takes effect.
    -l only produces a listing when ARCH/name is omitted or not found; if a valid ARCH/name is given, -l is ignored and the VM starts directly.
    If ARCH/name is not specified or not found, the script will prompt to select a name.
```

Examples:

```sh
# List all configured VM profiles
./start-qemu.sh -l

# Start a specific profile
./start-qemu.sh x86_64/debian

# Start a profile with an extra, one-off option
./start-qemu.sh -o '-vnc :1' x86_64/debian

# No name given: pick interactively from a menu
./start-qemu.sh
```

## Configuration file format

The config file (e.g. `start-qemu.cfg`) is a plain-text file with the
following structure:

```ini
# It is assumed the image files are located in {LOCATION}/{section name}.
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
-netdev user,id=net0,hostfwd=tcp::60022-:22
-device virtio-net-pci,netdev=net0
```

- **Comments**: Lines starting with `#` or `;` are ignored, as are
  blank lines.
- **`LOCATION`**: sets the base directory under which each VM's working directory
  (`{LOCATION}/{ARCH}/{name}`) is expected to exist. Only `$HOME`/`${HOME}` is
  expanded in this value.
- **Sections**: A line of the form `[ARCH/name]` starts a new profile.
  `ARCH` must match a suffix accepted by `qemu-system-<ARCH>` (e.g.
  `x86_64`, `aarch64`); `name` is an arbitrary label of your choosing.
  Duplicate section names are not explicitly prohibited; the first matching section wins.
- **Options**: Every non-comment, non-section line following a
  `[ARCH/name]` header, up to the next section header, is a QEMU
  option. Each line holds exactly one option and, optionally, one
  argument, separated by whitespace — for example:
  ```ini
  -drive file=debian-13-nocloud-amd64.qcow2,if=virtio,format=qcow2
  ```
  Arguments do not need to be quoted, even if they contain spaces
  (quotation marks are treated literally, not stripped). Only `$HOME`/`${HOME}`
  is expanded in option arguments.

### Working directory

Before launching QEMU, the script changes into
`{LOCATION}/{ARCH}/{name}` (e.g. `~/.local/share/qemu/x86_64/debian`).
Any relative paths in the profile's `-drive file=...` options are
resolved from there, and that's also where the `qemu.pid` file is
written.

## Notes

- If a `qemu.pid` file exists in the VM's working directory and the
  corresponding process is still alive, the script refuses to start a
  second instance of the same VM and prints its `ps` info instead.
  If the process is no longer running, the stale PID file is removed
  automatically.
- The config parser is intentionally minimal: it only understands the
  three line types described above (comments/blanks, `LOCATION=`, and
  `[ARCH/name]` + options). Any invalid line encountered while parsing
  is treated as a syntax error.

## License

This script is released under the [GNU General Public License](https://www.gnu.org/licenses/gpl-2.0.txt), version 2.