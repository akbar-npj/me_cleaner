#!/usr/bin/env bash
#
# build.sh - Build and test automation script for me_cleaner
# Automates source archiving, RPM compilation, and artifact verification.
# Always selects the latest package by timestamp when older packages exist.
#

set -euo pipefail

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

info() {
    echo -e "${BLUE}${BOLD}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}${BOLD}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}${BOLD}[ERROR]${NC} $*" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_FILE="${SCRIPT_DIR}/me_cleaner.spec"
RPMBUILD_DIR="${HOME}/rpmbuild"

# Flags
DO_RPM=true
DO_WHEEL=false
DO_TEST=true
DO_CLEAN=false
DO_INSTALL=false
OUTPUT_DIR=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Automate compilation, packaging, and testing of me_cleaner.
If previous builds exist, the newest packages are automatically selected by timestamp.

Options:
  -r, --rpm              Build RPM package (default: true)
      --no-rpm          Skip RPM package compilation
  -w, --wheel            Build Python wheel package (default: false)
  -t, --test             Run verification tests on built artifacts (default: true)
      --no-test          Skip artifact verification tests
  -o, --output-dir DIR   Copy built package artifacts to specified directory
  -i, --install          Install the built RPM package on local system (requires sudo)
  -c, --clean            Clean build directories and temporary files
  -h, --help             Show this help message and exit

Examples:
  ./build.sh                               # Build RPM and run tests (standard)
  ./build.sh --wheel                       # Build RPM and Python wheel
  ./build.sh -o ./dist                     # Build RPM and copy to ./dist
  ./build.sh -o ./dist --wheel             # Build RPM & wheel, copy to ./dist
  ./build.sh --clean                       # Clean local build directories
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--rpm)
            DO_RPM=true
            shift
            ;;
        --no-rpm)
            DO_RPM=false
            shift
            ;;
        -w|--wheel)
            DO_WHEEL=true
            shift
            ;;
        -t|--test)
            DO_TEST=true
            shift
            ;;
        --no-test)
            DO_TEST=false
            shift
            ;;
        -o|--output-dir)
            if [[ -z "${2:-}" ]] || [[ "${2:-}" == -* ]]; then
                error "Option $1 requires a directory argument"
                exit 1
            fi
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -i|--install)
            DO_INSTALL=true
            shift
            ;;
        -c|--clean)
            DO_CLEAN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Perform clean if requested
if [ "${DO_CLEAN}" = true ]; then
    info "Cleaning build artifacts in repository..."
    rm -rf "${SCRIPT_DIR}/build" "${SCRIPT_DIR}/dist" "${SCRIPT_DIR}"/*.egg-info "${SCRIPT_DIR}"/.test_rpm_*
    success "Clean completed."
    exit 0
fi

# Ensure spec file exists
if [ ! -f "${SPEC_FILE}" ]; then
    error "Spec file not found at ${SPEC_FILE}"
    exit 1
fi

# Extract package metadata from spec file
PKG_NAME="$(sed -n 's/^Name:[[:space:]]*//p' "${SPEC_FILE}" | head -n1 | tr -d '[:space:]')"
PKG_VERSION="$(sed -n 's/^Version:[[:space:]]*//p' "${SPEC_FILE}" | head -n1 | tr -d '[:space:]')"

info "Package: ${BOLD}${PKG_NAME}${NC} (v${PKG_VERSION})"

# Check essential prerequisites
info "Checking build tools..."
MISSING_TOOLS=()
REQUIRED_TOOLS=("git" "python3")
if [ "${DO_RPM}" = true ]; then
    REQUIRED_TOOLS+=("rpmbuild" "tar" "rpm2cpio" "cpio")
fi

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        MISSING_TOOLS+=("${tool}")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    error "Missing required build tools: ${MISSING_TOOLS[*]}"
    error "Please install them via: sudo dnf install -y rpm-build rpmdevtools git tar python3"
    exit 1
fi

BUILT_RPM=""
BUILT_SRPM=""
WHEEL_FILE=""

