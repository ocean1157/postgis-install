#!/usr/bin/env bash
set -Eeuo pipefail

# ======================== User configuration ========================
# Leave a value empty to discover it from the postgres login environment and
# postgresql17-ha-patroni-etcd's ~/.pgev. If discovery fails, defaults below
# are applied. Command-line options override these values.
PG_USER="${PG_USER:-}"
PG_CONFIG="${PG_CONFIG:-}"
PGHOME="${PGHOME:-}"
PGBIN="${PGBIN:-}"
PGPORT="${PGPORT:-}"
PGDATABASE="${PGDATABASE:-}"
INSTALL_PREFIX="${INSTALL_PREFIX:-}"
SQLITE_PREFIX="${SQLITE_PREFIX:-}"
PACKAGES_DIR="${PACKAGES_DIR:-}"
JOBS="${JOBS:-}"
CREATE_EXTENSION="${CREATE_EXTENSION:-}"
KEEP_BUILD="${KEEP_BUILD:-0}"
PREFER_YUM="${PREFER_YUM:-1}"
# ====================================================================

# PostGIS source installer for PostgreSQL clusters managed by Patroni.
# Run this script as root on every PostgreSQL node. It detects the PostgreSQL
# installation produced by postgresql17-ha-patroni-etcd and never replaces it.

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CHECK_ONLY=0

usage() {
    cat <<'EOF'
Usage: sudo ./install.sh [options]

Installs PostGIS against the existing PostgreSQL/Patroni installation.
Run it on every PostgreSQL node; on the Patroni leader it also creates the
postgis extension in the target database by default.
The script must run as root and switches to the PostgreSQL OS user internally
for environment discovery and database commands.

Options:
  -i, --prefix DIR          Dependency installation prefix (default: /usr/local)
  -s, --sqlite-prefix DIR   SQLite installation prefix (default: PREFIX/sqlite)
  -p, --pg-config FILE      Existing PostgreSQL pg_config path
  -d, --database NAME       Database used for CREATE EXTENSION (default: postgres)
      --create-extension    Always create the extension (must run on leader)
      --no-create-extension Do not create the extension
      --check               Validate OS, packages and PostgreSQL paths only
      --source-only         Do not use dependency packages from enabled yum repos
  -j, --jobs N              Parallel build jobs
  -h, --help                Show this help

Environment overrides: PG_CONFIG, PGHOME, PGBIN, PGPORT, PGDATABASE,
INSTALL_PREFIX, SQLITE_PREFIX, PACKAGES_DIR, JOBS, CREATE_EXTENSION,
PREFER_YUM (1 by default, set to 0 to build every bundled dependency).
EOF
}

log() { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_option_value() {
    [[ $# -ge 2 && -n "${2:-}" && "${2:-}" != -* ]] ||
        die "Option $1 requires a value"
}

while (($#)); do
    case "$1" in
        -i|--prefix) require_option_value "$@"; INSTALL_PREFIX="$2"; shift 2 ;;
        -s|--sqlite-prefix) require_option_value "$@"; SQLITE_PREFIX="$2"; shift 2 ;;
        -p|--pg-config)
            require_option_value "$@"
            PG_CONFIG="$2"
            [[ "$PG_CONFIG" == */pg_config ]] || PG_CONFIG="${PG_CONFIG%/}/pg_config"
            shift 2
            ;;
        -d|--database) require_option_value "$@"; PGDATABASE="$2"; shift 2 ;;
        -j|--jobs) require_option_value "$@"; JOBS="$2"; shift 2 ;;
        --create-extension) CREATE_EXTENSION=always; shift ;;
        --no-create-extension) CREATE_EXTENSION=never; shift ;;
        --check) CHECK_ONLY=1; shift ;;
        --source-only) PREFER_YUM=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1 (use --help)" ;;
    esac
done

