{
  config,
  lib,
  ...
}: let
  inherit
    (lib)
    attrValues
    flip
    mapAttrsToList
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionalAttrs
    types
    warnIf
    ;
in {
  options.topology.extractors.nixos-container.enable =
    mkEnableOption "topology nixos-container extractor"
    // {
      default = true;
    };

  options.containers = mkOption {
    type = types.attrsOf (
      types.submodule (submod: {
        options._nix_topology_config = mkOption {
          type = types.unspecified;
          internal = true;
          default =
            if submod.options.config.isDefined
            then submod.config.config
            else null;
          description = ''
            The configuration of the container. Defaults to `config` if that is used to define the container,
            otherwise must be set manually to make the topology extractor work.
          '';
        };
      })
    );
  };

  config = mkIf config.topology.extractors.nixos-container.enable {
    topology.dependentConfigurations = map (x: x._nix_topology_config.topology.definitions or []) (
      attrValues config.containers
    );
    topology.nodes = mkMerge (
      flip mapAttrsToList config.containers (
        containerName: container: let
          containerCfg =
            warnIf (container._nix_topology_config == null)
            "topology: The nixos container ${containerName} uses `path` instead of `config`. Please set _nix_topology_config to the `.config` of its nixosSystem instanciation to allow nix-topology to access the configuration."
            container._nix_topology_config;
        in
          optionalAttrs (containerCfg != null && containerCfg ? topology) {
            ${containerCfg.topology.id} = {
              guestType = "nixos-container";
              parent = config.topology.id;

              interfaces = mkMerge (
                flip map container.macvlans (
                  i: let
                    splitString = lib.splitString ":" i;
                    iface_host = lib.elemAt splitString 0;
                    iface_container =
                      if lib.length splitString > 1
                      then lib.elemAt splitString 1
                      else "mv-" + iface_host;
                  in {
                    ${iface_container} = {
                      type = "macvlan";
                      physicalConnections = [
                        {
                          node = config.topology.id;
                          interface = iface_host;
                          renderer.reverse = true;
                        }
                      ];
                    };
                  }
                )
                ++ flip map container.interfaces (i: {
                  ${i} = {
                    type = let
                      t = config.topology.nodes.${config.topology.id}.interfaces.${i}.type or null;
                    in
                      mkIf (t != null) t;
                    physicalConnections = [
                      {
                        node = config.topology.id;
                        interface = i;
                        renderer.reverse = true;
                      }
                    ];
                  };
                })
              );
            };

            # Add interfaces to host
            ${config.topology.id} = {
              interfaces = mkMerge (
                flip map container.macvlans (
                  i: let
                    splitString = lib.splitString ":" i;
                    iface_host = lib.elemAt splitString 0;
                  in {
                    ${iface_host} = {};
                  }
                )
                ++ flip map container.interfaces (i: {
                  ${i} = {};
                })
              );
            };
          }
      )
    );
  };
}
