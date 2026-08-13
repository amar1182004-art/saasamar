class ProductCategoryAssignment < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :product
  belongs_to :category

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
