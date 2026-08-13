class ControlPlaneContentVersion < ControlPlaneRecord
  self.table_name = "control_plane_content_versions"

  belongs_to :control_plane_content_document, inverse_of: :versions
  belongs_to :control_plane_user

  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :control_plane_content_document_id }
  validates :source, inclusion: { in: %w[draft rollback] }
  validate :content_is_object

  private

  def content_is_object
    errors.add(:content, "must be an object") unless content.is_a?(Hash)
  end
end
