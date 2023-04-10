{ stdenv
, lib
, fetchurl
, fetchFromGitHub
, fetchpatch
, bison
, dtc
, flex
, libusb1
, lzop
, openssl
, lz4
, pkg-config
, armTrustedFirmwareRK3399
, buildPackages
}:

let
  defaultVersion = "2023.03.0";
  defaultSrc = fetchurl {
    url = "https://www.barebox.org/download/barebox-${defaultVersion}.tar.bz2";
    sha256 = "sha256-0PeKabokAyckfI/Q4dRSh+Sg3/me2EfpppbMLaDPOIw=";
  };

  localSrc = fetchGit {
    url = "/src/barebox";
    ref = "rk3399-nexter";
  };

  masterSrc = fetchGit {
    url = "https://git.pengutronix.de/git/barebox";
    ref = "master";
  };

  nextSrc = fetchGit {
    url = "https://git.pengutronix.de/git/barebox";
    ref = "next";
    shallow = true;
  };

  defaultTarget = if stdenv.hostPlatform != stdenv.buildPlatform then
                  stdenv.cc.targetPrefix else "";

  buildBarebox = {
    version ? "local"
  , src ? "local"
  , extraFilesToInstall ? null
  , installDir ? "$out"
  , arch ? "${stdenv.hostPlatform.linuxArch}"
  , target ? defaultTarget
  , defconfig
  , extraConfig ? ""
  , extraPatches ? []
  , extraMakeFlags ? []
  , extraMeta ? {}
  , ... } @ args: stdenv.mkDerivation ({
    pname = "barebox-${defconfig}";

    version = if src == null then defaultVersion else version;

    src = if src == null then defaultSrc else if src == "master"
          then masterSrc else if src == "next" then nextSrc else
          if src == "local" then localSrc else src;

    patches = [
    ] ++ extraPatches;

    postPatch = ''
      patchShebangs scripts
    '';

    nativeBuildInputs = [
      bison
      flex
      libusb1
      lzop
      lz4
      pkg-config
    ];
    buildInputs = [
      libusb1
    ];
    depsBuildBuild = [ buildPackages.stdenv.cc openssl pkg-config ];

    hardeningDisable = [ "all" ];

    makeFlags = [
      "KBUILD_BUILD_USER=nix-user"
      "KBUILD_BUILD_HOST=nix-host"
      "KBUILD_BUILD_VERSION=1-NixOS"
      "ARCH=${arch}"
      "CROSS_COMPILE=${target}"
    ] ++ extraMakeFlags;

    passAsFile = [ "extraConfig" ];

    configurePhase = ''
      runHook preConfigure

      buildFlagsArray+=("KBUILD_BUILD_TIMESTAMP=$(date -u -d @$SOURCE_DATE_EPOCH)")

      make ${defconfig} ARCH=${arch} CROSS_COMPILE=${target} CROSS_PKG_CONFIG=$PKG_CONFIG

      cat $extraConfigPath >> .config

      runHook postConfigure
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p ${installDir}

      for artifact in .config $(cat barebox-flash-images) \
                      ${lib.concatStringsSep " " extraFilesToInstall}; do
        cp $artifact ${installDir}/
      done


      runHook postInstall
    '';

    enableParallelBuilding = true;

    dontStrip = true;

    meta = with lib; {
      homepage = "https://www.barebox.org";
      description = "The Swiss Army Knife for bare metal";
      license = licenses.gpl2;
      maintainers = with maintainers; [ emantor ];
    } // extraMeta;
  } // removeAttrs args [ "extraMeta" ]);

in {
  inherit buildBarebox;

  bareboxTools = buildBarebox {
    defconfig = "hosttools_defconfig";
    installDir = "$out/bin";
    hardeningDisable = [];
    dontStrip = false;
    extraMeta.platforms = lib.platforms.linux;
    arch = "sandbox";
    extraMakeFlags = [ "scripts" ];
    extraFilesToInstall = [
      "scripts/bareboxenv"
      "scripts/bareboxcrc32"
      "scripts/kernel-install"
      "scripts/bareboximd"
      "scripts/imx/imx-usb-loader"
      "scripts/omap4_usbboot"
      "scripts/omap3-usb-loader"
      "scripts/kwboot"
      "scripts/rk-usb-loader"
    ];
  };

  bareboxRockchip = buildBarebox rec {
    rkbin = fetchFromGitHub {
      owner = "rockchip-linux";
      repo = "rkbin";
      rev = "b0c100f1a260d807df450019774993c761beb79d";
      sha256 = "sha256-V7RcQj3BgB2q6Lgw5RfcPlOTZF8dbC9beZBUsTvaky0=";
    };

    defconfig = "rockchip_v8_defconfig";

    extraMeta = {
      platforms = ["aarch64-linux"];
      license = lib.licenses.unfreeRedistributableFirmware;
    };
    preBuild = ''
      boards=arch/arm/boards
      rk33=${rkbin}/bin/rk33
      rk35=${rkbin}/bin/rk35

      ln -fs $rk33/rk3399pro_ddr_800MHz_v1.27.bin $boards/radxa-rock-pi/sdram-init.bin
      ln -fs $rk33/rk3399_ddr_800MHz_v1.27.bin    $boards/pine64-rockpro64/sdram-init.bin

      ln -fs $rk35/rk3566_ddr_1056MHz_v1.13.bin   $boards/radxa-cm3/sdram-init.bin
      ln -fs $rk35/rk3566_ddr_1056MHz_v1.13.bin   $boards/pine64-quartz64/sdram-init.bin
      ln -fs $rk35/rk3568_ddr_1560MHz_v1.13.bin   $boards/radxa-rock3/sdram-init.bin
      ln -fs $rk35/rk3568_ddr_1560MHz_v1.13.bin   $boards/rockchip-rk3568-evb/sdram-init.bin
      ln -fs $rk35/rk3568_ddr_1560MHz_v1.13.bin   $boards/rockchip-rk3568-bpi-r2pro/sdram-init.bin

      ln -fs ${armTrustedFirmwareRK3399}/bl31.elf firmware/rk3399-bl31.bin
      ln -fs $rk35/rk3568_bl31_v1.34.elf          firmware/rk3568-bl31.bin
      ln -fs $rk35/rk3568_bl32_v2.08.bin          firmware/rk3568-op-tee.bin
    '';
  };

  bareboxIMXv7 = buildBarebox {
    defconfig = "imx_v7_defconfig";
    extraMeta.platforms = ["armv7l-linux"];
  };

  bareboxQemuAarch64 = buildBarebox {
    defconfig = "qemu_virt64_defconfig";
    extraMeta.platforms = ["aarch64-linux"];
  };

  bareboxQemuArm = buildBarebox {
    defconfig = "vexpress_defconfig";
    extraMeta.platforms = ["armv7l-linux"];
  };

  bareboxRiscv64 = buildBarebox {
    defconfig = "rv64i_defconfig";
    extraMeta.platforms = ["riscv64-linux"];
  };

  bareboxQemuRiscv32 = buildBarebox {
    defconfig = "virt32_defconfig";
    extraMeta.platforms = ["riscv32-linux" "riscv64-linux"];
  };

  bareboxQemuX86 = buildBarebox {
    defconfig = "efi_defconfig";
    extraMeta.platforms = [ "x86_64-linux" ];
  };

  bareboxRaspberryPi_32bit = buildBarebox {
    defconfig = "rpi_defconfig";
    extraMeta.platforms = ["armv7l-linux"];
    extraFilesToInstall = ["arch/arm/dts/*.dtb"];
  };

  bareboxRaspberryPi_64bit = buildBarebox {
    defconfig = "rpi_v8a_defconfig";
    extraMeta.platforms = ["aarch64-linux"];
    extraFilesToInstall = ["arch/arm/dts/*.dtb"];
  };
}
