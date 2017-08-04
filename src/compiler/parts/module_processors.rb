module DabNodeModuleProcessors
  def self.included(base)
    base.send :extend, ClassMethods
  end

  module ClassMethods
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
        end
      end

      define_method_chain.call(:check_with, :check_callbacks)
      define_method_chain.call(:after_init, :init_callbacks)
      define_method_chain.call(:lower_with, :lower_callbacks)
      define_method_chain.call(:optimize_with, :optimize_callbacks)
      define_method_chain.call(:strip_with, :strip_callbacks)
      define_method_chain.call(:flatten_with, :flatten_callbacks)
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

  def run_check_callbacks!
    run_all_processors!(:check_callbacks)
  end

  def init!
    run_all_processors!(:init_callbacks)
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
    $processors_cache ||= {}
    $processors_cache[self.class] ||= {}
    $processors_cache[self.class][type] ||= self.class.send(type)
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

  def run_all_processors!(type)
    ret = false
    all_nodes.each do |child|
      test = child.sub_run_all_processors!(type)
      ret ||= test
    end
    ret
  end
end
