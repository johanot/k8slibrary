let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  flake = builtins.getFlake (toString ./.);
  output = p: _: (flake.lib.evalModules {
    modules = [
      flake.outputs.nixosModules.swag
      ({ config, ... }: {
        config.swag.apps.${p} = {
          filters.doc = config.swag.lib.filterOutAPIVersionKind "v1" "Namespace";
          package = flake.manifests.${p};
          patches =
            (config.swag.lib.addToleration {
              effect = "NoSchedule";
              key = "tier";
              operator = "Equal";
              value = "platform";
            })
            ++
            config.swag.lib.setNamespace "${p}"
            ++
            config.swag.lib.scale 1
            ++
            config.swag.lib.addConfigMapData "argocd-cm" ({ "server.insecure" = "true"; })
            ++
            config.swag.lib.removePodAntiAffinityRule "requiredDuringSchedulingIgnoredDuringExecution"
            ++
            config.swag.lib.addEnvironmentVariable "PATH" "/usr/local/bin:/usr/bin:/bin:/run/current-system/sw/bin"
            ++
            (config.swag.lib.addHostAliases [{
              ip = "10.0.0.1";
              hostnames = [
                "argocd.local"
                "argocd-server.local"
                "argocd-test.test.case"
                "argocd-test.test.case" # This should be deduplicated
              ];
            }
            {
              ip = "10.0.0.2";
              hostnames = [
                "second-alias.local"
              ];
            }]);
        };
      })
    ];
  }).config.swag.apps.${p}.output;

  build = n: o: pkgs.writeText "${n}.json" (builtins.toJSON (output n o));
in
  pkgs.runCommand "swag-test" {} ''
    mkdir -p $out
    ${lib.concatStringsSep "\n"
      (lib.mapAttrsToList (n: o: "ln -s ${build n o} $out/${n}.json")
      flake.outputs.manifests)}
  ''
