class Integration < ApplicationRecord
  belongs_to :account
  has_many :transactions # rubocop:disable Rails/HasManyOrHasOneDependent
  has_many :schedulers # rubocop:disable Rails/HasManyOrHasOneDependent

  validates :account_id, :state, :vendor, :license, :eod, presence: true
  validates :facility_id, presence: true, numericality: { only_integer: true, greater_than: 0 }

  before_save { self.vendor.downcase! } # rubocop:disable Style/RedundantSelf
  before_create :set_activated_at

  # TODO: enable this when acts_as_paranoid supports AR +6.0
  # acts_as_paranoid
  scope :active, -> { where(deleted_at: nil) }
  scope :inactive, -> { where.not(deleted_at: nil) }

  def vendor_name
    vendor.capitalize
  end

  def vendor_module
    "#{vendor.camelize}Service".constantize
  end

  private

  def set_activated_at
    # in testing environments activated_at is already set via factory.
    self.activated_at ||= created_at
  end
end