[[ "$(id -u)" -eq 0 ]] || die "Run as root: sudo ./install.sh"
[[ -r /etc/os-release ]] || die "/etc/os-release not found"
# shellcheck disable=SC1091
source /etc/os-release
EL_MAJOR="${VERSION_ID%%.*}"
case "$EL_MAJOR" in
    7|8) ;;
    *) die "Supported systems: RHEL-compatible EL7/EL8; detected ${ID:-unknown} ${VERSION_ID:-unknown}" ;;
esac

# Anolis OS and other RHEL rebuilds identify compatibility through ID_LIKE
# instead of using one of the traditional RHEL/CentOS IDs.
case " ${ID:-} ${ID_LIKE:-} " in
    *" rhel "*|*" centos "*|*" fedora "*|*" rocky "*|*" almalinux "*|*" ol "*|*" anolis "*) ;;
    *) die "Unsupported non-RHEL-compatible system: ${ID:-unknown} ${VERSION_ID:-unknown} (ID_LIKE=${ID_LIKE:-unset})" ;;
esac

PG_USER="${PG_USER:-postgres}"
PG_LOGIN_PG_CONFIG=""

# First inspect the postgres login environment, then read only known values
# from .pgev. This preserves explicit top-of-file/CLI values.
load_pg_environment() {
    local pg_home pg_env_file line key value login_pg_config
    getent passwd "$PG_USER" >/dev/null 2>&1 || return 0
    pg_home="$(getent passwd "$PG_USER" | cut -d: -f6)"

    if command -v sudo >/dev/null 2>&1; then
        login_pg_config="$(
            sudo -iu "$PG_USER" bash -lc 'command -v pg_config 2>/dev/null || true' 2>/dev/null |
                tail -n1
        )"
    elif command -v runuser >/dev/null 2>&1; then
        login_pg_config="$(
            runuser -l "$PG_USER" -c "bash -lc 'command -v pg_config 2>/dev/null || true'" 2>/dev/null |
                tail -n1
        )"
    else
        login_pg_config="$(
            su - "$PG_USER" -c "bash -lc 'command -v pg_config 2>/dev/null || true'" 2>/dev/null |
                tail -n1
        )"
    fi
    [[ -n "$login_pg_config" ]] && PG_LOGIN_PG_CONFIG="$login_pg_config"

    pg_env_file="${pg_home}/.pgev"
    [[ -r "$pg_env_file" ]] || return 0
    while IFS= read -r line; do
        [[ "$line" == export\ *=* ]] || continue
        key="${line#export }"
        key="${key%%=*}"
        value="${line#*=}"
        case "$key" in
            PGHOME|PGBIN|PGDATA|PGPORT|PGDATABASE|PGUSER|PGHOST|PATRONI_CONFIG|PATRONICTL_CONFIG_FILE)
                if [[ "$value" == \"*\" && "$value" == *\" ]]; then
                    value="${value:1:${#value}-2}"
                elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
                    value="${value:1:${#value}-2}"
                fi
                [[ -n "${!key:-}" ]] || printf -v "$key" '%s' "$value"
                export "$key"
                ;;
        esac
    done < "$pg_env_file"
}
load_pg_environment

# Apply defaults only after postgres environment discovery.
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
SQLITE_PREFIX="${SQLITE_PREFIX:-${INSTALL_PREFIX}/sqlite}"
PACKAGES_DIR="${PACKAGES_DIR:-${SCRIPT_DIR}/packages}"
PGDATABASE="${PGDATABASE:-postgres}"
CREATE_EXTENSION="${CREATE_EXTENSION:-auto}"
readonly PACKAGES_DIR

find_pg_config() {
    local candidate version
    local -a candidates=()
    [[ -n "$PG_CONFIG" ]] && candidates+=("$PG_CONFIG")
    [[ -n "$PG_LOGIN_PG_CONFIG" ]] && candidates+=("$PG_LOGIN_PG_CONFIG")
    [[ -n "${PGBIN:-}" ]] && candidates+=("${PGBIN%/}/pg_config")
    [[ -n "${PGHOME:-}" ]] && candidates+=("${PGHOME%/}/bin/pg_config")
    candidates+=(
        /home/postgres/pghome/bin/pg_config
        /home/postgres/pg/bin/pg_config
        /usr/pgsql-17/bin/pg_config
        /usr/local/pgsql/bin/pg_config
    )
    command -v pg_config >/dev/null 2>&1 && candidates+=("$(command -v pg_config)")
    while IFS= read -r candidate; do candidates+=("$candidate"); done < <(
        find /home/postgres /opt /usr/local -maxdepth 5 -type f -path '*/bin/pg_config' 2>/dev/null || true
    )

    for candidate in "${candidates[@]}"; do
        [[ -x "$candidate" ]] || continue
        version="$("$candidate" --version 2>/dev/null || true)"
        if [[ "$version" == PostgreSQL\ * ]]; then
            PG_CONFIG="$(readlink -f "$candidate")"
            return 0
        fi
    done
    return 1
}

find_pg_config || die "PostgreSQL pg_config not found. Set PG_CONFIG or use --pg-config."
readonly PG_CONFIG
readonly PG_BINDIR="$("$PG_CONFIG" --bindir)"
readonly PG_PKGLIBDIR="$("$PG_CONFIG" --pkglibdir)"
readonly PG_SHAREDIR="$("$PG_CONFIG" --sharedir)"
[[ -x "$PG_BINDIR/postgres" ]] ||
    die "Selected pg_config does not match a complete PostgreSQL installation: $PG_CONFIG"
[[ -x "$PG_BINDIR/psql" ]] ||
    die "psql was not found beside the selected PostgreSQL installation: $PG_BINDIR"
PG_USER="${PG_USER:-$(stat -c '%U' "$PG_BINDIR/postgres")}"
[[ "$PG_USER" != UNKNOWN ]] || PG_USER=postgres
readonly PG_USER

# Minimum versions documented by the PostGIS 3.4 installation manual.
# For optional libraries we use the recommended version when it unlocks all
# PostGIS functionality.
declare -A MIN_VERSION=(
    [geos]=3.6
    [proj]=6.1
    [libxml2]=2.5
    [json-c]=0.9
    [gdal]=2.0
    [sfcgal]=1.3.1
    [protobuf-c]=1.1.0
    [llvm]=6.0
)

[[ -d "$PACKAGES_DIR" ]] || die "Package directory not found: $PACKAGES_DIR"

declare -A ARCHIVES=(
    [cmake]="CMake-3.30.2.tar.gz"
    [geos]="geos-3.9.5.tar.bz2"
    [sqlite]="sqlite-autoconf-3460100.tar.gz"
    [proj]="proj-6.3.1.tar.gz"
    [protobuf]="protobuf-all-3.15.3.tar.gz"
    [protobuf-c]="protobuf-c-1.3.3.tar.gz"
    [gdal]="gdal-3.0.4.tar.gz"
    [cgal]="CGAL-4.14.3.tar.xz"
    [sfcgal]="v1.3.7"
    [pcre]="pcre-8.45.tar.gz"
    [postgis]="postgis-3.4.2.tar.gz"
)
for archive in "${ARCHIVES[@]}"; do
    [[ -s "$PACKAGES_DIR/$archive" ]] || die "Missing package: packages/$archive"
done

if [[ -z "$JOBS" ]]; then
    JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
fi
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer"

log "Detected ${PRETTY_NAME}"
printf 'PostgreSQL: %s\npg_config: %s\npkglibdir: %s\nsharedir: %s\npackages: %s\n' \
    "$("$PG_CONFIG" --version)" "$PG_CONFIG" "$PG_PKGLIBDIR" "$PG_SHAREDIR" "$PACKAGES_DIR"
install_os_dependencies() {
    local -a packages=(
        gcc gcc-c++ make autoconf automake libtool
        bzip2 xz tar gzip wget sudo
        gmp-devel mpfr-devel boost-devel
        libxml2-devel json-c-devel libcurl-devel
        libtiff-devel libjpeg-turbo-devel libpng-devel
        zlib-devel openssl-devel readline-devel
    )
    local -a missing=()
    local package
    for package in "${packages[@]}"; do
        rpm -q "$package" >/dev/null 2>&1 || missing+=("$package")
    done
    if [[ "$EL_MAJOR" == 7 ]] && ! rpm -q epel-release >/dev/null 2>&1; then
        yum -y install epel-release || true
    fi
    if ((${#missing[@]} == 0)); then
        log "All required OS build RPMs are already installed; skipping yum install"
    else
        log "Installing missing OS build RPMs: ${missing[*]}"
        yum -y install "${missing[@]}"
    fi
}

version_ge() {
    local actual="${1%%-*}" minimum="$2"
    [[ "$(printf '%s\n%s\n' "$minimum" "$actual" | sort -V | head -n1)" == "$minimum" ]]
}

export PATH="$INSTALL_PREFIX/bin:$SQLITE_PREFIX/bin:$PG_BINDIR:$PATH"
export PKG_CONFIG_PATH="$SQLITE_PREFIX/lib/pkgconfig:$INSTALL_PREFIX/lib64/pkgconfig:$INSTALL_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$INSTALL_PREFIX/lib64:$INSTALL_PREFIX/lib:${LD_LIBRARY_PATH:-}"
export CPPFLAGS="-I$INSTALL_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$INSTALL_PREFIX/lib64 -L$INSTALL_PREFIX/lib ${LDFLAGS:-}"

extract_numeric_version() {
    grep -Eo '[0-9]+([.][0-9]+)+' | head -n1 || true
}

installed_dependency_version() {
    local component="$1" tool output=""
    case "$component" in
        cmake)
            tool="$(command -v cmake 2>/dev/null || true)"
            [[ -n "$tool" ]] && output="$("$tool" --version 2>/dev/null | head -n1)"
            ;;
        geos)
            tool="$(command -v geos-config 2>/dev/null || true)"
            [[ -n "$tool" ]] && output="$("$tool" --version 2>/dev/null)"
            ;;
        proj)
            if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists proj; then
                output="$(pkg-config --modversion proj 2>/dev/null)"
            fi
            ;;
        gdal)
            tool="$(command -v gdal-config 2>/dev/null || true)"
            [[ -n "$tool" ]] && output="$("$tool" --version 2>/dev/null)"
            ;;
        sfcgal)
            tool="$(command -v sfcgal-config 2>/dev/null || true)"
            [[ -n "$tool" ]] && output="$("$tool" --version 2>/dev/null)"
            ;;
        protobuf-c)
            tool="$(command -v protoc-c 2>/dev/null || true)"
            [[ -n "$tool" ]] && output="$("$tool" --version 2>/dev/null)"
            ;;
        pcre)
            tool="$(command -v pcre-config 2>/dev/null || true)"
            [[ -n "$tool" ]] && output="$("$tool" --version 2>/dev/null)"
            ;;
        *) return 1 ;;
    esac
    [[ -n "$output" ]] || return 1
    printf '%s\n' "$output" | extract_numeric_version
}

