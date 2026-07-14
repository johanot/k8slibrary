{
  stdenv,
  fetchFromGitHub,
  php,
  kubernetes-helm,
  yq-go,
  k8sapi,
  writeText,
  deployName ? "argocd",
  deployNamespace ? "argocd",
  kubernetes-version ? "1.28.0",
  values ? {}
}:

let
  yamlPHP = 
    php.withExtensions ({ enabled, all }:
      enabled ++ [ all.yaml ]);
in
stdenv.mkDerivation rec{
  pname = "argocd";
  version = "2.14.3";

  src = fetchFromGitHub {
    owner = "argoproj";
    repo = "argo-cd";
    rev = "v${version}";
    hash = "sha256-PyE47KgdHo1LTTfH/D0t8wnyM4qJKWKM+DAowo26WHo=";
  };

  nativeBuildInputs = [ yq-go ];

  buildPhase = ''
    mkdir templated
    mkdir crds
    cp manifests/ha/namespace-install.yaml templated
    cp manifests/crds/*.yaml templated
    cp manifests/crds/*.yaml crds
    rm templated/kustomization.yaml
    cp ${./namespace.yaml} templated/namespace.yaml
    cp ${./application.yaml} templated/application.yaml
    yq -o json -s '.kind + "_" + .metadata.name + ".json"' templated/*.yaml
    cp *.json templated

    ${yamlPHP}/bin/php ${../../swag.php} ${deployName} templated/ ${k8sapi} crds/ > enriched.json 2>>debug.log
  '';

  installPhase = ''
    mkdir -p $out
    cp debug.log $out
    cp -r templated $out
    cp enriched.json $out
  '';
}
