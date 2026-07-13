{
  description = "k8s-library";

  inputs = {
    k8sapi = {
      # 00236ae0d73d2455a2470469ed1005674f8ed61f is a random commit from the top of the kubernetes master branch
      # just to have things pinned down and not change all the time
      url = "https://raw.githubusercontent.com/kubernetes/kubernetes/810e9e212ec5372d16b655f57b9231d8654a2179/api/openapi-spec/swagger.json";
      flake = false;
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, k8sapi, nixpkgs, ... }@attrs:
  let
    pname = "k8s-library";
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
      overlays = [
        self.overlays.default
      ];
    };

    cephCSI = {
      repoName = "ceph-csi";
      repoUrl = "https://ceph.github.io/csi-charts";
      chartVersion = "3.13.1";
    };
    kubevipVersion = "0.8.9";
  in
  {
    inherit (pkgs) manifests lib kubevip-binary;

    nixosModules.swag = import ./swag.nix;

    overlays.default = final: prev: {
      fetchHelm = final.callPackage ./fetchers/helm {};
      inherit k8sapi;
      kubevip-binary = final.callPackage ./pkgs/kubevip/package.nix { version = kubevipVersion; };
      manifests = {
        argocd = final.callPackage ./pkgs/argocd {};
        ceph-csi-cephfs = final.callPackage ./builders/helm rec{
          deployName = helm.chartName;
          deployNamespace = helm.chartName;
          helm = {
            chartName = "ceph-csi-cephfs";
            chartHash = "sha256-f99qjSfB3InPWDgwSLYrerBzd9UIcOY+EBYg6ZS5TYs=";
            inherit (cephCSI) repoName repoUrl chartVersion;
          };
          kubernetes-version = "1.32.0";
        };
        ceph-csi-rbd = final.callPackage ./builders/helm rec{
          deployName = helm.chartName;
          deployNamespace = helm.chartName;
          helm = {
            chartName = "ceph-csi-rbd";
            chartHash = "sha256-YGwuOpeUoH2ESxqtnV2q638IefXkcaBHf+rwp6QrjtQ=";
            inherit (cephCSI) repoName repoUrl chartVersion;
          };
          kubernetes-version = "1.32.0";
        };
        csi-secrets-store-provider-azure = final.callPackage ./builders/helm rec{
          deployName = helm.chartName;
          deployNamespace = helm.chartName;
          helm = {
            repoName = "csi-secrets-store-provider-azure";
            repoUrl = "https://azure.github.io/secrets-store-csi-driver-provider-azure/charts";
            chartName = "csi-secrets-store-provider-azure";
            chartVersion = "1.6.1";
            chartHash = "sha256-r4qM94mXQFzZoTCyLkN7N4FYkwLWr7hVBLvLRR2A6i8=";
          };
          kubernetes-version = "1.31.0";
        };
        external-secrets = final.callPackage ./builders/helm rec{
          deployName = helm.chartName;
          deployNamespace = helm.chartName;
          helm = {
            repoName = "external-secrets";
            repoUrl = "https://charts.external-secrets.io";
            chartName = "external-secrets";
            chartVersion = "0.13.0";
            chartHash = "sha256-fI3Y3Eo5ya6o5KG4odbmAIFwSGj7yKhDojm7GvkXNks=";
          };
          kubernetes-version = "1.31.0";
        };
        kube-prometheus-stack = final.callPackage ./builders/helm rec{
          deployName = helm.chartName;
          deployNamespace = helm.chartName;
          helm = {
            repoName = "prometheus-community";
            repoUrl = "https://prometheus-community.github.io/helm-charts";
            chartName = "kube-prometheus-stack";
            chartVersion = "70.3.0";
            chartHash = "sha256-HeJB3Bw7LhrW4tMZ/J5mS00CVwkdjE6hXwCf10zSElE=";
          };
          kubernetes-version = "1.31.0";
        };
        kubevip = final.callPackage ./pkgs/kubevip { version = kubevipVersion; };
        port-k8s-exporter = final.callPackage ./builders/helm rec{
          deployName = helm.chartName;
          deployNamespace = helm.chartName;
          helm = {
            repoName = "port-k8s-exporter";
            repoUrl = "https://port-labs.github.io/helm-charts";
            chartName = "port-k8s-exporter";
            chartVersion = "0.2.38";
            chartHash = "sha256-kqZRhQcdk7IEWA7CCFHzfhh1Kp9IVMInoJz3GFwPYPQ=";
          };
          values.secret = {
            secrets = {
              portClientId = "dummy";
              portClientSecret = "dummy";
            };
          };
          kubernetes-version = "1.31.0";
        };
        rancher = final.callPackage ./builders/helm rec{
          deployName = helm.chartName;
          deployNamespace = "cattle-system";
          helm = {
            repoName = "rancher-latest";
            repoUrl = "https://releases.rancher.com/server-charts/latest";
            chartName = "rancher";
            chartVersion = "2.11.2";
            chartHash = "sha256-H5tcxl+sk5ClLDeyiX+xbek0VhWX2ie5OBbiWy962WY=";
          };
          kubernetes-version = "1.31.0";
        };
      };
    };

    devShells.${system}.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        (php.withExtensions ({ enabled, all }:
          enabled ++ [ all.yaml ]))
      ];
    };
  };
}
