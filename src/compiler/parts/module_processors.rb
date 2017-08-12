PROCESSORS_HASH = {
  check_with: :check_callbacks,
  dirty_check_with: :dirty_check_callbacks,
  after_init: :init_callbacks,
  lower_with: :lower_callbacks,
  optimize_with: :optimize_callbacks,
  strip_with: :strip_callbacks,
  flatten_with: :flatten_callbacks,
}.freeze

module DabNodeModuleProcessors
  def self.included(base)
    base.send :extend, ClassMethods

    base.define_processors!
    base.save_cached_processors!
  end

  module ClassMethods
    def inherited(subclass)
      super
      subclass.save_cached_processors!
    end

    def define_processors!
      define_method_chain = proc do |method_name, collection_name|
        define_singleton_method(collection_name) do
          ret = safe_instance_variable_get("@#{collection_name}") || []
          if self.superclass < DabNode
            ret |= self.superclass.send(collection_name)
          end
          ret
        end

        define_singleton_method(method_name) do |klass|
          name = "@#{collection_name}"
          collection = safe_instance_variable_get(name) || []
          collection << klass
          instance_variable_set(name, collection)
          save_cached_processors!
        end
      end

      PROCESSORS_HASH.each do |key, value|
        define_method_chain.call(key, value)
      end
    end

    def save_cached_processors!
      $processors_cache ||= {}
      $processors_cache[self] ||= {}
      PROCESSORS_HASH.values.each do |type|
        $processors_cache[self][type] = self.send(type)
      end
    end

    def run_callback(item, callback)
      dab_benchmark(callback) do
        case callback
        when Class
          callback.new.run(item)
        when Symbol
          item.send(callback)
        else
          raise "unknown callback #{callback.class}"
        end
      end
    end
  end

  def run_dirty_check_callbacks!
    run_all_processors!(:dirty_check_callbacks, true)
  end

  def run_check_callbacks!
    run_all_processors!(:check_callbacks)
  end

  def init!
    run_all_processors!(:init_callbacks)
  end

  def run_optimize_processors!
    run_processors!(:optimize_callbacks)
  end

  def run_lower_processors!
    run_processors!(:lower_callbacks)
  end

  def run_strip_processors!
    run_processors!(:strip_callbacks)
  end

  def run_flatten_processors!
    run_processors!(:flatten_callbacks)
  end

  def run_processors!(type)
    all_nodes.each do |node|
      return true if node._self_run_processors!(type)
    end
    false
  end

  def _self_run_processors!(type)
    list = _processors(type)
    list.each do |item|
      if self.class.run_callback(self, item)
        err "Run: #{self.class} #{item}\n".yellow.bold if $debug
        return true
      end
    end
    false
  end

  def _processors(type)
    $processors_cache[self.class][type]
  end

  def sub_run_all_processors!(type)
    list = _processors(type)
    ret = false
    list.each do |item|
      test = self.class.run_callback(self, item)
      ret ||= test
    end
    ret
  end

  def run_all_processors!(type, dirty_only = false)
    ret = false
    all_nodes.each do |child|
      next if dirty_only && !child.dirty?
      test = child.sub_run_all_processors!(type)
      child.dirty = false if dirty_only && !test
      ret ||= test
    end
    ret
  end
end
