# frozen_string_literal: true
require "sanscript/version"
require "sanscript/refinements"
require "sanscript/schemes"
require "sanscript/detect"

#
# Sanscript
#
# Sanscript is a Sanskrit transliteration library. Currently, it supports
# other Indian languages only incidentally.
#
# Released under the MIT and GPL Licenses.
#
module Sanscript
  using Refinements

  @defaults = {
    skip_sgml: false,
    syncope: false,
  }

  # Schemes and alternates are found in sanscript/schemes.rb

  # object cache
  @cache = {}

  module_function

  #
  #  Check whether the given scheme encodes romanized Sanskrit.
  #
  #  @param name  the scheme name
  #  @return      boolean
  #
  def roman_scheme?(name)
    @roman_schemes.include?(name.to_sym)
  end

  #
  # Add a Brahmic scheme to Sanscript.
  #
  # Schemes are of two types: "Brahmic" and "roman". Brahmic consonants
  # have an inherent vowel sound, but roman consonants do not. This is the
  # main difference between these two types of scheme.
  #
  # A scheme definition is an object ("{}") that maps a group name to a
  # list of characters. For illustration, see the "devanagari" scheme at
  # the top of this file.
  #
  # You can use whatever group names you like, but for the best results,
  # you should use the same group names that Sanscript does.
  #
  # @param name    the scheme name
  # @param scheme  the scheme data itself. This should be constructed as
  #                described above.
  #
  def add_brahmic_scheme(name, scheme)
    @schemes[name.to_sym] = scheme.deep_dup.deep_freeze
  end

  #
  # Add a roman scheme to Sanscript.
  #
  # See the comments on Sanscript.add_brahmic_scheme. The "vowel_marks" field
  # can be omitted.
  #
  # @param name    the scheme name
  # @param scheme  the scheme data itself
  #
  def add_roman_scheme(name, scheme)
    name = name.to_sym
    scheme = scheme.deep_dup
    scheme[:vowel_marks] = scheme[:vowels][1..-1] unless scheme.key?(:vowel_marks)
    @schemes[name] = scheme.deep_freeze
    @roman_schemes.add(name)
  end

  #
  # Create a deep copy of an object, for certain kinds of objects.
  #
  # @param scheme  the scheme to copy
  # @return        the copy
  #

  # Set up various schemes
  begin
    # Set up roman schemes
    kolkata = @schemes[:kolkata] = @schemes[:iast].deep_dup
    scheme_names = %i[iast itrans hk kolkata slp1 velthuis wx]
    kolkata[:vowels] = %w[a ā i ī u ū ṛ ṝ ḷ ḹ e ē ai o ō au]

    # These schemes already belong to Sanscript.schemes. But by adding
    # them again with `addRomanScheme`, we automatically build up
    # `roman_schemes` and define a `vowel_marks` field for each one.
    scheme_names.each do |name|
      add_roman_scheme(name, @schemes[name])
    end

    # ITRANS variant, which supports Dravidian short 'e' and 'o'.
    itrans_dravidian = @schemes[:itrans].deep_dup
    itrans_dravidian[:vowels] = %w[a A i I u U Ri RRI LLi LLi e E ai o O au]
    itrans_dravidian[:vowel_marks] = itrans_dravidian[:vowels][1..-1]
    @all_alternates[:itrans_dravidian] = @all_alternates[:itrans]
    add_roman_scheme(:itrans_dravidian, itrans_dravidian)

    # ensure deep freeze on all existing schemes and alternates
    @schemes.each { |_, scheme| scheme.deep_freeze }
    @all_alternates.each { |_, scheme| scheme.deep_freeze }
  end

  # /**
  # Transliterate from one script to another.
  #  *
  # @param data     the string to transliterate
  # @param from     the source script
  # @param to       the destination script
  # @param options  transliteration options
  # @return         the finished string
  #
  def transliterate(data, from, to, options = {})
    data = data.to_str.dup
    from = from.to_sym
    to = to.to_sym
    options = @defaults.merge(options)
    map = @cache[:"#{from}_#{to}"] ||= make_map(from, to)

    data.gsub!(/(<.*?>)/, "##\\1##") if options[:skip_sgml]

    # Easy way out for "{\m+}", "\", and ".h".
    if from == :itrans
      data.gsub!(/\{\\m\+\}/, ".h.N")
      data.gsub!(/\.h/, "")
      data.gsub!(/\\([^'`_]|$)/, "##\\1##")
    end

    if map[:from_roman?]
      transliterate_roman(data, map, options)
    else
      transliterate_brahmic(data, map)
    end
  end

  def detect(text)
    Detect.detect_script(text)
  end
  alias detect_script detect

  class << self
    attr_reader :defaults, :schemes, :roman_schemes, :all_alternates
    alias t transliterate

    private

    #
    # Create a map from every character in `from` to its partner in `to`.
    # Also, store any "marks" that `from` might have.
    #
    # @param from     input scheme
    # @param to       output scheme
    #
    def make_map(from, to)
      alternates = @all_alternates[from] || {}
      consonants = {}
      from_scheme = @schemes[from]
      letters = {}
      token_lengths = []
      marks = {}
      to_scheme = @schemes[to]

      from_scheme.each do |group, from_group|
        to_group = to_scheme[group]
        next if to_group.nil?

        from_group.each_with_index do |f, i|
          t = to_group[i]
          alts = alternates[f] || []
          token_lengths.push(f.length)
          token_lengths.concat(alts.map(&:length))

          if group == :vowel_marks || group == :virama
            marks[f] = t
            alts.each { |alt| marks[alt] = t }
          else
            letters[f] = t
            alts.each { |alt| letters[alt] = t }

            if group == :consonants || group == :other
              consonants[f] = t
              alts.each { |alt| consonants[alt] = t }
            end
          end
        end
      end

      {
        consonants: consonants,
        from_roman?: roman_scheme?(from),
        letters: letters,
        marks: marks,
        max_token_length: token_lengths.max,
        to_roman?: roman_scheme?(to),
        virama: to_scheme[:virama].first,
      }.deep_freeze
    end

    #
    # Transliterate from a romanized script.
    #
    # @param data     the string to transliterate
    # @param map      map data generated from makeMap()
    # @param options  transliteration options
    # @return         the finished string
    #
    def transliterate_roman(data, map, options = {})
      options = @defaults.merge(options)
      data = data.to_str.dup
      buf = String.new
      token_buffer = String.new
      had_consonant = false
      transliteration_enabled = true

      until data.empty? && token_buffer.empty?
        token_buffer << data.slice!(0, map[:max_token_length] - token_buffer.length)

        # Match all token substrings to our map.
        (0...map[:max_token_length]).each do |j|
          token = token_buffer[0, map[:max_token_length] - j]

          if token == "##"
            transliteration_enabled = !transliteration_enabled
            token_buffer.slice!(0, 2)
            break
          end
          temp_letter = map[:letters][token]
          if !temp_letter.nil? && transliteration_enabled
            if map[:to_roman?]
              buf << temp_letter
            else
              # Handle the implicit vowel. Ignore 'a' and force
              # vowels to appear as marks if we've just seen a
              # consonant.
              if had_consonant
                temp_mark = map[:marks][token]
                if !temp_mark.nil?
                  buf << temp_mark
                elsif token != "a"
                  buf << map[:virama] << temp_letter
                end
              else
                buf << temp_letter
              end
              had_consonant = map[:consonants].key?(token)
            end
            token_buffer.slice!(0, map[:max_token_length] - j)
            break
          elsif j == map[:max_token_length] - 1
            if had_consonant
              had_consonant = false
              buf << map[:virama] unless options[:syncope]
            end
            buf << token
            token_buffer.slice!(0, 1)
            # 'break' is redundant here, "j == ..." is true only on
            # the last iteration.
          end
        end
      end
      buf << map[:virama] if had_consonant && !options[:syncope]
      buf
    end

    #
    # Transliterate from a Brahmic script.
    #
    # @param data     the string to transliterate
    # @param map      map data generated from makeMap()
    # @return         the finished string
    #
    def transliterate_brahmic(data, map)
      data = data.to_str.dup
      buf = String.new
      dangling_hash = false
      had_roman_consonant = false
      transliteration_enabled = true

      until data.empty?
        l = data.slice!(0, 1)
        # Toggle transliteration state
        if l == "#"
          if dangling_hash
            transliteration_enabled = !transliteration_enabled
            dangling_hash = false
          else
            dangling_hash = true
          end
          if had_roman_consonant
            buf << "a"
            had_roman_consonant = false
          end
          next
        elsif !transliteration_enabled
          buf << l
          next
        end

        temp = map[:marks][l]
        if !temp.nil?
          buf << temp
          had_roman_consonant = false
        else
          if dangling_hash
            buf << "#"
            dangling_hash = false
          end
          if had_roman_consonant
            buf << "a"
            had_roman_consonant = false
          end

          # Push transliterated letter if possible. Otherwise, push
          # the letter itself.
          temp = map[:letters][l]
          if !temp.nil?
            buf << temp
            had_roman_consonant = map[:to_roman?] && map[:consonants].key?(l)
          else
            buf << l
          end
        end
      end

      buf << "a" if had_roman_consonant
      buf
    end
  end
end
