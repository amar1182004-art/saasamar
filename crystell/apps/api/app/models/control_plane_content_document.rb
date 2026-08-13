class ControlPlaneContentDocument < ControlPlaneRecord
  self.table_name = "control_plane_content_documents"

  KINDS = %w[branding page navigation footer banner ad].freeze

  has_many :versions,
           class_name: "ControlPlaneContentVersion",
           dependent: :restrict_with_exception,
           inverse_of: :control_plane_content_document

  validates :key, presence: true, length: { maximum: 120 }, format: { with: /\A[a-z0-9][a-z0-9._-]{0,119}\z/ }
  validates :kind, inclusion: { in: KINDS }
  validates :locale, presence: true, length: { maximum: 16 }, format: { with: /\A[a-z]{2,3}(?:-[A-Z]{2})?\z/ }
  validates :draft_version, :published_version,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :published_version_not_ahead_of_draft
  validate :content_documents_are_objects

  private

  def published_version_not_ahead_of_draft
    return unless draft_version && published_version

    errors.add(:published_version, "cannot exceed draft version") if published_version > draft_version
  end

  def content_documents_are_objects
    errors.add(:draft_content, "must be an object") unless draft_content.is_a?(Hash)
    errors.add(:published_content, "must be an object") unless published_content.is_a?(Hash)
  end
end
