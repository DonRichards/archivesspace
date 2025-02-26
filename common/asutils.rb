require 'java'
require 'tmpdir'
require 'tempfile'
require 'config/config-distribution'
require 'asconstants'

# Some basic helpers that are used in all parts of the application, both
# development and packaged.
# Note: ASUtils gets pulled in all over the place, and in some places prior to
# any gems having been loaded.  Be careful about loading gems here, as the gem
# path might not yet be configured.  For example, loading the 'json' gem can
# cause you to pull in the version that ships with JRuby, rather than the one in
# your Gemfile.
module ASUtils
  def self.keys_as_strings(hash)
    result = {}

    hash.each do |key, value|
      result[key.to_s] = value.is_a?(Date) ? value.to_s : value
    end

    result
  end

  def self.as_array(thing)
    return [] if thing.nil?
    thing.is_a?(Array) ? thing : [thing]
  end

  def self.jsonmodels_to_hashes(elt)
    if elt.is_a?(JSONModelType)
      elt = elt.to_hash(:raw)
    end

    if elt.is_a?(Hash)
      Hash[elt.map { |k, v| [k, self.jsonmodels_to_hashes(v)] }]
    elsif elt.is_a?(Array)
      elt.map { |v| self.jsonmodels_to_hashes(v) }
    else
      elt
    end
  end

  def self.json_parse(s)
    JSON.parse(s, max_nesting: false, create_additions: false)
  end

  # A bit funny to wrap this ourselves, but there's an interesting case when
  # running under rspec.
  #
  # Rspec reseeds the random number generator at the beginning of every suite
  # run, which means that Tempfile's "random" filenames are often IDENTICAL
  # between subsequent Tempfile invocations across test runs.
  #
  # This shouldn't really matter, except when this happens:
  #
  #  * Test1 runs and produces tempfile "somerandomfile", which gets closed and
  #    unlinked.
  #
  #  * Test2 runs and gets given "somerandomfile" too.  It starts working with it.
  #
  #  * Then, bam!  Garbage collection runs, and finalizes the object from Test1.
  #    This unlinks the underlying temp file while Test2 is still using it!
  #
  # So yeah, not cool.  We try to inject a little randomness into "base" to
  # avoid these sort of shenanigans, even though it really shouldn't matter in
  # production.
  def self.tempfile(base)
    Tempfile.new("#{base}_#{java.lang.System.currentTimeMillis}")
  end

  def self.to_json(obj, opts = {})
    if obj.respond_to?(:jsonize)
      obj.jsonize(opts.merge(max_nesting: false))
    else
      obj.to_json(opts.merge(max_nesting: false))
    end
  end

  def self.fixed_jruby_path(root = nil)
    this_dir = __dir__.gsub(%r{uri:classloader:(\/)?}, '')
    this_dir = this_dir.length.zero? ? '.' : this_dir
    [
      File.join(*[this_dir, '..', root].compact),
      File.join(*[File.realpath(this_dir), '..', root].compact)
    ].find { |dir| dir && Dir.exist?(dir) }
  end

  def self.find_base_directory(root = nil)
    # JRuby 9K seems to be adding this strange suffix...
    # Example: /pat/to/archivesspace/backend/uri:classloader:
    res = [java.lang.System.get_property('ASPACE_LAUNCHER_BASE'),
           java.lang.System.get_property('catalina.base'),
           fixed_jruby_path(root)]
          .find { |dir| dir && Dir.exist?(dir) }

    res
  end

  def self.plugin_base_directory
    # if a specific plugins directory is set in config.rb,
    # we use that. Otherwise, find the 'plugins' dir in the
    # aspace base.
    if AppConfig.changed?(:plugins_directory)
      # Yields something relative to our base directory if a relative path is used.
      # Absolute paths will pass through unchanged.
      File.absolute_path(AppConfig[:plugins_directory], self.find_base_directory)
    else
      File.join( *[ self.find_base_directory, 'plugins'])
    end
  end

  def self.find_local_directories(base = nil, *plugins)
    plugins = AppConfig[:plugins] if plugins.empty?
    base_directory = self.plugin_base_directory

    Array(plugins).map do |plugin|
      File.join(*[base_directory, plugin, base].compact)
    end
  end

  def self.find_locales_directories(base = nil)
    [File.join(*[self.find_base_directory('common'), 'locales', base].compact)]
  end

  def self.extract_nested_strings(coll)
    if coll.is_a?(Hash)
      coll.values.map { |v| self.extract_nested_strings(v) }.flatten.compact
    elsif coll.is_a?(Array)
      coll.map { |v| self.extract_nested_strings(v) }.flatten.compact
    else
      coll
    end
  end

  def self.get_diagnostics(exception = nil)
    runtime = java.lang.Runtime.getRuntime
    {
      version: ASConstants.VERSION,
      appconfig: defined?(AppConfig) ? AppConfig.dump_sanitized : 'not loaded',
      memory: { free: runtime.freeMemory, max: runtime.maxMemory,
                total: runtime.totalMemory },
      cpu_count: runtime.availableProcessors,
      exception: exception && { msg: exception, backtrace: exception.backtrace }
    }
  end

  def self.diagnostic_trace_msg(filename)
    <<ERRMSG
      #{'=' * 72}
      A trace file has been written to the following location: #{filename}

      This file contains information that will assist developers in diagnosing
      problems with your ArchivesSpace installation.  Please review the file's
      contents for sensitive information (such as passwords) that you might not
      want to share.
      #{'=' * 72}
