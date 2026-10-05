# frozen_string_literal: true

module ACP::Types
  # Raised by the generated from_h when a param does not match its schema
  # type; the connection boundaries rescue it into an invalid-params reply
  # that names the failing path.
  class ParseError < StandardError
    # @rbs @segments: Array[String | Integer]
    # @rbs @detail: String

    # @rbs segments: Array[String | Integer]
    # @rbs detail: String
    # @rbs return: void
    def initialize(segments, detail)
      @segments = segments.freeze
      @detail = detail
      super("#{path}: #{detail}")
    end

    # @dynamic segments
    attr_reader :segments #: Array[String | Integer]

    # @rbs return: String
    def path
      segments.each_with_index.map do |segment, index|
        if segment.is_a?(Integer) then "[#{segment}]"
        elsif index.zero? then segment
        else ".#{segment}"
        end
      end.join
    end

    # Prepends a container's segments so nested failures report an absolute path.
    #
    # @rbs *segments: (String | Integer)
    # @rbs return: ACP::Types::ParseError
    def prefix(*segments)
      ParseError.new([*segments, *@segments], @detail)
    end
  end

  # The guards the generated from_h methods call. Each takes the fetched value
  # and the path to it, and raises ParseError naming that path when the value
  # does not match the schema type. Nested from_h failures come back with the
  # field path prepended, so the reported path is absolute.
  module Check
    # @rbs hash: Hash[String, untyped]
    # @rbs key: String
    # @rbs return: untyped
    def self.key(hash, key)
      hash.fetch(key)
    rescue KeyError
      raise ParseError.new([key], 'is required')
    end

    # @rbs value: untyped
    # @rbs path: String | Array[String | Integer]
    # @rbs allow_nil: bool
    # @rbs allow_unset: bool
    # @rbs return: untyped
    def self.string(value, path, allow_nil: false, allow_unset: false)
      return value if value.is_a?(String) || skipped?(value, allow_nil, allow_unset)

      raise ParseError.new(segments(path), "expected String, got #{describe(value)}")
    end

    # @rbs value: untyped
    # @rbs path: String | Array[String | Integer]
    # @rbs allow_nil: bool
    # @rbs allow_unset: bool
    # @rbs return: untyped
    def self.boolean(value, path, allow_nil: false, allow_unset: false)
      return value if value == true || value == false || skipped?(value, allow_nil, allow_unset)

      raise ParseError.new(segments(path), "expected boolean, got #{describe(value)}")
    end

    # @rbs value: untyped
    # @rbs path: String | Array[String | Integer]
    # @rbs min: Integer?
    # @rbs max: Integer?
    # @rbs allow_nil: bool
    # @rbs allow_unset: bool
    # @rbs return: untyped
    def self.integer(value, path, min: nil, max: nil, allow_nil: false, allow_unset: false)
      return value if (value.is_a?(Integer) && within?(value, min, max)) || skipped?(value, allow_nil, allow_unset)

      raise ParseError.new(segments(path), "expected #{bounded('Integer', min, max)}, got #{describe(value)}")
    end

    # @rbs value: untyped
    # @rbs path: String | Array[String | Integer]
    # @rbs min: Integer?
    # @rbs max: Integer?
    # @rbs allow_nil: bool
    # @rbs allow_unset: bool
    # @rbs return: untyped
    def self.number(value, path, min: nil, max: nil, allow_nil: false, allow_unset: false)
      return value if (value.is_a?(Numeric) && within?(value, min, max)) || skipped?(value, allow_nil, allow_unset)

      raise ParseError.new(segments(path), "expected #{bounded('Numeric', min, max)}, got #{describe(value)}")
    end

    # @rbs value: untyped
    # @rbs path: String | Array[String | Integer]
    # @rbs values: Array[untyped]
    # @rbs allow_nil: bool
    # @rbs allow_unset: bool
    # @rbs return: untyped
    def self.enum(value, path, values, allow_nil: false, allow_unset: false)
      return value if values.include?(value) || skipped?(value, allow_nil, allow_unset)

      expected = values.map(&:inspect).join(', ')
      raise ParseError.new(segments(path), "expected one of #{expected}, got #{describe(value)}")
    end

    # @rbs value: untyped
    # @rbs path: String | Array[String | Integer]
    # @rbs classes: Array[untyped]
    # @rbs allow_nil: bool
    # @rbs allow_unset: bool
    # @rbs ?&items: (untyped, Array[String | Integer]) -> void
    # @rbs return: untyped
    def self.one_of(value, path, classes, allow_nil: false, allow_unset: false, &items)
      return value if skipped?(value, allow_nil, allow_unset)

      matched = classes.any? { |klass| value.is_a?(klass) }
      unless matched
        raise ParseError.new(segments(path), "expected #{classes.map(&:name).join(' | ')}, got #{describe(value)}")
      end

      return value unless value.is_a?(Array) && items

      value.each_with_index { |item, index| yield(item, [*segments(path), index]) }
      value
    end

    # @rbs value: untyped
    # @rbs path: String | Array[String | Integer]
    # @rbs allow_nil: bool
    # @rbs allow_unset: bool
    # @rbs &check: (untyped, Array[String | Integer]) -> void
    # @rbs return: untyped
    def self.hash(value, path, allow_nil: false, allow_unset: false, &check)
      return value if skipped?(value, allow_nil, allow_unset)
      raise ParseError.new(segments(path), "expected object, got #{describe(value)}") unless value.is_a?(Hash)

      parsed = {} #: Hash[String, untyped]
      value.each { |key, item| parsed[key] = yield(item, [*segments(path), key]) }
      parsed
    end

    # @rbs value: untyped
    # @rbs path: String | Array[String | Integer]
    # @rbs allow_nil: bool
    # @rbs allow_unset: bool
    # @rbs &check: (untyped, Array[String | Integer]) -> void
    # @rbs return: untyped
    def self.array(value, path, allow_nil: false, allow_unset: false, &check)
      return value if skipped?(value, allow_nil, allow_unset)
      raise ParseError.new(segments(path), "expected array, got #{describe(value)}") unless value.is_a?(Array)

      value.each_with_index.map { |item, index| yield(item, [*segments(path), index]) }
    end

    # @rbs value: untyped
    # @rbs path: String | Array[String | Integer]
    # @rbs klass: untyped
    # @rbs allow_nil: bool
    # @rbs allow_unset: bool
    # @rbs return: untyped
    def self.object(value, path, klass, allow_nil: false, allow_unset: false)
      return value if skipped?(value, allow_nil, allow_unset)
      raise ParseError.new(segments(path), "expected object, got #{describe(value)}") unless value.is_a?(Hash)

      begin
        klass.from_h(value)
      rescue ParseError => e
        raise e.prefix(*segments(path))
      end
    end

    # @rbs value: untyped
    # @rbs path: String | Array[String | Integer]
    # @rbs klass: untyped
    # @rbs allow_nil: bool
    # @rbs allow_unset: bool
    # @rbs return: untyped
    def self.objects(value, path, klass, allow_nil: false, allow_unset: false)
      return value if skipped?(value, allow_nil, allow_unset)
      raise ParseError.new(segments(path), "expected array, got #{describe(value)}") unless value.is_a?(Array)

      value.each_with_index do |item, index|
        next if item.is_a?(Hash)

        raise ParseError.new([*segments(path), index], "expected object, got #{describe(item)}")
      end

      begin
        klass.from_a(value)
      rescue ParseError => e
        raise e.prefix(*segments(path))
      end
    end

    # @rbs value: untyped
    # @rbs allow_nil: bool
    # @rbs allow_unset: bool
    # @rbs return: bool
    def self.skipped?(value, allow_nil, allow_unset)
      (value.nil? && allow_nil) || (allow_unset && value.equal?(:unset))
    end

    # @rbs path: String | Array[String | Integer]
    # @rbs return: Array[String | Integer]
    def self.segments(path)
      path.is_a?(Array) ? path : [path]
    end

    # @rbs value: untyped
    # @rbs return: String
    def self.describe(value)
      case value
      when nil then 'null'
      when true then 'true'
      when false then 'false'
      else value.class.name
      end
    end

    # @rbs value: Numeric
    # @rbs min: Integer?
    # @rbs max: Integer?
    # @rbs return: bool
    def self.within?(value, min, max)
      (min.nil? || value >= min) && (max.nil? || value <= max)
    end

    # @rbs name: String
    # @rbs min: Integer?
    # @rbs max: Integer?
    # @rbs return: String
    def self.bounded(name, min, max)
      if min && max then "#{name} between #{min} and #{max}"
      elsif min then "#{name} >= #{min}"
      elsif max then "#{name} <= #{max}"
      else name
      end
    end
  end
end