use_installed_dependency() {
    local component="$1" minimum="$2" installed
    installed="$(installed_dependency_version "$component")"
    [[ -n "$installed" ]] || return 1
    if version_ge "$installed" "$minimum"; then
        log "Already installed: ${component} ${installed} (required >= ${minimum}); skipping"
        return 0
    fi
    log "Installed ${component} ${installed} is below ${minimum}; looking for a newer yum/source version"
    return 1
}

yum_candidate_version() {
    local package="$1"
    yum --showduplicates list available "$package" 2>/dev/null |
        awk -v name="$package" '
            $1 == name || index($1, name ".") == 1 {
                version=$2
            }
            END {
                sub(/^[0-9]+:/, "", version)
                sub(/-[^-]+$/, "", version)
                print version
            }' || true
}

prefer_yum_dependency() {
    local component="$1" package="$2" minimum="$3" candidate
    [[ "$PREFER_YUM" == 1 ]] || return 1
    candidate="$(yum_candidate_version "$package")"
    if [[ -n "$candidate" ]] && version_ge "$candidate" "$minimum"; then
        log "Using yum dependency: ${package} ${candidate} (required >= ${minimum})"
        yum -y install "$package"
        return 0
    fi
    if [[ -n "$candidate" ]]; then
        log "Yum ${package} ${candidate} is below ${minimum}; using packages/ source"
    else
        log "Yum dependency ${package} is unavailable; using packages/ source"
    fi
    return 1
}

