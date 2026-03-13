{
  description = "Send Watchtower EPUB to Kindle via email";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        haskellPkg = pkgs.haskellPackages.developPackage {
          root = ./.;
          modifier = drv:
            pkgs.haskell.lib.addBuildTools drv (with pkgs.haskellPackages; [
              cabal-install
              ghcid
            ]);
        };

        exe = pkgs.haskell.lib.justStaticExecutables haskellPkg;
      in
      {
        packages.default = exe;

        apps.default = {
          type = "app";
          program = "${exe}/bin/send-wt-to-kindle";
        };

        devShells.default = haskellPkg.env.overrideAttrs (old: {
          buildInputs = old.buildInputs ++ (with pkgs.haskellPackages; [
            cabal-install
            ghcid
            haskell-language-server
          ]);
        });
      });
}
