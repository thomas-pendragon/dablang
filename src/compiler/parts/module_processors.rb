PROCESSOR_CHECK_INDEX = 0
PROCESSOR_DIRTY_CHECK_INDEX = 1
PROCESSOR_INIT_INDEX = 2
PROCESSOR_LOWER_INDEX = 3
PROCESSOR_OPTIMIZE_INDEX = 4
PROCESSOR_STRIP_INDEX = 5
PROCESSOR_FLATTEN_INDEX = 6
PROCESSOR_SSA_INDEX = 7
PROCESSOR_POST_SSA_INDEX = 8
PROCESSOR_OPTIMIZE_SSA_INDEX = 9

PROCESSORS_HASH = [
  [PROCESSOR_CHECK_INDEX, :check_with, :check_callbacks],
  [PROCESSOR_DIRTY_CHECK_INDEX, :dirty_check_with, :dirty_check_callbacks],
  [PROCESSOR_INIT_INDEX, :after_init, :init_callbacks],
  [PROCESSOR_LOWER_INDEX, :lower_with, :lower_callbacks],
  [PROCESSOR_OPTIMIZE_INDEX, :optimize_with, :optimize_callbacks],
  [PROCESSOR_STRIP_INDEX, :strip_with, :strip_callbacks],
  [PROCESSOR_FLATTEN_INDEX, :flatten_with, :flatten_callbacks],
  [PROCESSOR_SSA_INDEX, :ssa_with, :ssa_callbacks],
  [PROCESSOR_OPTIMIZE_SSA_INDEX, :ssa_optimize_with, :optimize_ssa_callbacks],
  [PROCESSOR_POST_SSA_INDEX, :post_ssa_with, :post_ssa_callbacks],
].freeze

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

      PROCESSORS_HASH.each do |row|
        _index, key, value = *row
        define_method_chain.call(key, value)
      end
    end

    def save_cached_processors!
      @processors_cache ||= []
      PROCESSORS_HASH.each do |row|
        index, _, type = *row
        @processors_cache[index] = self.send(type)
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

    def processors_cache
      @processors_cache
    end
  end

  def run_dirty_check_callbacks!
    run_all_processors!(PROCESSOR_DIRTY_CHECK_INDEX, true)
  end

  def run_check_callbacks!
    run_all_processors!(PROCESSOR_CHECK_INDEX)
  end

  def init!
    run_all_processors!(PROCESSOR_INIT_INDEX)
  end

  def run_optimize_processors!
    run_processors!(PROCESSOR_OPTIMIZE_INDEX)
  end

  def run_ssa_processors!
    run_processors!(PROCESSOR_SSA_INDEX)
  end

  def run_optimize_ssa_processors!
    run_processors!(PROCESSOR_OPTIMIZE_SSA_INDEX)
  end

  def run_post_ssa_processors!
    run_processors!(PROCESSOR_POST_SSA_INDEX)
  end

  def run_lower_processors!
    run_processors!(PROCESSOR_LOWER_INDEX)
  end

  def run_strip_processors!
    run_processors!(PROCESSOR_STRIP_INDEX)
  end

  def run_flatten_processors!
    run_processors!(PROCESSOR_FLATTEN_INDEX)
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
    self.class.processors_cache[type]
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
