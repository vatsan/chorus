require 'spec_helper'

resource "Greenplum Tables / Views" do
  let(:dataset) { datasets(:table) }
  let(:owner) { users(:owner) }

  let(:owner_account) { dataset.gpdb_instance.owner_account }
  let(:dataset_id) { dataset.id }
  let!(:statistics) { FactoryGirl.build(:dataset_statistics) }

  let(:result) do
    SqlResult.new.tap do |r|
      r.add_column("column_1", "integer")
      r.add_column("column_2", "double")
      r.add_rows([
        [1, 2.0],
        [5, 2.5]
      ])
    end
  end

  before do
    log_in owner
    stub(SqlExecutor).preview_dataset { result }
    stub(GpdbColumn).columns_for.with_any_args { [FactoryGirl.build(:gpdb_column), FactoryGirl.build(:gpdb_column)] }
    any_instance_of(Dataset) do |dataset|
      stub(dataset).verify_in_source
      stub(dataset).add_metadata!.with_any_args { statistics }
      stub(dataset).statistics.with_any_args { statistics }
    end

    stub(SqlExecutor).cancel_query.with_any_args { status }
  end

  get "/datasets/:id" do
    let(:id) { dataset.id }
    example_request "Display a dataset" do
      status.should == 200
    end
  end

  post "/datasets/:dataset_id/previews" do
    parameter :dataset_id, "Table / View ID"
    parameter :check_id, "An identifier (generated by the client) which can be used to cancel this preview later"
    required_parameters :dataset_id, :check_id

    scope_parameters :task, [:check_id]

    let(:check_id) { '42' }

    example_request "Preview 100 rows" do
      status.should == 201
    end
  end

  delete "/datasets/:dataset_id/previews/:id" do
    parameter :dataset_id, "Table / View ID"
    parameter :id, "A check-id identifier (generated by the client) which can be used to cancel this preview later"

    let(:id) { "12345" }

    example_request "Cancel a preview task on a dataset" do
      status.should == 200
    end
  end

  get "/datasets/:dataset_id/activities" do
    example_request "Get all activities for specified dataset" do
      status.should == 200
    end
  end

  get "/datasets/:dataset_id/columns" do
    example_request "Get all columns for specified dataset" do
      status.should == 200
    end
  end

  get "/datasets/:dataset_id/statistics" do
    example_request "Get statistics for specified dataset" do
      status.should == 200
    end
  end

  get "/datasets/:dataset_id/download" do
    parameter :row_limit, "Optional number of rows"

    let(:row_limit) { 100 }

    example_request "Download a dataset as CSV file" do
      status.should == 200
    end
  end

end
