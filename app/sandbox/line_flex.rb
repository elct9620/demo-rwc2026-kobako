# Runs an untrusted layout script and answers with the LINE Flex Message it
# built. The script speaks line-message-builder's Flex DSL, but the builder
# never leaves the host: every verb crosses the sandbox boundary as one
# dispatch onto a wrapper this module owns.
module LineFlex
  # The vocabulary the guest may speak, and the whole of it. It is a public
  # contract in both directions — the ceiling the sandbox enforces, and the list
  # a script author writes against — so a verb absent here is a verb no script
  # can use, whoever wrote it.
  VERBS = %i[
    alt_text bubble carousel
    header hero hero_image body footer
    box text button image separator span
    message postback
    to_h
  ].freeze

  # A layout script is arithmetic and string building; a card measures around
  # 128 KiB of guest memory and a millisecond of wall clock. The gem's memory
  # default already sits an order of magnitude above that, but its 60 second
  # timeout is a cap nobody watching would wait out.
  TIMEOUT_SECONDS = 1.0

  # A line-message-builder node, exposed to the guest as exactly VERBS.
  #
  # The wrapper exists because the gem's nodes answer +respond_to?+ for anything
  # their context answers, which would take every name kobako's reflection floor
  # does not independently reject straight into the node's +method_missing+.
  # Binding a node directly would also expose +Base#context+, whose return value
  # crosses back as a live Handle into the context chain.
  class Node
    def initialize(node) = (@node = node)

    def to_h = @node.to_h

    def method_missing(name, *, **)
      return super unless VERBS.include?(name)

      result = @node.public_send(name, *, **)
      # A box verb returns the mutated contents Array rather than the child it
      # created, because ordinary use nests inside a construction-time block.
      # The guest holds that block on its side of the boundary, so it needs the
      # child handed back to descend into.
      child = result.is_a?(Array) ? result.last : result
      child.is_a?(Line::Message::Builder::Base) ? Node.new(child) : result
    end

    # The reflection floor lets an otherwise-unknown name through only when the
    # target answers +respond_to?+ truthy, so the forwarded verbs must be
    # answered honestly to be reachable at all.
    def respond_to_missing?(name, include_private = false)
      VERBS.include?(name) || super
    end

    private

    # Kobako's narrowing hook. Unlike the predicate above it is consulted for
    # every name, including the ones this class defines concretely, and can only
    # narrow what the floor already allows.
    def respond_to_guest?(name) = VERBS.include?(name)
  end

  # The backend bound at the guest constant +Studio+. A provider mints one per
  # invocation, so no builder state survives into the next run.
  class Studio
    def root
      Node.new(
        Line::Message::Builder::Flex::Builder.new(
          context: Line::Message::Builder::Context.new(nil)
        )
      )
    end

    private

    def respond_to_guest?(name) = name == :root
  end

  # The guest idiom. +Build+ forwards each call onto the wrapped Handle and,
  # when the call carries a block, descends into the child that comes back —
  # which is how the DSL's nesting survives a boundary the block cannot cross.
  # +Flex.with+ mirrors the gem's own entry point, so a script reads almost
  # exactly as it would against the gem directly.
  GUEST_SOURCE = <<~MRUBY
    class Build
      def initialize(handle) = (@handle = handle)

      def method_missing(name, *args, **kwargs, &blk)
        result = @handle.method_missing(name, *args, **kwargs)
        return result unless blk

        (result.is_a?(Kobako::Handle) ? Build.new(result) : result).instance_eval(&blk)
        self
      end

      def respond_to_missing?(_name, _include_private = false) = true

      def handle = @handle
    end

    module Flex
      def self.with(&blk)
        root = Build.new(Studio.root)
        root.instance_eval(&blk)
        root.handle.to_h
      end
    end
  MRUBY

  def self.extension
    Kobako::Extension.new(
      name: :LineFlex,
      source: GUEST_SOURCE,
      backend: Kobako::Extension::Backend.new(path: "Studio", provider: -> { Studio.new })
    )
  end

  # A run that produced no message. Untrusted code failing is an outcome, not
  # an emergency, so it arrives as data the caller renders like any other.
  Failure = Data.define(:reason, :message)

  # Evaluate +script+ and return the Flex Message it assembled, or a Failure
  # when the guest exhausted a cap, raised, or broke against a Service.
  def self.render(script)
    sandbox = Kobako::Sandbox.new(timeout: TIMEOUT_SECONDS)
    sandbox.install(extension)
    sandbox.eval(script).value
  rescue Kobako::TrapError, Kobako::SandboxError, Kobako::ServiceError => e
    Failure.new(reason: reason_for(e), message: e.message)
  end

  # Kobako's error classes already name why a run ended, so the reason is read
  # off the class rather than restated as a table here.
  def self.reason_for(error)
    error.class.name.demodulize.delete_suffix("Error").underscore.to_sym
  end
  private_class_method :reason_for
end