ERRMSG
  end

  def self.dump_diagnostics(exception = nil)
    unless defined?(JSON)
      # We might get invoked before everything has been loaded,
      # so just load a minimal set.
      require 'json'
    end
    diagnostics = get_diagnostics(exception)
    tmp = File.join(Dir.tmpdir, "aspace_diagnostic_#{Time.now.to_i}.txt")
    File.open(tmp, 'w') { |fh| fh.write(JSON.pretty_generate(diagnostics)) }
    $stderr.puts diagnostic_trace_msg(tmp)
    raise exception if exception
  end

  # Recursively overlays hash2 onto hash 1
  def self.deep_merge(hash1, hash2)
    target = hash1.dup
    hash2.each_key do |key|
      if hash2[key].is_a?(Hash) && hash1[key].is_a?(Hash)
        target[key] = self.deep_merge(target[key], hash2[key])
        next
      end
      target[key] = hash2[key]
    end
    target
  end

  # Recursively concatenates hash2 onto hash 1
  def self.deep_merge_concat(hash1, hash2)
    target = hash1.dup
    hash2.keys.each do |key|
      if hash2[key].is_a? Hash and hash1[key].is_a? Hash
        target[key] = self.deep_merge_concat(target[key], hash2[key])
        next
      end
      if hash2[key].is_a? Array and hash1[key].is_a? Array

        if hash1[key] === []
          target[key] = hash2[key]
        elsif hash2[key] === []
          target[key] = target[key]
        else
          target_array = []
          target[key].zip(hash2[key]).each do |target_a, hash2_a|
            if target_a.nil?
              target_array << hash2_a
            elsif hash2_a.nil?
              target_array << target_a
            else
              target_array << self.deep_merge_concat(target_a, hash2_a)
            end
          end
          target[key] = target_array
        end
        next
      end
      if hash1[key] === true and key != "is_display_name" and key != "authorized"
        hash1[key] = "true"
      elsif hash1[key] === false and key != "is_display_name" and key != "authorized"
        hash1[key] = "false"
      end
      if hash2[key] === true and key != "is_display_name" and key != "authorized"
        hash2[key] = "1"
      elsif hash2[key] === false and key != "is_display_name" and key != "authorized"
        hash2[key] = "0"
      end
      if hash1[key].is_a? String
        if hash1[key] == hash2[key]
          target[key] = hash2[key]
        else
          if key == "jsonmodel_type" and hash1[key].include?("note") and hash2[key].include?("note")
            raise "Required Note Types must not conflict with Default Note Types"
          elsif key == "jsonmodel_type" and hash1[key].include?("relationship") and hash2[key].include?("relationship")
            raise "Required Relationship Types must not conflict with Default Relationship Types"
          else
            target[key] = hash1[key] + '_' + hash2[key]
          end
        end
      else
        target[key] = hash2[key]
      end
    end
    target
  end

  def self.load_plugin_gems(context)
    ASUtils.find_local_directories.each do |plugin|
      gemfile = File.join(plugin, 'Gemfile')
      if File.exist?(gemfile)
        # only load Gemfiles we find
        context.instance_eval(File.read(gemfile), gemfile, 1)
      end
    end
  end

  # Borrowed from:activesupport/lib/active_support/core_ext/array/wrap.rb:36
  def self.wrap(object)
    if object.nil?
      []
    elsif object.respond_to?(:to_ary)
      object.to_ary || [object]
    else
      [object]
    end
  end

  # Recursively find any hash entry whose key is in `keys`.  When we find a
  # match, call `block` with the key and value as arguments.
  #
  # Skips descending into any hash entry whose key is in `ignore_keys` (allowing
  # us to avoid walking '_resolved' subtrees, for example)
  def self.search_nested(elt, keys, ignore_keys = [], &block)
    if elt.respond_to?(:key?)
      keys.each do |key|
        if elt.key?(key)
          block.call(key, elt.fetch(key))
        end
      end

      elt.each.each do |next_key, value|
        unless ignore_keys.include?(next_key)
          search_nested(value, keys, ignore_keys, &block)
        end
      end
    elsif elt.respond_to?(:each)
      elt.each do |value|
        search_nested(value, keys, ignore_keys, &block)
      end
    end
  end

  # recursively walk `obj` and remove any hash entry whose key returns `true`
  # for `block.call(key)`.
  #
  # `obj` can be an arbitrarily nested combination of array-like and hash-like
  # things.
  def self.recursive_reject_key(obj, &block)
    if obj.nil? || block.nil?
      obj
    elsif obj.respond_to?(:each_pair)
      result = {}
      obj.each_pair do |k, v|
        if !block.call(k)
          result[k] = recursive_reject_key(v, &block)
        end
      end
      result
    elsif obj.respond_to?(:map)
      obj.map { |elt| recursive_reject_key(elt, &block) }
    else
      obj
    end
  end

  def self.blank?(obj)
    if obj.nil?
      true
    elsif obj.respond_to?(:empty?)
      !!obj.empty?
    else
      !obj
    end
  end

  def self.present?(obj)
    !blank?(obj)
  end


  PluginDependency = Struct.new(:depends_on, :recommends)

  def self.load_plugin_dependencies
    # YAML will generally have already been loaded at this point so this is
    # usually a no-op.  This is here for DB migrations, which now rely on this
    # code to run in the correct order and won't otherwise have loaded YAML.
    require 'yaml'

    result = {}

    ASUtils.find_local_directories('config.yml').each do |f|
      next unless File.exist?(f)

      config = YAML.load_file(f)
      plugin_name = File.basename(File.dirname(f))

      result[plugin_name] = PluginDependency.new(config.fetch('depends_on_plugins', []),
                                                 config.fetch('recommends_plugins', []))
    end

    # All other plugins have no dependencies
    all_plugins = ASUtils.wrap(AppConfig[:plugins])

    all_plugins.each do |plugin|
      result[plugin] ||= PluginDependency.new([], [])
    end

    # Check that hard dependencies are satisfied and warn about missing recommended plugins.
    all_plugins.each do |plugin|
      plugin_deps = result.fetch(plugin)

      unless (plugin_deps.depends_on - all_plugins).empty?
        raise "Plugin #{plugin} is missing dependency plugin(s): #{(plugin_deps.depends_on - all_plugins).join(', ')}"
      end

      unless (plugin_deps.recommends - all_plugins).empty?
        # No standard logging mechanism between public/backend/frontend/indexer.
        # Sorry for the puts!
        $stderr.puts("INFO: Plugin #{plugin} recommends additional plugin(s): #{(plugin_deps.recommends - all_plugins).join(', ')}")
      end
    end

    result
  end


  def self.order_plugins(plugin_dirs)
    all_plugins = ASUtils.wrap(AppConfig[:plugins])
    all_deps = self.load_plugin_dependencies

    # Order our list of plugins by walking the dependency graph
    to_process = all_plugins.clone
    ordered_plugins = []
    while !to_process.empty?
      # Select plugins whose prerequisites are all satisfied.
      next_plugins = to_process.select {|plugin|
        plugin_deps = all_deps.fetch(plugin)
        ((plugin_deps.depends_on + plugin_deps.recommends) - ordered_plugins).empty?
      }

      # If we didn't match, try selecting a plugin whose hard dependencies are
      # satisfied (ignoring recommended plugins).
      if next_plugins.empty?
        next_plugins = to_process.select {|plugin|
          plugin_deps = all_deps.fetch(plugin)
          (plugin_deps.depends_on - ordered_plugins).empty?
        }
      end

      # If we're still deadlocked then there must be a dependency cycle...
      if next_plugins.empty?
        raise "Plugin dependency cycle detected among the following plugins: #{to_process.join(', ')}"
      end

      ordered_plugins.concat(next_plugins)
      to_process -= next_plugins
    end

    # Our plugin base dir complete with trailing path separator
    plugin_base_dir = File.join(File.absolute_path(self.plugin_base_directory),
                                "")

    # Sort our input according to its position in our plugin ordering.  Entries
    # that aren't explicitly ordered can load in any order.
    plugin_dirs.map {|f| File.absolute_path(f)}.sort_by {|plugin_dir|
      unless plugin_dir.start_with?(plugin_base_dir)
        raise "Assertion failure: Unexpected plugin dir: '#{plugin_dir}' was expected to begin with '#{plugin_base_dir}'"
      end

      plugin_name = (plugin_dir.gsub(plugin_base_dir, "")).split(File::SEPARATOR).find {|segment| segment != '.'}
      ordered_plugins.index(plugin_name) or raise "Expected to find #{plugin_name} but didn't!"
    }
  end
end
