class User < ApplicationRecord
  has_secure_password validations: false

  has_many :memberships, dependent: :destroy
  has_many :tenants, through: :memberships
  has_many :sessions, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: %w[active invited suspended] }
  validates :password, length: { minimum: 12 }, allow_nil: true
end
