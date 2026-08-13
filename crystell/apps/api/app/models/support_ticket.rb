class SupportTicket < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :created_by_user, class_name: "User"
  has_many :support_messages, dependent: :restrict_with_exception
  has_many :support_attachments, dependent: :restrict_with_exception

  normalizes :ticket_number, with: ->(value) { value.strip.upcase }
  normalizes :subject, with: ->(value) { value.strip }

  validates :ticket_number, presence: true, length: { maximum: 40 }
  validates :subject, presence: true, length: { in: 3..160 }
  validates :priority, inclusion: { in: %w[low normal high urgent] }
  validates :status, inclusion: { in: %w[open pending resolved closed] }
  validates :source, inclusion: { in: %w[in_app email sms whatsapp] }
end