# 1. Build RPM Package
if [ "${DO_RPM}" = true ]; then
    info "Preparing rpmbuild directories in ${RPMBUILD_DIR}..."
    mkdir -p "${RPMBUILD_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

    TARBALL_NAME="${PKG_NAME}-${PKG_VERSION}.tar.gz"
    TARBALL_PATH="${RPMBUILD_DIR}/SOURCES/${TARBALL_NAME}"

    info "Creating source archive: ${TARBALL_PATH}..."
    git -C "${SCRIPT_DIR}" archive --format=tar.gz --prefix="${PKG_NAME}-${PKG_VERSION}/" HEAD -o "${TARBALL_PATH}"

    info "Copying spec file to ${RPMBUILD_DIR}/SPECS/${PKG_NAME}.spec..."
    cp -p "${SPEC_FILE}" "${RPMBUILD_DIR}/SPECS/${PKG_NAME}.spec"

    info "Compiling RPM package with rpmbuild..."
    rpmbuild -ba "${RPMBUILD_DIR}/SPECS/${PKG_NAME}.spec"

    # Locate generated RPMs by newest timestamp if older builds exist
    BUILT_RPM="$(find "${RPMBUILD_DIR}/RPMS" -type f -name "${PKG_NAME}*.rpm" ! -name "*.src.rpm" -printf '%T@ %p\n' 2>/dev/null | sort -k1,1n | tail -n1 | cut -d' ' -f2-)"
    BUILT_SRPM="$(find "${RPMBUILD_DIR}/SRPMS" -type f -name "${PKG_NAME}*.src.rpm" -printf '%T@ %p\n' 2>/dev/null | sort -k1,1n | tail -n1 | cut -d' ' -f2-)"

    if [ -z "${BUILT_RPM}" ] || [ ! -f "${BUILT_RPM}" ]; then
        error "Failed to locate generated binary RPM!"
        exit 1
    fi

    RPM_MTIME="$(date -r "${BUILT_RPM}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")"
    success "Binary RPM selected (newest timestamp: ${RPM_MTIME}): ${BUILT_RPM}"
    if [ -n "${BUILT_SRPM}" ] && [ -f "${BUILT_SRPM}" ]; then
        SRPM_MTIME="$(date -r "${BUILT_SRPM}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")"
        success "Source RPM selected (newest timestamp: ${SRPM_MTIME}): ${BUILT_SRPM}"
    fi
fi

# 2. Build Python Wheel (if requested)
if [ "${DO_WHEEL}" = true ]; then
    info "Building Python wheel..."
    python3 -m pip wheel --no-deps --no-build-isolation -w "${SCRIPT_DIR}/dist" "${SCRIPT_DIR}"
    # Select wheel by newest timestamp
    WHEEL_FILE="$(find "${SCRIPT_DIR}/dist" -type f -name "${PKG_NAME}*.whl" -printf '%T@ %p\n' 2>/dev/null | sort -k1,1n | tail -n1 | cut -d' ' -f2-)"
    if [ -n "${WHEEL_FILE}" ] && [ -f "${WHEEL_FILE}" ]; then
        WHEEL_MTIME="$(date -r "${WHEEL_FILE}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")"
        success "Python wheel selected (newest timestamp: ${WHEEL_MTIME}): ${WHEEL_FILE}"
    fi
fi

# 3. Automated Testing and Verification
if [ "${DO_TEST}" = true ] && [ "${DO_RPM}" = true ] && [ -n "${BUILT_RPM}" ]; then
    info "Running automated verification tests on ${BUILT_RPM}..."

    # Check RPM header info
    rpm -qip "${BUILT_RPM}" >/dev/null
    info "RPM metadata queried successfully."

    # Verify file manifest
    RPM_FILES="$(rpm -qlp "${BUILT_RPM}")"
    for expected in "/usr/bin/me_cleaner" "/usr/bin/me_cleaner.py" "/usr/share/man/man1/me_cleaner.1.gz"; do
        if ! echo "${RPM_FILES}" | grep -q "${expected}"; then
            error "Expected file ${expected} is missing from RPM package!"
            exit 1
        fi
    done
    info "Package manifest contains all required binaries and documentation."

    # Extract RPM into isolated temp directory for execution testing
    TEST_TMPDIR="$(mktemp -d -p "${SCRIPT_DIR}" .test_rpm_XXXXXX)"
    trap 'rm -rf "${TEST_TMPDIR}"' EXIT INT TERM

    (
        cd "${TEST_TMPDIR}"
        rpm2cpio "${BUILT_RPM}" | cpio -idm --quiet
    )

    # Test me_cleaner binary execution
    CLI_BIN="${TEST_TMPDIR}/usr/bin/me_cleaner"
    CLI_PY_BIN="${TEST_TMPDIR}/usr/bin/me_cleaner.py"

    chmod +x "${CLI_BIN}" "${CLI_PY_BIN}"

    # Verify shebang
    SHEBANG="$(head -n1 "${CLI_PY_BIN}")"
    if [[ "${SHEBANG}" != *"python3"* ]]; then
        error "Invalid shebang in ${CLI_PY_BIN}: ${SHEBANG}"
        exit 1
    fi
    info "Shebang verified: ${SHEBANG}"

    # Test version output
    VERSION_OUT="$("${CLI_BIN}" --version 2>&1)"
    if [[ "${VERSION_OUT}" != *"${PKG_VERSION}"* ]]; then
        error "Unexpected version output from me_cleaner: ${VERSION_OUT} (expected ${PKG_VERSION})"
        exit 1
    fi
    info "Verified executable: '${CLI_BIN} --version' -> ${VERSION_OUT}"

    VERSION_PY_OUT="$("${CLI_PY_BIN}" --version 2>&1)"
    if [[ "${VERSION_PY_OUT}" != *"${PKG_VERSION}"* ]]; then
        error "Unexpected version output from me_cleaner.py: ${VERSION_PY_OUT}"
        exit 1
    fi
    info "Verified executable: '${CLI_PY_BIN} --version' -> ${VERSION_PY_OUT}"

    # Test help output
    "${CLI_BIN}" --help >/dev/null
    info "Verified help screen output (exit code 0)."

    # Verify error handling on missing input file
    if "${CLI_BIN}" /nonexistent/file.bin >/dev/null 2>&1; then
        error "me_cleaner unexpectedly succeeded on non-existent file!"
        exit 1
    fi
    info "Verified error handling on missing input file."

    # Clean up test tempdir
    rm -rf "${TEST_TMPDIR}"
    trap - EXIT INT TERM

    success "All automated verification tests passed!"
