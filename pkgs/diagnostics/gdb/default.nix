# pkgs/diagnostics/gdb/default.nix
# GNU Debugger (GDB) & gdbserver for Android 14+ (Bionic libc).

{
  stdenv,
  fetchurl,
  lib,
  buildPackages,
  python3,
  expat,
  gmp,
  mpfr,
  ncurses,
  readline,
  zlib,
  zstd,
  pythonSupport ? true,
}:

let
  solibSearchPath =
    if stdenv.hostPlatform.is64bit then
      "/system/lib64:/system/vendor/lib64"
    else
      "/system/lib:/system/vendor/lib";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "gdb";
  version = "17.2";

  src = fetchurl {
    url = "mirror://gnu/gdb/gdb-${finalAttrs.version}.tar.xz";
    hash = "sha256-HANsDXLks9H7XJTIhjKt1vnXb018TS6nk8EqnxmjIow=";
  };

  buildInputs =
    [
      expat
      gmp
      mpfr
      ncurses
      readline
      zlib
      zstd
    ]
    ++ lib.optionals pythonSupport [ python3 ];

  env.NIX_CFLAGS_COMPILE = "-Wno-format-nonliteral -Wno-unused-function -D__USE_FORTIFY_LEVEL=0";

  configureFlags = [
    "--disable-werror"
    "--enable-64-bit-bfd"
    "--disable-install-libbfd"
    "--enable-tui"
    "--with-curses"
    "--disable-shared"
    "--enable-static"
    "--with-system-readline"
    "--with-system-zlib"
    "--with-zstd"
    "--with-expat"
    "--with-libexpat-prefix=${expat.dev}"
    "--with-gmp=${gmp.dev}"
    "--with-mpfr=${mpfr.dev}"
    "--without-guile"
    "--disable-sim"
    "--without-debuginfod"
    "--disable-nls"
    "--disable-inprocess-agent"
    "ac_cv_func_getpwent=no"
    "ac_cv_func_getpwnam=no"
    "gl_cv_func_gettimeofday_clobber=no"
    "gl_cv_func_gettimeofday_posix_signature=yes"
    "gl_cv_func_realpath_works=yes"
    "gl_cv_func_lstat_dereferences_slashed_symlink=yes"
    "gl_cv_func_memchr_works=yes"
    "gl_cv_func_stat_file_slash=yes"
    "gl_cv_func_frexp_no_libm=no"
    "gl_cv_func_strerror_0_works=yes"
    "gl_cv_func_working_strerror=yes"
    "gl_cv_func_getcwd_path_max=yes"
  ];

  postPatch = ''
    substituteInPlace gdbsupport/eintr.h \
      --replace-fail 'return gdb::handle_eintr (-1, ::open, pathname, flags);' \
                     'int ret; do { errno = 0; ret = ::open(pathname, flags); } while (ret == -1 && errno == EINTR); return ret;'

    substituteInPlace gdbsupport/pathstuff.cc \
      --replace-fail 'return "/tmp";' 'return "/data/local/tmp";' \
      --replace-fail 'ret = "/bin/sh";' 'ret = "/system/bin/sh";'

    substituteInPlace gdb/compile/compile.c \
      --replace-fail '#define TMP_PREFIX "/tmp/gdbobj-"' '#define TMP_PREFIX "/data/local/tmp/gdbobj-"'

    substituteInPlace gdbsupport/signals-state-save-restore.cc \
      --replace-fail 'if (found_preinstalled)' 'if (!defined_android && found_preinstalled)' \
      --replace-fail 'bool found_preinstalled = false;' 'bool defined_android = true; bool found_preinstalled = false;'

    substituteInPlace gdbsupport/job-control.cc \
      --replace-fail 'retval = setpgid (getpid (), getpid ());' 'retval = setpgid (0, 0);'

    substituteInPlace gdb/nat/linux-btrace.c \
      --replace-fail '#include <signal.h>' $'#include <signal.h>\n#ifndef PAGE_SIZE\n#define PAGE_SIZE ((size_t) sysconf(_SC_PAGESIZE))\n#endif'

    substituteInPlace gdb/solib.c \
      --replace-fail 'add_alias_cmd ("solib-absolute-prefix", sysroot_cmds.set, class_support, 0,' $'#ifdef __ANDROID__\n  solib_search_path = "${solibSearchPath}";\n#endif\n  add_alias_cmd ("solib-absolute-prefix", sysroot_cmds.set, class_support, 0,'

    substituteInPlace gdbserver/configure \
      --replace-fail '  *-android*)' '  *-android-disabled-auxv-override*)'

    substituteInPlace gdb/amd64-linux-nat.c \
      --replace-fail 'gdb_assert (FS < ELF_NGREG);' '#ifndef __ANDROID__
  gdb_assert (FS < ELF_NGREG);' \
      --replace-fail 'gdb_assert (GS < ELF_NGREG);' 'gdb_assert (GS < ELF_NGREG);


#endif'
  '';

  preConfigure = ''
    # Localized host CC wrapper for build-time tools (e.g. bfd/doc/chew)
    # Host GCC fails if given Clang-specific Bionic flags (-nostdlibinc, -fno-emulated-tls).
    mkdir -p "$PWD/build-bin"
    cat > "$PWD/build-bin/build-cc" << 'BUILD_CC_EOF'
#!/bin/sh
NIX_CFLAGS_COMPILE="" NIX_LDFLAGS="" exec "${buildPackages.stdenv.cc}/bin/cc" "$@"
BUILD_CC_EOF
    chmod +x "$PWD/build-bin/build-cc"
    configureFlagsArray+=("CC_FOR_BUILD=$PWD/build-bin/build-cc")
    makeFlagsArray+=("CC_FOR_BUILD=$PWD/build-bin/build-cc")

    pyHelper="$PWD/python-config-cross.sh"
    cat > "$pyHelper" << 'PY_HELPER_EOF'
#!/bin/sh
case "$*" in
  *--includes*) echo "-I${python3}/include/python3.13" ;;
  *--ldflags*) echo "-L${python3}/lib -lpython3.13" ;;
  *--exec-prefix*) echo "${python3}" ;;
  *) exit 1 ;;
esac
PY_HELPER_EOF
    chmod +x "$pyHelper"
    ${lib.optionalString pythonSupport ''
      configureFlagsArray+=("--with-python=$pyHelper")
    ''}
  '';

  meta = {
    description = "GNU Debugger for Android Bionic targets";
    homepage = "https://www.gnu.org/software/gdb/";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    needsLibcxx = true;
  };
})
