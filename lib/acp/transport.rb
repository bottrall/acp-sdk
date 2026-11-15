# frozen_string_literal: true

module ACP::Transport
  Reply = Data.define(
    :result, #: ACP::Transport::_Response
    :after #: ^() -> void
  )
end
