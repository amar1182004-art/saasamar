class MfaCredential < ApplicationRecord
  belongs_to :user

  validates :encrypted_secret, presence: true
  validates :user_id, uniqueness: true

  def confirmed?
    confirmed_at.present?
  end
end