select_dependency() {
    local flag="$1" component="$2" package="$3" minimum="$4"
    if use_installed_dependency "$component" "$minimum"; then
        printf -v "$flag" '%s' 1
    elif prefer_yum_dependency "$component" "$package" "$minimum"; then
        printf -v "$flag" '%s' 1
    fi
}

print_dependency_policy() {
    cat <<EOF
Dependency minimums (PostGIS 3.4):
  GEOS >= ${MIN_VERSION[geos]}
  PROJ >= ${MIN_VERSION[proj]}
  LibXML2 >= ${MIN_VERSION[libxml2]}
  JSON-C >= ${MIN_VERSION[json-c]}
  GDAL >= ${MIN_VERSION[gdal]} (3.x preferred)
  SFCGAL >= ${MIN_VERSION[sfcgal]} (1.4.1 recommended for all features)
  protobuf-c >= ${MIN_VERSION[protobuf-c]}
  LLVM >= ${MIN_VERSION[llvm]} only when PostgreSQL was built with JIT
EOF
}

report_yum_candidate() {
    local package="$1" minimum="$2" candidate
    candidate="$(yum_candidate_version "$package")"
    if [[ -z "$candidate" ]]; then
        printf '  %-20s unavailable (source fallback)\n' "$package"
    elif version_ge "$candidate" "$minimum"; then
        printf '  %-20s %-12s usable (>= %s)\n' "$package" "$candidate" "$minimum"
    else
        printf '  %-20s %-12s too old (< %s; source fallback)\n' "$package" "$candidate" "$minimum"
    fi
}

