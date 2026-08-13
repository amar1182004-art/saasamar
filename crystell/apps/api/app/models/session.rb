class Session < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def active?
    revoked_at.nil? && expires_at.future?
  end
end
