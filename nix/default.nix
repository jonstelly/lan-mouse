{
  rustPlatform,
  lib,
  pkgs,
}: let
  cargoToml = builtins.fromTOML (builtins.readFile ../Cargo.toml);
  pname = cargoToml.package.name;
  version = cargoToml.package.version;
in
rustPlatform.buildRustPackage {
  pname = pname;
  version = version;

  nativeBuildInputs = with pkgs; [
    pkg-config
    cmake
    buildPackages.gtk4
  ];

  buildInputs = with pkgs; [
    xorg.libX11
    gtk4
    libadwaita
    xorg.libXtst
  ] ++ lib.optionals stdenv.isDarwin [
    darwin.apple_sdk_11_0.frameworks.CoreGraphics
  ];

  src = builtins.path {
    name = pname;
    path = lib.cleanSource ../.;
  };

  cargoLock.lockFile = ../Cargo.lock;

  # Set Environment Variables
  RUST_BACKTRACE = "full";

  meta = with lib; {
    description = "Lan Mouse is a mouse and keyboard sharing software";
    longDescription = ''
      Lan Mouse is a mouse and keyboard sharing software similar to universal-control on Apple devices. It allows for using multiple pcs with a single set of mouse and keyboard. This is also known as a Software KVM switch.
      The primary target is Wayland on Linux but Windows and MacOS and Linux on Xorg have partial support as well (see below for more details).
    '';
    mainProgram = pname;
    platforms = platforms.all;
  };
}