print_dependency_policy
if ((CHECK_ONLY)); then
    log "Installed dependency versions"
    for component in cmake geos proj gdal sfcgal protobuf-c pcre; do
        installed="$(installed_dependency_version "$component")"
        printf '  %-12s %s\n' "$component" "${installed:-not found}"
    done
    if [[ "$PREFER_YUM" == 1 ]]; then
        log "Enabled yum repository candidates"
        report_yum_candidate geos-devel "${MIN_VERSION[geos]}"
        report_yum_candidate proj-devel "${MIN_VERSION[proj]}"
        report_yum_candidate libxml2-devel "${MIN_VERSION[libxml2]}"
        report_yum_candidate json-c-devel "${MIN_VERSION[json-c]}"
        report_yum_candidate gdal-devel "${MIN_VERSION[gdal]}"
        report_yum_candidate SFCGAL-devel "${MIN_VERSION[sfcgal]}"
        report_yum_candidate protobuf-c-devel "${MIN_VERSION[protobuf-c]}"
        report_yum_candidate pcre-devel 8.0
        report_yum_candidate cmake 3.13
    fi
    log "Preflight check passed"
    exit 0
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/postgis-install.XXXXXX")"
cleanup() {
    if [[ "$KEEP_BUILD" == 1 ]]; then
        log "Build directory retained: $WORK_DIR"
    else
        rm -rf -- "$WORK_DIR"
    fi
}
trap cleanup EXIT

extract() {
    local archive="$1"
    tar -xf "$PACKAGES_DIR/$archive" -C "$WORK_DIR"
}

