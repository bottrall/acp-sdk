# frozen_string_literal: true

module TypeGenerator::Naming
  extend self

  # @rbs ref: String
  # @rbs return: String
  def ref_name(ref) = ref.delete_prefix('#/$defs/')

  # @rbs const: String
  # @rbs return: String
  def path(const)
    "#{const.delete_prefix("#{TypeGenerator::NAMESPACE}::").split('::').map { |part| snake(part) }.join('/')}.rb"
  end

  # @rbs name: String
  # @rbs return: String
  def snake(name) = name.delete_prefix('_').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase

  # @rbs name: String
  # @rbs return: String
  def camel(name) = name.split(/[^a-zA-Z\d]/).map(&:capitalize).join
end
