class Schema < ActiveRecord::Base
  attr_accessible :name, :type
  belongs_to :parent, :polymorphic => true
  has_many :datasets, :foreign_key => :schema_id, :dependent => :destroy
  delegate :accessible_to, :to => :parent

  def active_tables_and_views
    datasets.where(:stale_at => nil)
  end

  validates :name,
            :presence => true,
            :uniqueness => { :scope => [:parent_type, :parent_id] }

  def self.find_and_verify_in_source(schema_id, user)
    schema = find(schema_id)
    raise ActiveRecord::RecordNotFound unless schema.verify_in_source(user)
    schema
  end

  def self.refresh(account, schema_parent, options = {})
    found_schemas = []

    schema_parent.connect_with(account).schemas.each do |name|
      schema = schema_parent.schemas.find_or_initialize_by_name(name)
      next if schema.invalid?
      schema.stale_at = nil
      schema.save!
      Dataset.refresh(account, schema, options) if options[:refresh_all]
      found_schemas << schema
    end

    found_schemas
  rescue DataSourceConnection::Error => e
    Chorus.log_error "Could not refresh schemas: #{e.message} on #{e.backtrace[0]}"
    return []
  ensure
    if options[:mark_stale]
      (schema_parent.schemas.not_stale - found_schemas).each do |schema|
        schema.mark_stale!
      end
    end
  end

  def self.visible_to(*args)
    refresh(*args)
  end

  def verify_in_source(user)
    parent.connect_as(user).schema_exists?(name)
  end

  def connect_as(user, &block)
    connect_with(data_source.account_for_user!(user), &block)
  end

  def refresh_datasets(account, options = {})
    found_datasets = []
    mark_stale = options.delete(:mark_stale)
    force_index = options.delete(:force_index)
    datasets_in_data_source = connect_with(account).datasets(options)

    datasets_in_data_source.each do |attrs|
      klass = class_for_type attrs.delete(:type)
      dataset = klass.find_or_initialize_by_name_and_schema_id(attrs[:name], id)
      attrs.merge!(:stale_at => nil) if dataset.stale?
      dataset.assign_attributes(attrs, :without_protection => true)
      begin
        dataset.skip_search_index = true if options[:skip_dataset_solr_index]
        if dataset.changed?
          dataset.save!
        elsif force_index
          dataset.index
        end
        found_datasets << dataset
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, DataSourceConnection::QueryError
      end
    end

    touch(:refreshed_at)

    if mark_stale
      raise "You should not use mark_stale and limit at the same time" if options[:limit]
      (datasets.not_stale - found_datasets).each do |dataset|
        dataset.mark_stale! unless dataset.is_a? ChorusView
      end
    end

    self.active_tables_and_views_count = active_tables_and_views.count
    save!

    found_datasets
  rescue DataSourceConnection::Error
    touch(:refreshed_at)
    found_datasets
  end

  def dataset_count(account, options={})
    connect_with(account).datasets_count options
  end
end