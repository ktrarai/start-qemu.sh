#!/usr/bin/env bash
# A thin wrapper for QEMU.
# depends: `envsubst` (gettext-base), `pgrep`/'ps' (procps), `qemu-system-ARCH` (part of qemu / qemu-system-<arch>)
# usage: start-qemu.sh [-h] [-l] [-o 'option'] ... [ARCH/name]

set -o errexit
set -o nounset
set -o pipefail

script_root=$(cd "$(dirname "$0")" && pwd)
readonly script_root

cfg_file="${script_root}/$(basename "$0" .sh).cfg"
readonly cfg_file

declare section_name=$'\n'  # must not match any section name in the cfg file
declare ARCH='' LOCATION='' help='false' list='false' _opt _arg
declare -a cli_options=() qemu_options section_names

write_error ()
{
    printf '%s: %s\n' "${0}" "${1}" 1>&2
}

split ()
{
    local -n _first=${2} _rest=${3}
    _first=${1%%[[:space:]]*}
    _rest=${1#*[[:space:]]}
}

trim ()
{
    local -n ref=${1}
    ref=${ref#"${ref%%[![:space:]]*}"}
    ref=${ref%"${ref##*[![:space:]]}"}
}

append_qemu_option ()
{
    local _str=${1} _opt _arg
    if [[ "${_str}" = *[[:space:]]* ]]
    then
        split "${_str}" _opt _arg
        trim _opt
        trim _arg
        qemu_options+=("${_opt}" "${_arg}") 
    else
        qemu_options+=("${_str}")
    fi
}

# parse the cfg file and get the options for the specified section name
# global variables: section_name, ARCH, LOCATION, qemu_options, section_names
get_cfg ()
{
    qemu_options=() section_names=()
    local found='false' _section_name _val _opt _arg
    local -i line_num=0

    while IFS= read -r REPLY || [[ -n "${REPLY}" ]]
    do
        line_num=$((line_num + 1))
        trim REPLY
        if [[ "${REPLY}" =~ ^([#;].*|)$ ]]
        then
            continue
        elif [[ "${REPLY}" =~ ^LOCATION[[:space:]]*=[[:space:]]*[[:graph:]] ]]
        then
            _val=${REPLY#*=}
            trim _val
            LOCATION=${_val}
        elif [[ "${REPLY}" = "[${section_name}]" ]]
        then
            found='true'
            ARCH=${section_name%%/*}
        elif [[ "${REPLY}" =~ ^\[[-[:alnum:]._]+/[-[:alnum:]._]+\]$ ]]
        then
            [[ "${found}" = 'true' ]] && break
            _section_name=${REPLY#\[} _section_name=${_section_name%\]}
            trim _section_name
            section_names+=("${_section_name}")
        elif [[ "${REPLY}" =~ --?[[:alnum:]].* ]]
        then
            [[ "${found}" = 'true' ]] && append_qemu_option "${REPLY}"
        else
            write_error "${cfg_file}: invalid line: ${line_num}: ${REPLY}"
            exit 1
        fi
    done

    [[ "${found}" = 'true' ]]
} < <(envsubst '$HOME' < "${cfg_file}")

usage ()
{
    cat <<EOF
usage: $0 [-h] [-l] [-o 'option'] ... [ARCH/name]
    -h: show this help message
    -l: list the available names
    -o 'option': additional option for QEMU
    -h and -l are mutually exclusive; whichever is given last takes effect.
    -l only produces a listing when ARCH/name is omitted or not found; if a valid ARCH/name is given, -l is ignored and the VM starts directly.
    If ARCH/name is not specified or not found, the script will prompt to select a name.
EOF
}

trap 'status=$?; write_error "an unexpected error occurred at line ${LINENO}"; exit "${status}"' ERR

[[ "${BASH_VERSINFO[0]}" -gt 4 || "${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -ge 3 ]] || {
    write_error 'Bash 4.3 or later is required.'
    exit 1
}

[[ -r "${cfg_file}" ]] || {
    write_error "${cfg_file}: not found or not readable"
    exit 1
}

command -v envsubst >/dev/null 2>&1 || {
    write_error "envsubst is required. (install gettext package.)"
    exit 1
}

# parse the command line arguments

while getopts ":hlo:" opt
do
    case "${opt}" in
    h)
        help='true'
        list='false'
        ;;
    l)
        list='true'
        help='false'
        ;;
    o)
        cli_options+=("${OPTARG}")
        ;;
    :)
        write_error "option -${OPTARG}: an argument is required"
        usage 1>&2
        exit 1
        ;;
    *)
        write_error "invalid option: -${OPTARG}"
        usage 1>&2
        exit 1
        ;;
    esac
done

[[ "${help}" = 'true' ]] && {
    usage
    exit 0
}

shift $((OPTIND - 1))

case $# in
0)
    : ;;
1)
    section_name=${1} ;;
*)
    write_error 'too many arguments'
    usage 1>&2
    exit 1
    ;;
esac

# parse the cfg file and get the options for the specified section name

get_cfg ||
    if [[ "${list}" = 'true' ]]
    then
        printf '%s\n' "${section_names[@]}"
        exit 0
    else
        select section_name in "${section_names[@]}"
        do
            [[ -n "${section_name}" ]] && break
        done
        get_cfg
    fi

declare -n prop

for prop in ARCH LOCATION
do
    [[ -v prop && -n "${prop}" ]] || {
        write_error "${!prop} is not set"
        exit 1
    }
done

# launch qemu-system-${ARCH}

command -v "qemu-system-${ARCH}" >/dev/null 2>&1 || {
    write_error "qemu-system-${ARCH} is not installed or ${ARCH} is not supported by QEMU."
    exit 1
}

dir="${LOCATION}/${section_name}"
cd "${dir}" || {
    write_error "failed to change directory: ${dir}"
    exit 1
}

[[ -r qemu.pid ]] && 
    if pgrep -L -F qemu.pid >/dev/null 2>&1
    then
        write_error "${section_name} is already running:"
        ps -ww -p "$(< qemu.pid)" 1>&2
        exit 1
    else
        rm -f qemu.pid
    fi

for _opt in "${cli_options[@]}"
do
    append_qemu_option "${_opt}"
done

exec "qemu-system-${ARCH}" "${qemu_options[@]}" -pidfile qemu.pid
