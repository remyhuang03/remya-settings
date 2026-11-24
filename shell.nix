{ pkgs ? import <nixpkgs> { } }:

import ../remya-core/nix/flutter-shell.nix {
  inherit pkgs;
  extraPackages = pkgs: with pkgs; [
    gst_all_1.gst-plugins-base
    gst_all_1.gstreamer
    libpulseaudio
    pipewire
    sqlite
  ];
}
