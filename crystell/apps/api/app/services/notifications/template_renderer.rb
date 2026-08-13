module Notifications
  class TemplateRenderer
    class InvalidTemplateError < StandardError; end

    PLACEHOLDER = /\{\{\s*([a-z][a-z0-9_]{0,63})\s*\}\}/
    Result = Data.define(:subject, :body)

    def self.call(template:, variables:)
      source = variables.respond_to?(:to_unsafe_h) ? variables.to_unsafe_h : variables
      raise InvalidTemplateError, "template variables must be an object" unless source.is_a?(Hash)

      values = source.deep_stringify_keys
      allowed = Array(template.variables)
      unknown = values.keys - allowed
      missing = allowed - values.keys
      raise InvalidTemplateError, "template variables are missing: #{missing.join(', ')}" if missing.any?
      raise InvalidTemplateError, "template variables are not allowed: #{unknown.join(', ')}" if unknown.any?

      normalized = values.transform_values do |value|
        text = value.to_s
        raise InvalidTemplateError, "template variable is too long" if text.length > 1_000

        text
      end
      subject = render_text(template.subject, allowed, normalized)
      body = render_text(template.body, allowed, normalized)
      Result.new(subject: subject, body: body)
    end

    def self.render_text(text, allowed, values)
      return if text.nil?

      placeholders = text.scan(PLACEHOLDER).flatten.uniq
      undeclared = placeholders - allowed
      raise InvalidTemplateError, "template uses undeclared variables" if undeclared.any?

      text.gsub(PLACEHOLDER) { values.fetch(Regexp.last_match(1)) }
    end
    private_class_method :render_text
  end
end