make_install() {
    make -j "$JOBS"
    make install
}

install_os_dependencies

USE_SYSTEM_GEOS=0
USE_SYSTEM_PROJ=0
USE_SYSTEM_GDAL=0
USE_SYSTEM_SFCGAL=0
USE_SYSTEM_PROTOBUF_C=0
USE_SYSTEM_PCRE=0
USE_SYSTEM_CMAKE=0

select_dependency USE_SYSTEM_CMAKE cmake cmake 3.13
select_dependency USE_SYSTEM_GEOS geos geos-devel "${MIN_VERSION[geos]}"
select_dependency USE_SYSTEM_PROJ proj proj-devel "${MIN_VERSION[proj]}"
select_dependency USE_SYSTEM_GDAL gdal gdal-devel "${MIN_VERSION[gdal]}"
select_dependency USE_SYSTEM_SFCGAL sfcgal SFCGAL-devel "${MIN_VERSION[sfcgal]}"
select_dependency USE_SYSTEM_PROTOBUF_C protobuf-c protobuf-c-devel "${MIN_VERSION[protobuf-c]}"
select_dependency USE_SYSTEM_PCRE pcre pcre-devel 8.0

if ((USE_SYSTEM_CMAKE == 0)); then
    log "Building CMake"
    extract "${ARCHIVES[cmake]}"
    pushd "$WORK_DIR/CMake-3.30.2" >/dev/null
    ./bootstrap --prefix="$INSTALL_PREFIX" --parallel="$JOBS" -- -DBUILD_TESTING=OFF
    make_install
    popd >/dev/null
fi

if ((USE_SYSTEM_GEOS == 0)); then
    log "Building GEOS"
    extract "${ARCHIVES[geos]}"
    cmake -S "$WORK_DIR/geos-3.9.5" -B "$WORK_DIR/geos-3.9.5/build" \
        -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
    cmake --build "$WORK_DIR/geos-3.9.5/build" --parallel "$JOBS"
    cmake --install "$WORK_DIR/geos-3.9.5/build"
fi

if ((USE_SYSTEM_PROJ == 0)); then
    log "Building SQLite (required by bundled PROJ)"
    extract "${ARCHIVES[sqlite]}"
    pushd "$WORK_DIR/sqlite-autoconf-3460100" >/dev/null
    ./configure --prefix="$SQLITE_PREFIX"
    make_install
    popd >/dev/null
fi

if ((USE_SYSTEM_PROJ == 0)); then
    log "Building PROJ"
    extract "${ARCHIVES[proj]}"
    pushd "$WORK_DIR/proj-6.3.1" >/dev/null
    ./configure --prefix="$INSTALL_PREFIX"
    make_install
    popd >/dev/null
fi

if ((USE_SYSTEM_PROTOBUF_C == 0)); then
    log "Building protobuf"
    extract "${ARCHIVES[protobuf]}"
    pushd "$WORK_DIR/protobuf-3.15.3" >/dev/null
    ./configure --prefix="$INSTALL_PREFIX"
    make_install
    popd >/dev/null

    log "Building protobuf-c"
    extract "${ARCHIVES[protobuf-c]}"
    pushd "$WORK_DIR/protobuf-c-1.3.3" >/dev/null
    ./configure --prefix="$INSTALL_PREFIX"
    make_install
    popd >/dev/null
fi

if ((USE_SYSTEM_GDAL == 0)); then
    log "Building GDAL"
    extract "${ARCHIVES[gdal]}"
    pushd "$WORK_DIR/gdal-3.0.4" >/dev/null
    ./configure --prefix="$INSTALL_PREFIX"
    make_install
    popd >/dev/null
fi

