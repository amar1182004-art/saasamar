class Category < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :parent, class_name: "Category", optional: true

  has_many :children, class_name: "Category", foreign_key: :parent_id, dependent: :restrict_with_exception, inverse_of: :parent
  has_many :product_category_assignments, dependent: :delete_all
  has_many :products, through: :product_category_assignments

  normalizes :name, with: ->(value) { value.strip }
  normalizes :slug, with: ->(value) { value.strip.downcase }

  validates :name, presence: true
  validates :slug, presence: true
  validates :status, inclusion: { in: %w[active archived] }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validate :parent_is_not_self

  private

  def parent_is_not_self
    errors.add(:parent_id, "cannot reference itself") if parent_id.present? && parent_id == id
  end
end
