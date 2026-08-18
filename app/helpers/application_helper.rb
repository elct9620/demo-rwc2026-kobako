module ApplicationHelper
  # The script is written by an LLM and is never trusted, so it reaches the page
  # as markup only because Rouge escapes every value it lexes — a script holding
  # `<script>` comes back as `&lt;script&gt;`. That escaping is the whole of why
  # this may be marked safe; nothing here re-checks the string itself.
  #
  # Rouge's HTML formatter emits the spans alone and no wrapper, so the element
  # the block is drawn in stays the view's to choose.
  def highlighted(script)
    formatter = Rouge::Formatters::HTML.new
    lexer = Rouge::Lexers::Ruby.new

    formatter.format(lexer.lex(script.to_s)).html_safe
  end
end
