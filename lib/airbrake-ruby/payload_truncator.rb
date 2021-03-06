module Airbrake
  ##
  # This class is responsible for truncation of too big objects. Mainly, you
  # should use it for simple objects such as strings, hashes, & arrays.
  class PayloadTruncator
    ##
    # @return [Hash] the options for +String#encode+
    ENCODING_OPTIONS = { invalid: :replace, undef: :replace }.freeze

    ##
    # @return [String] the temporary encoding to be used when fixing invalid
    #   strings with +ENCODING_OPTIONS+
    TEMP_ENCODING = (RUBY_VERSION == '1.9.2' ? 'iso-8859-1' : 'utf-16')

    ##
    # @param [Integer] max_size maximum size of hashes, arrays and strings
    # @param [Logger] logger the logger object
    def initialize(max_size, logger)
      @max_size = max_size
      @logger = logger
    end

    ##
    # Truncates errors (not exceptions) to fit the limit.
    #
    # @param [Hash] error
    # @option error [Symbol] :message
    # @option error [Array<String>] :backtrace
    # @return [void]
    def truncate_error(error)
      if error[:message].length > @max_size
        error[:message] = truncate_string(error[:message])
        @logger.info("#{LOG_LABEL} truncated the message of #{error[:type]}")
      end

      return if (dropped_frames = error[:backtrace].size - @max_size) < 0

      error[:backtrace] = error[:backtrace].slice(0, @max_size)
      @logger.info("#{LOG_LABEL} dropped #{dropped_frames} frame(s) from #{error[:type]}")
    end

    ##
    # Performs deep truncation of arrays, hashes and sets. Uses a
    # placeholder for recursive objects (`[Circular]`).
    #
    # @param [Hash,Array] object The object to truncate
    # @param [Hash] seen The hash that helps to detect recursion
    # @return [void]
    def truncate_object(object, seen = {})
      return seen[object] if seen[object]

      seen[object] = '[Circular]'.freeze
      truncated = if object.is_a?(Hash)
                    truncate_hash(object, seen)
                  elsif object.is_a?(Array)
                    truncate_array(object, seen)
                  elsif object.is_a?(Set)
                    truncate_set(object, seen)
                  else
                    raise Airbrake::Error,
                          "cannot truncate object: #{object} (#{object.class})"
                  end
      seen[object] = truncated
    end

    ##
    # Reduces maximum allowed size of the truncated object.
    # @return [void]
    def reduce_max_size
      @max_size /= 2
    end

    private

    def truncate(val, seen)
      case val
      when String
        truncate_string(val)
      when Array, Hash, Set
        truncate_object(val, seen)
      when Numeric, TrueClass, FalseClass, Symbol, NilClass
        val
      else
        stringified_val = begin
                            val.to_json
                          rescue *Notice::JSON_EXCEPTIONS
                            val.to_s
                          end
        truncate_string(stringified_val)
      end
    end

    def truncate_string(str)
      replace_invalid_characters!(str)
      return str if str.length <= @max_size
      str.slice(0, @max_size) + '[Truncated]'.freeze
    end

    ##
    # Replaces invalid characters in string with arbitrary encoding.
    #
    # For Ruby 1.9.2 the method converts encoding of +str+ to +iso-8859-1+ to
    # avoid a bug when encoding options are no-op, when `#encode` is given the
    # same encoding as the receiver's encoding.
    #
    # For modern Rubies we use UTF-16 as a safe alternative.
    #
    # @param [String] str The string to replace characters
    # @return [void]
    # @note This method mutates +str+ for speed
    # @see https://github.com/flori/json/commit/3e158410e81f94dbbc3da6b7b35f4f64983aa4e3
    def replace_invalid_characters!(str)
      encoding = str.encoding
      utf8_string = (encoding == Encoding::UTF_8 || encoding == Encoding::ASCII)
      return str if utf8_string && str.valid_encoding?

      str.encode!(TEMP_ENCODING, ENCODING_OPTIONS) if utf8_string
      str.encode!('utf-8', ENCODING_OPTIONS)
    end

    def truncate_hash(hash, seen)
      hash.each_with_index do |(key, val), idx|
        if idx < @max_size
          hash[key] = truncate(val, seen)
        else
          hash.delete(key)
        end
      end
    end

    def truncate_array(array, seen)
      array.slice(0, @max_size).map! { |val| truncate(val, seen) }
    end

    def truncate_set(set, seen)
      set.keep_if.with_index { |_val, idx| idx < @max_size }.map! do |val|
        truncate(val, seen)
      end
    end
  end
end
