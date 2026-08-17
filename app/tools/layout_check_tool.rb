# What the writer runs a script through before answering with it. The sandbox
# is the only thing that knows whether a script assembles a card, so the writer
# is handed the same boundary the app will run it behind — and what comes back
# is the failure translated into something it can act on, not a stack trace.
class LayoutCheckTool < RubyLLM::Tool
  # Where a writer that is not converging is stopped, rather than what one
  # answer is worth spending. The sandbox names one fault at a time and a run
  # costs a millisecond, so the writer is meant to check as often as it needs
  # to — a script that has to be answered unedited is one that has to be
  # checked again after every change. This is the backstop on a model looping
  # on the same fault, and nothing here is sized by how long a reply token
  # lasts.
  ATTEMPTS = 8

  description <<~TEXT
    Run a layout script through the same sandbox that will run it for real and
    report whether it assembled a Flex Message. Call this before answering.
  TEXT

  param :script, desc: "The layout script to run, exactly as it would be answered."

  def execute(script:)
    @checks = (@checks || 0) + 1
    return spent if @checks > ATTEMPTS

    result = LineFlex.render(script)
    return "The sandbox assembled a Flex Message from this script." unless result.is_a?(LineFlex::Failure)

    guidance_for(result)
  end

  private

  # Kobako names why a run ended; what the writer needs is what to do about it,
  # and for the one failure it can actually repair — a name outside the
  # vocabulary — the vocabulary itself.
  def guidance_for(failure)
    case failure.reason
    when :no_service
      "The script called a name the sandbox does not lend. " \
        "The whole vocabulary is: #{LineFlex::VERBS.join(', ')}."
    when :timeout
      "The script never finished. A layout is assembled in one pass, so nothing may loop or wait."
    else
      "The sandbox stopped the script (#{failure.reason}): #{failure.message}"
    end
  end

  def spent
    "The sandbox has run #{ATTEMPTS} times for this message, which is as many as it will. " \
      "Answer with the best script you have."
  end
end
