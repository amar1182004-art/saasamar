class StorefrontConfiguration < ApplicationRecord
  belongs_to :tenant
  belongs_to :store

  validates :status, inclusion: { in: %w[offline online] }
  validates :draft_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :published_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :configuration_documents_are_objects

  private

  def configuration_documents_are_objects
    errors.add(:draft_config, "must be an object") unless draft_config.is_a?(Hash)
    errors.add(:published_config, "must be an object") unless published_config.is_a?(Hash)
  end
end