fi

# 4. Copy artifacts to output directory (if requested)
if [ -n "${OUTPUT_DIR}" ]; then
    info "Copying build artifacts to ${OUTPUT_DIR}..."
    mkdir -p "${OUTPUT_DIR}"
    TARGET_CANONICAL="$(cd "${OUTPUT_DIR}" && pwd)"

    if [ "${DO_RPM}" = true ] && [ -n "${BUILT_RPM}" ]; then
        if [ "$(cd "$(dirname "${BUILT_RPM}")" && pwd)" != "${TARGET_CANONICAL}" ]; then
            cp -p "${BUILT_RPM}" "${OUTPUT_DIR}/"
        fi
        if [ -n "${BUILT_SRPM}" ]; then
            if [ "$(cd "$(dirname "${BUILT_SRPM}")" && pwd)" != "${TARGET_CANONICAL}" ]; then
                cp -p "${BUILT_SRPM}" "${OUTPUT_DIR}/"
            fi
        fi
    fi
    if [ "${DO_WHEEL}" = true ] && [ -n "${WHEEL_FILE}" ]; then
        if [ "$(cd "$(dirname "${WHEEL_FILE}")" && pwd)" != "${TARGET_CANONICAL}" ]; then
            cp -p "${WHEEL_FILE}" "${OUTPUT_DIR}/"
        fi
    fi
    success "Artifacts exported to ${OUTPUT_DIR}"
fi

# 5. Install package (if requested)
if [ "${DO_INSTALL}" = true ]; then
    if [ "${DO_RPM}" != true ] || [ -z "${BUILT_RPM}" ]; then
        error "Cannot install: RPM was not built."
        exit 1
    fi
    info "Installing RPM package: ${BUILT_RPM}..."
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "${BUILT_RPM}"
    else
        sudo rpm -Uvh --replacepkgs "${BUILT_RPM}"
    fi
    success "Package installation completed."
fi

# Print final summary
echo ""
echo -e "${GREEN}${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD}               BUILD & TEST COMPLETE                  ${NC}"
echo -e "${GREEN}${BOLD}======================================================${NC}"
if [ "${DO_RPM}" = true ] && [ -n "${BUILT_RPM}" ]; then
    echo -e "${BOLD}Binary RPM:${NC}  ${BUILT_RPM}"
    if [ -n "${BUILT_SRPM}" ]; then
        echo -e "${BOLD}Source RPM:${NC}  ${BUILT_SRPM}"
    fi
fi
if [ "${DO_WHEEL}" = true ] && [ -n "${WHEEL_FILE}" ]; then
    echo -e "${BOLD}Wheel:${NC}       ${WHEEL_FILE}"
fi
if [ -n "${OUTPUT_DIR}" ]; then
    echo -e "${BOLD}Exported to:${NC} ${OUTPUT_DIR}"
fi
if [ "${DO_RPM}" = true ] && [ -n "${BUILT_RPM}" ]; then
    echo ""
    echo -e "${BOLD}To install on your system:${NC}"
    echo -e "  sudo dnf install ${BUILT_RPM}"
    echo ""
    echo -e "${BOLD}To verify installed binary:${NC}"
    echo -e "  me_cleaner --version"
    echo -e "  man me_cleaner"
fi
echo -e "${GREEN}${BOLD}======================================================${NC}"
