# frozen_string_literal: true

# Orders every SDN object type before pve_sdn_apply.
#
# The apply has to observe the writes a run made before it decides whether the
# running configuration is up to date -- Resource API retrieves current state
# per resource at its own position in the graph, so an apply scheduled too
# early would read the pre-run state and report green over a stale cluster.
#
# The edge is declared here rather than as an autorequire on pve_sdn_apply
# because that direction would need a catalog-wide scan for resources of each
# SDN type, while this direction is exact: pve_sdn_apply is a singleton whose
# title is always 'sdn'. An autobefore naming a resource that is not in the
# catalog is simply ignored, so this costs nothing when no apply is declared --
# which is the default, and the whole point of the design.
module Puppet::Type::PveSdnApplyAutobefore
  APPLY_TITLE = 'sdn'

  def self.register(type_name)
    Puppet::Type.type(type_name).autobefore(:pve_sdn_apply) { [APPLY_TITLE] }
  end
end
