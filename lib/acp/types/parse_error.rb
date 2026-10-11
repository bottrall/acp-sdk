# frozen_string_literal: true

# Hand-authored support for the generated types: the generator neither emits
# nor deletes this file (see TypeGenerator::SUPPORT_FILES).

# Raised by the generated from_h when a param does not match its schema
# type; the connection boundaries rescue it into an invalid-params reply
# that names the failing path.
class ACP::Types::ParseError < StandardError
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
    ACP::Types::ParseError.new([*segments, *@segments], @detail)
  end
end
