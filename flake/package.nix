{
  lib,
  stdenv,
  rustPlatform,
  fetchurl,
  makeDesktopItem,
  clang,
  copyDesktopItems,
  patchelf,
  pkg-config,
  qt6,
  alsa-lib,
  bash,
  ffmpeg_7,
  mdk-sdk,
  ocl-icd,
  opencv,
  versionCheckHook,
}:
let
  lens-profiles-version = "v41";

  lens-profiles-db = fetchurl {
    url = "https://github.com/gyroflow/lens_profiles/releases/download/${lens-profiles-version}/profiles.cbor.gz";
    hash = "sha256-W5E2aXt13fnNogll8X54a2yFMOPVkQn4dQUGlgLn9nY=";
  };

  # Blackmagic RAW SDK, pre-installed so the user never sees the
  # "install BRAW plugin" download prompt. Extracted into the package's
  # lib/ dir at build time (see postInstall).
  braw-sdk = fetchurl {
    url = "https://api.gyroflow.xyz/sdk/Blackmagic_RAW_SDK_Linux_5.0.0.tar.gz";
    hash = "sha256-um38/Dl1qejuNFRoLvVvcuwIG6nH/EhjfIxDqALwRjc=";
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "gyroflow";
  version = "1.6.3";

  src = ./..;

  cargoHash = "sha256-DZnHqE/kphQNeMZsK04cir00+sanS4nzwJtRlqwuHo4=";

  __structuredAttrs = true;
  strictDeps = true;

  nativeBuildInputs = [
    clang
    pkg-config
    rustPlatform.bindgenHook
    qt6.wrapQtAppsHook
    copyDesktopItems
    patchelf
  ];

  buildInputs = [
    bash
    ffmpeg_7
    mdk-sdk
    opencv
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtsvg
    alsa-lib
    ocl-icd
  ];

  postPatch = ''
    install -Dm644 ${lens-profiles-db} resources/camera_presets/profiles.cbor.gz

    substituteInPlace build.rs \
      --replace-fail 'println!("cargo:rustc-link-lib=static:+whole-archive=z")' ""

    # Breaks reproducibility with build time embedded in the binary
    substituteInPlace build.rs \
      --replace-fail 'println!("cargo:rustc-env=BUILD_TIME={}", (time.as_secs() - 1642516578) / 600);' ""
  '';

  # qml-video-rs and gyroflow assume that all Qt headers are installed
  # in a single (qtbase) directory.  Apart from QtCore and QtGui from
  # qtbase they need QtQuick and QtQml public and private headers from
  # qtdeclarative:
  # https://github.com/AdrianEddy/qml-video-rs/blob/bbf60090b966f0df2dd016e01da2ea78666ecea2/build.rs#L22-L40
  # https://github.com/gyroflow/gyroflow/blob/v1.5.4/build.rs#L163-L186
  # Additionally gyroflow needs QtQuickControls2:
  # https://github.com/gyroflow/gyroflow/blob/v1.5.4/build.rs#L173
  env.NIX_CFLAGS_COMPILE = toString [
    "-I${qt6.qtdeclarative}/include/QtQuick"
    "-I${qt6.qtdeclarative}/include/QtQuick/${qt6.qtdeclarative.version}"
    "-I${qt6.qtdeclarative}/include/QtQuick/${qt6.qtdeclarative.version}/QtQuick"
    "-I${qt6.qtdeclarative}/include/QtQml"
    "-I${qt6.qtdeclarative}/include/QtQml/${qt6.qtdeclarative.version}"
    "-I${qt6.qtdeclarative}/include/QtQml/${qt6.qtdeclarative.version}/QtQml"
    "-I${qt6.qtdeclarative}/include/QtQuickControls2"
  ];

  # FFMPEG_DIR is used by ffmpeg-sys-next/build.rs and
  # gyroflow/build.rs.  ffmpeg-sys-next fails to build if this dir
  # does not contain ffmpeg *headers*.  gyroflow assumes that it
  # contains ffmpeg *libraries*, but builds fine as long as it is set
  # with any value.
  env.FFMPEG_DIR = ffmpeg_7.dev;

  # These variables are needed by gyroflow/build.rs.
  # OPENCV_LINK_LIBS is based on the value in gyroflow/_scripts/common.just, with opencv_dnn added to fix linking.
  env.OPENCV_LINK_PATHS = "${opencv}/lib";
  env.OPENCV_LINK_LIBS = "opencv_core,opencv_calib3d,opencv_dnn,opencv_features2d,opencv_imgproc,opencv_video,opencv_flann,opencv_imgcodecs,opencv_objdetect,opencv_stitching,png";

  # For qml-video-rs. It concatenates "lib/" to this value so it needs a trailing "/":
  env.MDK_SDK = "${mdk-sdk}/";

  doCheck = false; # No tests.

  # mdk-sdk license key is hardcoded to 'gyroflow' process name, wrapQt changes it,
  # which breaks the license check and throws a QR code
  dontWrapQtApps = true;

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  postInstall = ''
    mkdir -p $out/opt/Gyroflow
    cp -r resources $out/opt/Gyroflow/

    rm -rf $out/lib
    patchelf $out/bin/gyroflow --add-rpath ${mdk-sdk}/lib

    mv $out/bin/gyroflow $out/opt/Gyroflow/

    install -D ${./gyroflow-open.sh} $out/bin/gyroflow-open
    install -Dm644 ${./gyroflow-mime.xml} $out/share/mime/packages/gyroflow.xml
    install -Dm644 resources/icon.svg $out/share/icons/hicolor/scalable/apps/gyroflow.svg

    # Pre-install the Blackmagic RAW SDK so BRAW files decode without the
    # user having to trigger the in-app download. SDK_PATH is <exe dir>/lib/.
    mkdir -p $out/opt/Gyroflow/lib
    tar -xzf ${braw-sdk} -C $out/opt/Gyroflow/lib
    # The SDK tarball ships a stray 0-byte braw.tar.gz; drop it.
    rm -f $out/opt/Gyroflow/lib/braw.tar.gz
  '';

  postFixup = ''
    # Point the mdk-braw plugin at the pre-installed Blackmagic RAW SDK so
    # BRAW files decode without the in-app download. The plugin dlopens
    # libBlackmagicRawAPI.so from $BRAWSDK_DIR.
    makeQtWrapper $out/opt/Gyroflow/gyroflow $out/bin/gyroflow \
      --set BRAWSDK_DIR $out/opt/Gyroflow/lib
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "gyroflow";
      desktopName = "Gyroflow";
      genericName = "Video stabilization using gyroscope data";
      comment = finalAttrs.meta.description;
      icon = "gyroflow";
      exec = "gyroflow-open %u";
      terminal = false;
      mimeTypes = [ "application/x-gyroflow" ];
      categories = [
        "AudioVideo"
        "Video"
        "AudioVideoEditing"
        "Qt"
      ];
      startupNotify = true;
      startupWMClass = "gyroflow";
      prefersNonDefaultGPU = true;
    })
  ];

  meta = {
    description = "Advanced gyro-based video stabilization tool";
    homepage = "https://gyroflow.xyz";
    mainProgram = "gyroflow";
    license = with lib.licenses; [
      gpl3Plus
      cc0
    ];
    maintainers = with lib.maintainers; [ ];
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
})
