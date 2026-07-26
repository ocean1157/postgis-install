#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec bash "$0" "$@"; fi
set -Eeuo pipefail

# Download the complete RPM dependency closure for the current EL7/EL8 host.
# GIS packages are included only when the enabled repositories provide a
# version that satisfies the PostGIS 3.4 minimum; install.sh uses bundled
# sources for the remaining components.

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PACKAGES_DIR="${PACKAGES_DIR:-${SCRIPT_DIR}/packages}"
CHECK_ONLY=0

log() { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: sudo bash downloadrpm.sh [--check]

Downloads the complete RPM dependency closure available from the current
EL7/EL8 yum repositories into packages/rpm/el<major>/<arch>/.

  --check   Show package/version selection without downloading
  -h        Show this help
EOF
}

while (($#)); do
    case "$1" in
        --check) CHECK_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1 (use --help)" ;;
    esac
done

[[ "$(id -u)" -eq 0 ]] || die "Run as root: sudo ./downloadrpm.sh"
[[ -r /etc/os-release ]] || die "/etc/os-release not found"
# shellcheck disable=SC1091
source /etc/os-release

EL_MAJOR="${VERSION_ID%%.*}"
case "$EL_MAJOR" in
    7|8) ;;
    *) die "Supported systems: RHEL-compatible EL7/EL8; detected ${ID:-unknown} ${VERSION_ID:-unknown}" ;;
esac
case " ${ID:-} ${ID_LIKE:-} " in
    *" rhel "*|*" centos "*|*" fedora "*|*" rocky "*|*" almalinux "*|*" ol "*|*" anolis "*) ;;
    *) die "Unsupported non-RHEL-compatible system: ${ID:-unknown} ${VERSION_ID:-unknown}" ;;
esac

RPM_ARCH="$(rpm --eval '%{_arch}')"
RPM_DIR="${RPM_DIR:-${PACKAGES_DIR}/rpm/el${EL_MAJOR}/${RPM_ARCH}}"
mkdir -p "$RPM_DIR"

log "Checking enabled yum repositories"
if [[ "$EL_MAJOR" == 7 ]]; then
    yum -q makecache fast || die "The current yum repositories are unavailable"
else
    command -v dnf >/dev/null 2>&1 || die "dnf is required on EL8"
    dnf -q makecache || die "The current dnf/yum repositories are unavailable"
fi

version_ge() {
    local actual="${1%%-*}" minimum="$2"
    [[ "$(printf '%s\n%s\n' "$minimum" "$actual" | sort -V | head -n1)" == "$minimum" ]]
}

yum_candidate_version() {
    local package="$1"
    yum --showduplicates list available "$package" 2>/dev/null |
        awk -v name="$package" '
            $1 == name || index($1, name ".") == 1 { version=$2 }
            END {
                sub(/^[0-9]+:/, "", version)
                sub(/-[^-]+$/, "", version)
                print version
            }' || true
}

declare -a ROOT_PACKAGES=(
    gcc gcc-c++ make autoconf automake libtool
    bzip2 xz tar gzip wget sudo
    gmp-devel mpfr-devel boost-devel
    libxml2-devel json-c-devel libcurl-devel
    libtiff-devel libjpeg-turbo-devel libpng-devel
    zlib-devel openssl-devel readline-devel
)
declare -a GIS_PACKAGES=()

select_if_usable() {
    local package="$1" minimum="$2" candidate
    candidate="$(yum_candidate_version "$package")"
    if [[ -n "$candidate" ]] && version_ge "$candidate" "$minimum"; then
        GIS_PACKAGES+=("$package")
        log "RPM selected: ${package} ${candidate} (required >= ${minimum})"
    elif [[ -n "$candidate" ]]; then
        log "RPM skipped: ${package} ${candidate} is below ${minimum}; install.sh will use packages/ source"
    else
        log "RPM skipped: ${package} is unavailable; install.sh will use packages/ source"
    fi
}

select_if_usable cmake 3.13
select_if_usable geos-devel 3.6
select_if_usable proj-devel 6.1
select_if_usable gdal-devel 2.0
select_if_usable SFCGAL-devel 1.3.1
select_if_usable protobuf-c-devel 1.1.0
select_if_usable pcre-devel 8.0

ALL_PACKAGES=("${ROOT_PACKAGES[@]}" "${GIS_PACKAGES[@]}")
log "Downloading RPM dependency closure for ${PRETTY_NAME}, arch=${RPM_ARCH}"
printf 'Destination: %s\nRoot packages: %s\n' "$RPM_DIR" "${ALL_PACKAGES[*]}"
if ((CHECK_ONLY)); then
    log "RPM download preflight passed; no files were downloaded"
    exit 0
fi

if [[ "$EL_MAJOR" == 8 ]]; then
    if ! dnf download --help >/dev/null 2>&1; then
        log "Installing dnf-plugins-core on this online preparation host"
        dnf -y install dnf-plugins-core
    fi
    dnf download --resolve --alldeps --destdir "$RPM_DIR" "${ALL_PACKAGES[@]}"
else
    if ! command -v repotrack >/dev/null 2>&1; then
        log "Installing yum-utils on this online preparation host"
        yum -y install yum-utils
    fi
    command -v repotrack >/dev/null 2>&1 || die "repotrack was not installed"
    repotrack -a "$RPM_ARCH" -p "$RPM_DIR" "${ALL_PACKAGES[@]}"
fi

RPM_COUNT="$(find "$RPM_DIR" -maxdepth 1 -type f -name '*.rpm' | wc -l | tr -d ' ')"
[[ "$RPM_COUNT" -gt 0 ]] || die "No RPM files were downloaded"

if command -v createrepo_c >/dev/null 2>&1; then
    createrepo_c --update "$RPM_DIR"
elif command -v createrepo >/dev/null 2>&1; then
    createrepo --update "$RPM_DIR"
else
    log "createrepo is unavailable; RPM files are complete but repository metadata was not generated"
fi

{
    printf 'created_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'os=%s\nos_major=%s\narch=%s\nrpm_files=%s\n' \
        "${PRETTY_NAME}" "$EL_MAJOR" "$RPM_ARCH" "$RPM_COUNT"
    printf 'root_packages=%s\n' "${ALL_PACKAGES[*]}"
} > "$RPM_DIR/OFFLINE-ENVIRONMENT.txt"

(cd "$RPM_DIR" && sha256sum ./*.rpm > SHA256SUMS)
log "RPM download completed: ${RPM_COUNT} files in ${RPM_DIR}"
