# frozen_string_literal: true

require "jekyll"
require "html/pipeline"

module Jekyll
  class Mentions
    GITHUB_DOT_COM = "https://github.com"
    BODY_START_TAG = "<body"

    OPENING_BODY_TAG_REGEX = %r!<body(.*?)>\s*!m.freeze

    InvalidJekyllMentionConfig = Class.new(Jekyll::Errors::FatalException)

    class << self
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def mentionify(doc)
        people = doc.data['people']
        content = doc.output
        return unless content.include?("@")

        config = doc.site.config
        config = config.merge(doc.data) if doc.data.key?("jekyll-mentions")

        src = mention_base(config)

        if content.include? BODY_START_TAG
          head, opener, tail  = content.partition(OPENING_BODY_TAG_REGEX)
          body_content, *rest = tail.partition("</body>")

          return unless body_content&.match?(filter_regex)

          filtered = filter_with_mention(src)
          called = filtered.call(body_content)
          if people == nil
            doc.data['people'] == called[:mentioned_usernames]
          else
            for mention in called[:mentioned_usernames]
              people.append(mention) unless people.include?(mention)
            end
            doc.data['people'] = people
          end
          processed_markup = called[:output].to_s
          doc.output       = String.new(head) << opener << processed_markup << rest.join
        else
          return unless content&.match?(filter_regex)

          doc.data['people'] = people
          doc.output = filter_with_mention(src).call(content)[:output].to_s
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Public: Find al lthe mentions in the doc and add it to
      # doc.data['mentions']
      def pre_render(doc, payload)
        if doc.content == nil
          return
        end
        found_mentions = doc.content.scan(/\s@(\w+)/)
        if found_mentions.empty?
          return
        end

        mentions = payload['page']['mentions']
        if mentions == nil
          mentions = []
        end

        for mention in found_mentions
          mentions.append(mention[0]) unless mentions.include?(mention[0])
        end
        payload['page']['mentions'] = mentions
      end

      # Public: Create or fetch the filter for the given {{src}} base URL.
      #
      # src - the base URL (e.g. https://github.com)
      #
      # Returns an HTML::Pipeline instance for the given base URL.
      def filter_with_mention(src)
        filters[src] ||= HTML::Pipeline.new([
          HTML::Pipeline::MentionFilter,
        ], :base_url => src, :username_pattern => mention_username_pattern)
      end

      def mention_username_pattern
        @mention_username_pattern ||= %r!\w[\w-]*!
      end

      # Public: Filters hash where the key is the mention base URL.
      # Effectively a cache.
      def filters
        @filters ||= {}
      end

      # Public: Calculate the base URL to use for mentioning.
      #
      # The custom base URL can be defined \in either the site config or a document's
      # front matter as `jekyll-mentions.base_url` or `jekyll-mentions`, and must be
      # a valid URL (i.e. it must include a protocol and valid domain).
      # It should _not_ have a trailing slash.
      #
      # config - The effective configuration that includes configurations for mentions.
      #
      # Returns a URL to use as the base URL for mentions.
      # Defaults to the https://github.com.
      def mention_base(config = {})
        mention_config = config["jekyll-mentions"]
        case mention_config
        when nil, NilClass
          default_mention_base
        when String
          mention_config.to_s
        when Hash
          mention_config.fetch("base_url", default_mention_base)
        else
          raise InvalidJekyllMentionConfig,
                "Your jekyll-mentions config has to either be a string or a hash. " \
                "It's a #{mention_config.class} right now."
        end
      end

      # Public: Defines the conditions for a document to be mentionable.
      #
      # doc - the Jekyll::Document or Jekyll::Page
      #
      # Returns true if the doc is written & is HTML.
      def mentionable?(doc)
        (doc.is_a?(Jekyll::Page) || doc.write?) &&
          (doc.output_ext == ".html" || doc.permalink&.end_with?("/")) &&
          (doc.data["jekyll-mentions"] != false)
      end

      private

      def filter_regex
        @filter_regex ||=
          begin
            Regexp.new(
              HTML::Pipeline::MentionFilter::MentionPatterns[mention_username_pattern]
            )
          rescue TypeError
            %r!@\w+!
          end
      end

      def default_mention_base
        if !ENV["SSL"].to_s.empty? && !ENV["GITHUB_HOSTNAME"].to_s.empty?
          scheme = ENV["SSL"] == "true" ? "https://" : "http://"
          "#{scheme}#{ENV["GITHUB_HOSTNAME"].chomp("/")}"
        else
          GITHUB_DOT_COM
        end
      end
    end
  end

end

module Mentions
  class Generator < Jekyll::Generator
    def generate(site)
      docs = site.posts.docs

      docs.each do | doc |
        found_mentions = doc.content.scan(/\s@(\w+)/).map{ | mention | mention[0] }
        if found_mentions.empty?
          next
        end
        mentions = doc.data['mentions'] || []
        mentions.concat(found_mentions.uniq)
        doc.data['mentions'] = mentions.uniq
      end
          
    end
  end
end

Jekyll::Hooks.register [:pages, :documents], :post_render do |doc|
  Jekyll::Mentions.mentionify(doc) if Jekyll::Mentions.mentionable?(doc)
end
