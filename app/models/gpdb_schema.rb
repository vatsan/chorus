require 'greenplum_connection'

class GpdbSchema < Schema
  include Stale
  include SoftDelete

  attr_accessible :database
  alias_attribute :parent, :database

  belongs_to :database, {
      :polymorphic => true,
      :foreign_key => 'parent_id',
      :foreign_type => 'parent_type',
      :class_name => 'GpdbDatabase'
  }

  def active_tables_and_views
    super.where("type != 'ChorusView'")
  end

  has_many :workspaces, :foreign_key => :sandbox_id, :dependent => :nullify
  has_many :imports, class_name: 'SchemaImport', foreign_key: 'schema_id'

  has_many :workfiles_as_execution_schema, :class_name => 'Workfile', :foreign_key => :execution_schema_id, :dependent => :nullify
  has_many :views, :source => :datasets, :class_name => 'GpdbView', :foreign_key => :schema_id
  has_many :tables, :source => :datasets, :class_name => 'GpdbTable', :foreign_key => :schema_id

  validates :name, :format => /^[^\/?&]*$/

  delegate :data_source, :account_for_user!, :to => :database

  before_save :mark_schemas_as_stale

  def stored_functions(account)
    results = connect_with(account).functions

    #This would be a lot easier if the schema_function_query could use ARRAY_AGG,
    #but it is not available on GPDB 4.0

    reduced_results = results.reduce [-1, []] do |last, result|
      record = result.values
      last_record_id = last[0]
      functions = last[1]
      current_function = functions.last
      current_function_types = current_function[5] if current_function
      arg_type = record[5]

      if current_function and record[0] == last_record_id
        current_function_types << arg_type
      else
        record[5] = [arg_type]
        functions << record
      end

      [record[0], last[1]]
    end

    reduced_results.last.map do |record|
      GpdbSchemaFunction.new(name, *record[1..7])
    end
  end

  def disk_space_used(account)
    @disk_space_used ||= connect_with(account).disk_space_used
    @disk_space_used == :error ? nil : @disk_space_used
  rescue Exception => e
    @disk_space_used = :error
    raise e if (e.respond_to?(:error_type) && e.error_type == :INVALID_PASSWORD)
    nil
  end

  def connect_with(account, &block)
    database.connect_with account, { :schema => name }, &block
  end

  def class_for_type(type)
    type == 'r' ? GpdbTable : GpdbView
  end

  private

  def mark_schemas_as_stale
    if stale? && stale_at_changed?
      datasets.each do |dataset|
        dataset.mark_stale! unless dataset.type == "ChorusView"
      end
    end
  end
end
