class NotificationTemplate < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  has_many :notification_deliveries, dependent: :restrict_with_exception

  normalizes :key, with: ->(value) { value.strip.downcase }
  normalizes :channel, with: ->(value) { value.strip.downcase }
  normalizes :locale, with: ->(value) { value.strip.downcase }
  normalizes :subject, with: ->(value) { value&.strip&.presence }
  normalizes :body, with: ->(value) { value.strip }

  validates :key, format: { with: /\A[a-z0-9][a-z0-9._-]{0,119}\z/ }
  validates :channel, inclusion: { in: %w[email sms whatsapp] }
  validates :locale, format: { with: /\A[a-z]{2}(?:-[a-z]{2})?\z/ }, length: { maximum: 10 }
  validates :subject, length: { maximum: 200 }, allow_nil: true
  validates :body, presence: true, length: { maximum: 20_000 }
  validates :status, inclusion: { in: %w[draft active archived] }
  validate :email_subject_is_present
  validate :variables_are_names

  private

  def email_subject_is_present
    errors.add(:subject, "is required for email templates") if channel == "email" && subject.blank?
  end

  def variables_are_names
    valid = variables.is_a?(Array) && variables.length <= 50 && variables.all? do |name|
      name.is_a?(String) && name.match?(/\A[a-z][a-z0-9_]{0,63}\z/)
    end
    errors.add(:variables, "must contain valid variable names") unless valid
  end
end
