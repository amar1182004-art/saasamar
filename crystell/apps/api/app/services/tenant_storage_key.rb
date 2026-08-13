require "digest"

class TenantStorageKey
  class InvalidPathError < StandardError; end

  SAFE_SEGMENT = /\A[a-zA-Z0-9._-]+\z/
  ALLOWED_CATEGORIES = %w[products branding documents contracts support exports].freeze

  def self.build(tenant_id:, store_id:, category:, object_id:, filename:)
    tenant = segment!(tenant_id, "tenant_id")
    store = segment!(store_id, "store_id")
    category = category.to_s
    raise InvalidPathError, "invalid category" unless ALLOWED_CATEGORIES.include?(category)

    object = segment!(object_id, "object_id")
    safe_filename = sanitize_filename(filename)

    "tenants/#{tenant}/stores/#{store}/#{category}/#{object}/#{safe_filename}"
  end

  def self.segment!(value, name)
    segment = value.to_s
    raise InvalidPathError, "#{name} is required" if segment.blank?
    raise InvalidPathError, "#{name} contains unsafe characters" unless segment.match?(SAFE_SEGMENT)

    segment
  end
  private_class_method :segment!

  def self.sanitize_filename(filename)
    original = File.basename(filename.to_s)
    raise InvalidPathError, "filename is required" if original.blank? || original == "."

    extension = File.extname(original).downcase.gsub(/[^a-z0-9.]/, "")
    stem = File.basename(original, File.extname(original)).gsub(/[^a-zA-Z0-9._-]/, "-").gsub(/-+/, "-")
    stem = "file" if stem.blank?
    digest = Digest::SHA256.hexdigest(original)[0, 12]
    "#{stem.first(80)}-#{digest}#{extension.first(16)}"
  end
  private_class_method :sanitize_filename
end
