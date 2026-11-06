# frozen_string_literal: true

require 'puppet'

# @api private
module PuppetX; end
# @api private
module PuppetX::ProxmoxVirtualEnvironment; end

# Read-only reader for the secrets PVE persists under /etc/pve/priv.
#
# The PVE API is write-only for most of these values, but PVE writes every one
# of them to the node -- five of six in plaintext, the sixth as a crypt(3)
# hash. Reading them here is what makes drift detection possible at all.
#
# Two failure modes, deliberately distinguished:
#
#   * a missing secret *file* means PVE holds no secret        -> nil
#   * an unreadable priv *dir* means we cannot know            -> raise
#
# Reporting "in sync" when the value cannot be seen would silently disable
# enforcement, which is the exact bug this module exists to fix. So the second
# case fails closed.
#
# ALWAYS require this file with `require_relative` -- see config.rb for why a
# bare require breaks type autoloading inside puppetserver.
#
# priv_dir is writable purely as a test seam, so specs can point the store at a
# fixture tree instead of a real /etc/pve.
module PuppetX::ProxmoxVirtualEnvironment::SecretStore
  DEFAULT_PRIV_DIR = '/etc/pve/priv'
  # PVE object names never contain a path separator. Anything that does is a
  # traversal attempt or a bug, and must not reach File.read.
  SAFE_NAME = %r{\A[^/\\\0]+\z}

  class << self
    attr_writer :priv_dir

    def priv_dir
      @priv_dir || DEFAULT_PRIV_DIR
    end

    # Non-raising probe. get() runs during discovery for every resource in the
    # catalog, including ones managing no secrets at all, so it must never
    # raise merely because the agent is not on a PVE node.
    def available?
      File.directory?(priv_dir) && File.readable?(priv_dir)
    end

    # Fail-closed guard, called from insync? and therefore only for attributes
    # actually being managed.
    def assert_available!(attribute_name)
      return if available?

      raise Puppet::ResourceError,
            "Cannot verify '#{attribute_name}': #{priv_dir} is not readable. " \
            'Managing PVE secrets requires the Puppet agent to run on the PVE node as root.'
    end

    def storage_password(storeid)
      read_secret_file(File.join(priv_dir, 'storage', "#{safe(storeid)}.pw"))
    end

    # PVE/Auth/LDAP.pm:414-429 checks priv/realm first, then the pre-move
    # priv/ldap. Realms created before the move still live in the old
    # directory, so checking only the new one would report false drift forever
    # on exactly the longest-lived realms.
    def realm_password(realm)
      name = safe(realm)
      read_secret_file(File.join(priv_dir, 'realm', "#{name}.pw")) ||
        read_secret_file(File.join(priv_dir, 'ldap', "#{name}.pw"))
    end

    # shadow.cfg lines are "username:hash:" -- keyed by the BARE username with
    # the realm stripped. Usernames may contain dots (pdm.example.com is real),
    # so split on '@' and never on '.'.
    def user_password_hash(userid)
      username = userid.to_s.split('@').first.to_s
      return nil if username.empty?

      shadow_entries[username]
    end

    # PVE section-config: a "<type>: <name>" header followed by indented
    # "<field> <value>" lines. Webhook secrets repeat the 'secret' field once
    # per entry, so every match is returned, newline-joined.
    def notification_secret(type, name, field)
      values = notification_section(type, name).filter_map do |line|
        key, value = line.strip.split(' ', 2)
        value if key == field.to_s && !value.nil?
      end
      return nil if values.empty?

      values.join("\n")
    end

    private

    def safe(name)
      value = name.to_s
      return value if SAFE_NAME.match?(value)

      raise Puppet::ResourceError, "invalid PVE object name: #{value.inspect}"
    end

    # nil means "PVE holds no secret here". A read error that is not ENOENT
    # (EACCES on a non-root agent, EIO on a sick pmxcfs) must not be mistaken
    # for that, so it raises.
    def read_secret_file(path)
      File.read(path).chomp
    rescue Errno::ENOENT
      nil
    rescue SystemCallError => error
      raise Puppet::ResourceError, "Failed to read #{path}: #{error.message}"
    end

    def shadow_entries
      contents = read_secret_file(File.join(priv_dir, 'shadow.cfg'))
      return {} if contents.nil?

      contents.each_line.filter_map { |line| shadow_entry(line) }.to_h
    end

    # A shadow.cfg line is "username:hash:". Anything without both halves is a
    # blank or malformed line and is skipped rather than treated as an entry.
    def shadow_entry(line)
      name, hash = line.strip.split(':', 3)
      return nil if name.nil? || name.empty? || hash.nil? || hash.empty?

      [name, hash]
    end

    def notification_section(type, name)
      contents = read_secret_file(File.join(priv_dir, 'notifications.cfg'))
      return [] if contents.nil?

      config_sections(contents).fetch("#{type}: #{name}", [])
    end

    # Splits PVE section-config into {header => [indented lines]}. An
    # unindented line opens a section; indented lines belong to the one above.
    def config_sections(contents)
      header = nil
      contents.each_line.with_object({}) do |line, sections|
        if line.match?(%r{\A\S})
          header = line.strip
        elsif header
          (sections[header] ||= []) << line
        end
      end
    end
  end
end
