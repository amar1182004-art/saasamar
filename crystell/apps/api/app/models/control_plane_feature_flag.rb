class ControlPlaneFeatureFlag < ControlPlaneRecord
  self.table_name = "control_plane_feature_flags"

  validates :key, presence: true, uniqueness: true, length: { maximum: 120 }, format: { with: /\A[a-z0-9][a-z0-9._-]{0,119}\z/ }
  validates :rollout_percentage,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :config_is_object

  private

  def config_is_object
    errors.add(:config, "must be an object") unless config.is_a?(Hash)
  end
end
