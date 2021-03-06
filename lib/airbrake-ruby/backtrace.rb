module Airbrake
  ##
  # Represents a cross-Ruby backtrace from exceptions (including JRuby Java
  # exceptions). Provides information about stack frames (such as line number,
  # file and method) in convenient for Airbrake format.
  #
  # @example
  #   begin
  #     raise 'Oops!'
  #   rescue
  #     Backtrace.parse($!)
  #   end
  module Backtrace
    ##
    # @return [Regexp] the pattern that matches standard Ruby stack frames,
    #   such as ./spec/notice_spec.rb:43:in `block (3 levels) in <top (required)>'
    RUBY_STACKFRAME_REGEXP = %r{\A
      (?<file>.+)       # Matches './spec/notice_spec.rb'
      :
      (?<line>\d+)      # Matches '43'
      :in\s
      `(?<function>.*)' # Matches "`block (3 levels) in <top (required)>'"
    \z}x

    ##
    # @return [Regexp] the template that matches JRuby Java stack frames, such
    #  as org.jruby.ast.NewlineNode.interpret(NewlineNode.java:105)
    JAVA_STACKFRAME_REGEXP = /\A
      (?<function>.+)  # Matches 'org.jruby.ast.NewlineNode.interpret
      \(
        (?<file>[^:]+) # Matches 'NewlineNode.java'
        :?
        (?<line>\d+)?  # Matches '105'
      \)
    \z/x

    ##
    # @return [Regexp] the template that tries to assume what a generic stack
    #   frame might look like, when exception's backtrace is set manually.
    GENERIC_STACKFRAME_REGEXP = %r{\A
      (?<file>.+)              # Matches '/foo/bar/baz.ext'
      :
      (?<line>\d+)?            # Matches '43' or nothing
      (in\s`(?<function>.+)')? # Matches "in `func'" or nothing
    \z}x

    ##
    # Parses an exception's backtrace.
    #
    # @param [Exception] exception The exception, which contains a backtrace to
    #   parse
    # @return [Array<Hash{Symbol=>String,Integer}>] the parsed backtrace
    def self.parse(exception)
      return [] if exception.backtrace.nil? || exception.backtrace.none?

      regexp = if java_exception?(exception)
                 JAVA_STACKFRAME_REGEXP
               else
                 RUBY_STACKFRAME_REGEXP
               end

      exception.backtrace.map do |stackframe|
        stack_frame(match_frame(regexp, stackframe))
      end
    end

    ##
    # Checks whether the given exception was generated by JRuby's VM.
    #
    # @param [Exception] exception
    # @return [Boolean]
    def self.java_exception?(exception)
      defined?(Java::JavaLang::Throwable) &&
        exception.is_a?(Java::JavaLang::Throwable)
    end

    class << self
      private

      def stack_frame(match)
        { file: match[:file],
          line: (Integer(match[:line]) if match[:line]),
          function: match[:function] }
      end

      def match_frame(regexp, stackframe)
        match = regexp.match(stackframe)
        return match if match

        match = GENERIC_STACKFRAME_REGEXP.match(stackframe)
        return match if match

        raise Airbrake::Error, "can't parse '#{stackframe}'"
      end
    end
  end
end
