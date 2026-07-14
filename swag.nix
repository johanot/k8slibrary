{ config, lib, ... }:
let
  cfg = config.swag;

  render = ii:
  let
    i = if !builtins.isAttrs ii then throw "init object assertion: ${builtins.toJSON ii}" else ii;
    content = if (i.__content or null) == null then "undefined content: ${builtins.toJSON i}" else i.__content;
    typ = if (i.__type or null) == null then throw "undefined type: ${builtins.toJSON i}" else i.__type;
  in
    if typ == "object" then
      if content == {} then
        {}
      else if builtins.isAttrs content then
        lib.mapAttrs (_: v: render v) (lib.filterAttrs (n: _: n != "__type") content)
      else throw "object assertion: ${builtins.toJSON content}"
    else if typ == "array" then
      if builtins.isList content then
        lib.map render content
      else throw "array assertion: ${builtins.toJSON content}"
    else content;


  getMetadataName = queryAttrByPath ["metadata" "name"];

  queryAttrByPath = path: obj:
    let
      subject = render obj;
    in
      lib.attrByPath path null subject;

  mutate' =
    with builtins; apiType: f: s: (
    if isAttrs s && s ? __api_type && s.__api_type == apiType then f s
    else if isAttrs s && s ? __content then s // { __content = mutate' apiType f s.__content; }
    else if isAttrs s then lib.mapAttrs (_: v: mutate' apiType f v) s
    else if isList s then map (v: mutate' apiType f v) s
    else s);

  module = with lib; with lib.types; submodule ({config, lib, ...}: {
    options = {
      package = mkOption {
        type = package;
      };

      patchFunctions = mkOption {
        type = types.list;
        default = [];
      };

      input = mkOption {
        type = attrsOf attrs;
      };

      output = mkOption {
        type = attrsOf attrs;
      };

      lib = mkOption {
        type = attrs;
      };

      patches = mkOption {
        type = listOf anything;
        default = [];
      };

      filters = mkOption {
        type = attrs;
        default = {
          doc = (name: doc: true);
        };
      };
    };

    config.input = builtins.fromJSON (builtins.readFile "${config.package}/enriched.json");
    config.output = config.lib.renderDocs config.input;

    config.lib = rec{
      renderDocs = i:
        lib.mapAttrs (n: v: render (patch v)) (lib.filterAttrs config.filters.doc i);

      patch = d: lib.foldl' (a: f: f a) d config.patches;
    };
  });

  ipv4Regex = "(([0-9]{1,3}\\.){3})([0-9]{1,3})";
  ipv4Address = lib.types.strMatching ("^" + ipv4Regex + "$");

  helperModules = rec{
    hostAlias = { ... }: with lib.types; {
      options = {
        ip = lib.mkOption {
          type = ipv4Address;
        };

        hostnames = lib.mkOption {
          type = listOf str;
        };
      };
    };
    hostAliases = { config, ... }: with lib.types; {
      options = {
        hostAliases = lib.mkOption {
          type = listOf (submodule hostAlias);
        };

        output = lib.mkOption {
          type = listOf attrs;
          internal = true;
          readOnly = true;
        };
      };

      config.output = map (a: {
        __content = {
          ip = {
            __content = a.ip;
            __type = "string";
          };
          hostnames = {
            __content = map (h: {
              __content = h;
              __type = "string";
            }) (lib.unique a.hostnames);
            __type = "array";
          };
        };
        __type = "object";
      }) config.hostAliases;
    };
  };

  typeEnrichInternal = acc: input: with builtins;
    if isAttrs input then { __type = "object"; __content = lib.mapAttrs (n: v: typeEnrichInternal acc v) input; }
    else if isList input then { __type = "array"; __content = map (v: typeEnrichInternal acc v) input; }
    else { __type = "string"; __content = input; };

  typeEnrich = typeEnrichInternal {};
in
{
  options.swag.apps = lib.mkOption {
    type = lib.types.attrsOf module;
    default = {};
  };

  options.swag.lib = lib.mkOption {
    type = lib.types.attrs;
  };

  config.swag.lib = rec{
    filterOutAPIVersionKind = apiVersion: kind: _: doc: !(doc.__content.apiVersion.__content == apiVersion && doc.__content.kind.__content == kind);
    mapAPIType = type: f: mutate' type f;
    injectContent = type: new: old: old // { "__content" = old.__content // (lib.mapAttrs (n: v: {
      __type = type;
      __content = v;
    }) new); };
    removePropertyPlumbing = name: obj:
      obj // { __content = builtins.removeAttrs obj.__content [name]; };
    appendListPlumbing = property: new: old: old // {
      __content = old.__content //
        {
          "${property}" = {
            __type = "array";
            __content = (old.__content."${property}".__content or []) ++ [new];
          };
        };
    };
    addLabel = name: value: [
      (mapAPIType "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"
        (old: old // ({
          __content = old.__content // {
            labels = {
              __type = "object";
              __content = (old.__content.labels.__content or {}) // {
                "${name}" = {
                  __type = "string";
                  __content = value;
                };
              };
            };
          };
        }))
      )
    ];
    removeProperty = type: property: mapAPIType type (removePropertyPlumbing property);
    setSimple = type: new: mapAPIType type (injectContent "string" new);
    appendList = type: property: new: mapAPIType type (appendListPlumbing property new);
    setList = type: new: mapAPIType type (injectContent "array" new);
    setSimpleNamed = type: name: new: mapAPIType type (old: let oName = getMetadataName old; in if oName == name then injectContent "string" new old else old);
    setContentN = addIfNotExists: ctx: path: new:
    let
      next = builtins.head path;
      remainder = builtins.tail path;
    in
      if (builtins.hasAttr next ctx.__content) || addIfNotExists then
        ctx // {
          __content = ctx.__content // {
            "${next}" = if remainder == [] then new else setContentN addIfNotExists ctx.__content."${next}" remainder new;
          };
        }
      else
        throw "${toString path} does not exist in context";

    setContentByPath = new: type: path: [
      (mapAPIType type (old: old // (setContentN false old path (typeEnrich new))))
    ];
    setNamespace = namespace: let phrase = { inherit namespace; }; in [
      (setSimple "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta" phrase)
      (setSimple "io.k8s.api.rbac.v1.Subject" phrase)
      (setSimple "io.k8s.api.admissionregistration.v1.ServiceReference" phrase)
      (setSimple "io.k8s.apiextensions-apiserver.pkg.apis.apiextensions.v1.ServiceReference" phrase)
    ];
    scale = replicas: let phrase = { replicas = assert builtins.isInt replicas; replicas; }; in [
      (setSimple "io.k8s.api.apps.v1.DeploymentSpec" phrase)
      (setSimple "io.k8s.api.apps.v1.StatefulSetSpec" phrase)
    ];
    addEnvironmentVariable = name: value: let phrase = { __content = {
      name = {
        __content = name;
        __type = "string";
      };
      value = {
        __content = value;
        __type = "string";
      };
    }; __type = "object"; }; in [
      (appendList "io.k8s.api.core.v1.Container" "env" phrase)
    ];
    addConfigMapData = name: data: let phrase = { inherit data; }; in [
      (setSimpleNamed "io.k8s.api.core.v1.ConfigMap" name phrase)
    ];
    addToleration = { effect, key, operator, value }: let phrase = { __content = {
      effect = {
        __content = effect;
        __type = "string";
      };
      key = {
        __content = key;
        __type = "string";
      };
      operator = {
        __content = operator;
        __type = "string";
      };
      value = {
        __content = value;
        __type = "string";
      };
    }; __type = "object"; }; in [
      (appendList "io.k8s.api.core.v1.PodSpec" "tolerations" phrase)
    ];
    removePodAntiAffinityRule = rule: [
      (removeProperty "io.k8s.api.core.v1.PodAntiAffinity" rule)
    ];
    addHostAliases = input:
      let
        phrase = {
          hostAliases = (lib.evalModules {
            modules = [
              helperModules.hostAliases
              ({ ... }: {
                config.hostAliases = input;
              })
            ];
          }).config.output;
        };
      in
        [
          (setList "io.k8s.api.core.v1.PodSpec" phrase)
        ];
    setRegistryHost = host: setRegistryHostWithoutTrailingSlash "${host}/";
    setRegistryHostWithoutTrailingSlash = host: [
      (mapAPIType "io.k8s.api.core.v1.Container" (old:
        let
          oldImageRef = old.__content.image.__content;
          pathPart = with builtins; tail (filter isString (split "/" oldImageRef));
        in
            old // ({ __content = old.__content // {
              image = {
                __content = "${host}${builtins.concatStringsSep "/" pathPart}";
                __type = "string";
              };
            }; })
      ))
    ];
  };
}
