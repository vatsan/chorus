class InstanceAccount < ActiveRecord::Base
  attr_accessor :legacy_migrate

  attr_accessible :db_username, :db_password, :owner
  validate :credentials_are_valid, :unless => :legacy_migrate
  validates_presence_of :db_username, :db_password, :data_source, :owner
  validates_uniqueness_of :owner_id, :scope => :data_source_id

  attr_encrypted :db_password, :encryptor => ChorusEncryptor, :encrypt_method => :encrypt_password, :decrypt_method => :decrypt_password, :encode => false

  has_many :instance_account_permissions, dependent: :destroy
  has_many :accesseds, :through => :instance_account_permissions
  has_many :gpdb_databases, :through => :instance_account_permissions, :source => :accessed,
           :conditions => "instance_account_permissions.accessed_type = 'GpdbDatabase'"

  belongs_to :owner, :class_name => 'User'
  belongs_to :data_source

  after_save :reindex_data_source
  after_destroy :reindex_data_source
  after_destroy { instance_account_permissions.clear }

  def reindex_data_source
    data_source.refresh_databases_later
  end

  private

  def credentials_are_valid
    association = association(:data_source)
    if association.loaded?
      association.loaded! if association.stale_target?
    end
    return unless data_source && db_username.present? && db_password.present?
    unless data_source.valid_db_credentials?(self)
      errors.add(:base, :INVALID_PASSWORD)
    end
  end
end
