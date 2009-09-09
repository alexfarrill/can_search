module CanSearch
  # Tracks the search scopes for a given model.
  class SearchScopes
    # Registered scope_types using their symbolized names as keys.
    def self.scope_types() @scope_types ||= {} end

    attr_reader :model, :scopes

    def initialize(model, &block)
      @scopes = {}
      @model  = model
      @model.extend CanSearch
      instance_eval(&block) if block
    end

    # Adds a new scope for the given model.  It works by looking up the scope class
    # in the scope_types hash and instantiating it with the given arguments.
    def scoped_by(name, options = {})
      unless options[:scope] 
        options[:scope] = if @model.columns_hash.any?{ |k,v| k == name.to_s && v.type == :boolean }
          :boolean 
        else
          :reference
        end
      end
      if scope_class = self.class.scope_types[options[:scope]]
        @scopes[name] = scope_class.new(@model, name, options)
      end
    end

    # Builds a combined scoped finder object, starting with the model itself.
    def search_for(options = {})
      @scopes.values.inject(@model) { |finder, scope| scope.scope_for(finder, options) }
    end
    
    def add_existing_scope(name)
      @scopes[name] = BaseScope.new(@model, name, :named_scope => name)
    end

    def add_existing_scopes(*names)
			names.each do |name|
				@scopes[name] = BaseScope.new(@model, name, :named_scope => name)
			end
    end

    def [](name)
      @scopes[name]
    end
  end

  # The base class for all scope classes.  Scope classes know how to take the 
  # given arguments, generate a proper named_scope for the model, and perform
  # searches on it.
  class BaseScope
    # This is the key the scope looks for to create the finder.
    attr_reader :name
    
    # This is the main attribute that is being used in the search.
    attr_reader :attribute

    # The name of the named_scope that is used.
    attr_reader :named_scope
    
    # a reference to the ActiveRecord model that this scope is attached to.
    attr_reader :model

    def initialize(model, name, options = {})
      @model, @name = model, name
      @named_scope  = options[:named_scope] if options[:named_scope]
    end
    
    # strip out any scoped keys from options and return a chained finder.
    def scope_for(finder, options = {})
      return finder unless options.keys.include? @named_scope
      value = options.delete(@named_scope)
      finder.send(@named_scope, value)
    end

    def ==(other)
      self.class == other.class && other.name == @name && other.attribute == @attribute && other.named_scope == @named_scope
    end
  end

  # Generates named_scope for belongs_to associations.  ReferenceScopes actually look for both a singular
  # and plural key.  Singular keys should be the id value or the model instance.
  #
  #   class Topic
  #     belongs_to :forum
  #   
  #     can_search do
  #       scoped_by :forums
  #     end
  #   end
  #
  #   Topic.search(:forum => 1)                  # Topic.by_forums(1)
  #   Topic.search(:forums => [1,2])             # Topic.by_forums([1,2])
  #
  class ReferenceScope < BaseScope
    attr_reader :singular_name

    # By default, the singular_name is generated with the #singularize (:forums => :forum) inflection.
    # The attribute is taken from the #foreign_key (:forum => :forum_id) inflection of the singular name.
    # The named_scope adds a "by_" prefix to the scope name (:forums => :by_forums).
    def initialize(model, name, options = {})
      super
      single         = name.to_s.singularize
      @singular_name = options[:singular]    || single.to_sym
      @attribute     = options[:attribute]   || single.foreign_key.to_sym
      @named_scope   = options[:named_scope] || "by_#{name}".to_sym
      @model.named_scope @named_scope, lambda { |records| {:conditions => {@attribute => records}} }
    end

    def scope_for(finder, options = {})
      value, values = options.delete(@singular_name), options.delete(@name) || []
      values << value if value
      return finder if values.empty?
      finder.send(@named_scope, values.size == 1 ? values.first : values)
    end
    
    def ==(other)
      super && other.singular_name == @singular_name
    end
  end
  
  # Generates named_scopes for boolean fields.
  #
  #   class Topic
  #     can_search do
  #       scoped_by :live
  #     end
  #   end
  #
  #   Topic.search(:live => true)               # Topic.live
  #   Topic.search(:live => false)              # Topic.not_live
  #
  class BooleanScope < BaseScope
    attr_reader :negative
    
    def initialize(model, name, options = {})
      super
      @attribute     = options[:attribute]   || name.to_sym
      @named_scope   = options[:named_scope] || name.to_sym
      @negative = options[:negative]
      @negative ||= @named_scope.to_s[/^has_/] ? @named_scope.to_s.gsub(/^has_/, "doesnt_have_").to_sym : "not_#{@named_scope.to_s}".to_sym
      @model.named_scope @named_scope, Proc.new { |bool, _| {:conditions => {@attribute => bool.nil? ? true : bool}} }
      @model.named_scope @negative, Proc.new { |bool, _| {:conditions => {@attribute => bool.nil? ? false : !bool}} }
    end

    def ==(other)
      super && other.negative == @negative
    end
  end

  SearchScopes.scope_types.update \
    :reference  => ReferenceScope,
    :boolean => BooleanScope
end

send respond_to?(:require_dependency) ? :require_dependency : :require, 'can_search/date_range_scope'
send respond_to?(:require_dependency) ? :require_dependency : :require, 'can_search/like_query_scope'