if ((USE_SYSTEM_SFCGAL == 0)); then
    log "Building CGAL"
    extract "${ARCHIVES[cgal]}"
    cmake -S "$WORK_DIR/CGAL-4.14.3" -B "$WORK_DIR/CGAL-4.14.3/build" \
        -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
    cmake --build "$WORK_DIR/CGAL-4.14.3/build" --parallel "$JOBS"
    cmake --install "$WORK_DIR/CGAL-4.14.3/build"

    log "Building SFCGAL"
    extract "${ARCHIVES[sfcgal]}"
    cmake -S "$WORK_DIR/SFCGAL-1.3.7" -B "$WORK_DIR/SFCGAL-1.3.7/build" \
        -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
    cmake --build "$WORK_DIR/SFCGAL-1.3.7/build" --parallel "$JOBS"
    cmake --install "$WORK_DIR/SFCGAL-1.3.7/build"
fi

if ((USE_SYSTEM_PCRE == 0)); then
    log "Building PCRE"
    extract "${ARCHIVES[pcre]}"
    pushd "$WORK_DIR/pcre-8.45" >/dev/null
    ./configure --prefix="$INSTALL_PREFIX"
    make_install
    popd >/dev/null
fi

POSTGIS_CONTROL="$PG_SHAREDIR/extension/postgis.control"
POSTGIS_INSTALLED_VERSION=""
if [[ -f "$PG_PKGLIBDIR/postgis-3.so" && -r "$POSTGIS_CONTROL" ]]; then
    POSTGIS_INSTALLED_VERSION="$(
        awk -F"'" '/^[[:space:]]*default_version[[:space:]]*=/{print $2; exit}' "$POSTGIS_CONTROL"
    )"
fi
if [[ -n "$POSTGIS_INSTALLED_VERSION" ]] && version_ge "$POSTGIS_INSTALLED_VERSION" 3.4.2; then
    log "Already installed: PostGIS ${POSTGIS_INSTALLED_VERSION}; skipping source build"
else
    log "Building PostGIS for the existing PostgreSQL installation"
    extract "${ARCHIVES[postgis]}"
    pushd "$WORK_DIR/postgis-3.4.2" >/dev/null
    ./configure --with-pgconfig="$PG_CONFIG" --without-raster
    make_install
    popd >/dev/null
fi

cat > /etc/ld.so.conf.d/postgis-local.conf <<EOF
$INSTALL_PREFIX/lib
$INSTALL_PREFIX/lib64
$SQLITE_PREFIX/lib
EOF
ldconfig
chown -R "$PG_USER":"$(id -gn "$PG_USER")" "$PG_PKGLIBDIR" "$PG_SHAREDIR/extension"

pg_env=(env "PATH=$PG_BINDIR:$PATH")
for key in PGHOME PGDATA PGPORT PGDATABASE PGUSER PGHOST; do
    [[ -n "${!key:-}" ]] && pg_env+=("$key=${!key}")
done

is_patroni_leader() {
    sudo -iu "$PG_USER" "${pg_env[@]}" "$PG_BINDIR/psql" \
        -XAtq -d "${PGDATABASE:-postgres}" \
        -c 'select not pg_is_in_recovery()' 2>/dev/null | grep -qx t
}

case "$CREATE_EXTENSION" in
    always) create_now=1 ;;
    never) create_now=0 ;;
    auto)
        if is_patroni_leader; then create_now=1; else create_now=0; fi
        ;;
    *) die "CREATE_EXTENSION must be auto, always or never" ;;
esac

if ((create_now)); then
    log "Creating/updating postgis extension in ${PGDATABASE:-postgres}"
    sudo -iu "$PG_USER" "${pg_env[@]}" \
        "$PG_BINDIR/psql" -v ON_ERROR_STOP=1 -d "${PGDATABASE:-postgres}" \
        -c 'CREATE EXTENSION IF NOT EXISTS postgis;' \
        -c 'ALTER EXTENSION postgis UPDATE;'
else
    log "Extension SQL skipped on this replica; it is replicated from the Patroni leader"
fi

log "PostGIS installation completed: $("$PG_BINDIR/postgres" --version)"
