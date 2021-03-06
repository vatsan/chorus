require 'spec_helper'

describe Schema do
  let(:user) { users(:owner) }
  let(:schema) { schemas(:public) }

  describe ".find_and_verify_in_source" do
    let(:parent) { schema.parent }
    let(:connection) { Object.new }

    before do
      mock(parent).connect_as(anything) { connection }
      stub(Schema).find(schema.id) { schema }
    end

    context "when it exists in the source database" do
      before do
        mock(connection).schema_exists?(anything) { true }
      end

      it "returns the schema" do
        described_class.find_and_verify_in_source(schema.id, user).should == schema
      end
    end

    context "when it does not exist in the source database" do
      before do
        mock(connection).schema_exists?(anything) { false }
      end

      it "should raise ActiveRecord::RecordNotFound exception" do
        expect {
          described_class.find_and_verify_in_source(schema.id, user)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "#verify_in_source" do
    let(:connection) { Object.new }
    it "calls #schema_exists? on its parent's connection" do
      mock(schema.parent).connect_as(user) { connection }
      mock(connection).schema_exists?(schema.name) { "goober" }

      schema.verify_in_source(user).should == 'goober'
    end
  end

  describe "#refresh_datasets" do
    let(:connection) { Object.new }
    let(:options) { {} }
    let(:account) { "foo" }
    let(:dataset) { datasets(:table) }
    let(:schema) { dataset.schema }

    before do
      stub(schema).connect_with(account) { connection }
      mock(connection).datasets(options).at_least(1) { found_datasets.map(&:clone) }
    end

    context "refresh once, without mark_stale flag" do
      let(:found_datasets) do
        [
            {:type => "r", :name => dataset.name, :master_table => 't'},
            {:type => "v", :name => "new_view", :master_table => 'f'},
            {:type => "r", :name => "new_table", :master_table => 't'}
        ]
      end

      before do
        mock(schema).class_for_type('v').at_least(1) { GpdbDataset }
        mock(schema).class_for_type('r').at_least(1) { GpdbTable }
      end

      it "creates new copies of the datasets in our db" do
        expect do
          schema.refresh_datasets(account)
        end.to change(Dataset, :count).by(2)
        new_table = schema.datasets.find_by_name('new_table')
        new_view = schema.datasets.find_by_name('new_view')
        new_table.should be_a GpdbTable
        new_table.master_table.should be_true
        new_view.should be_a GpdbDataset
        new_view.master_table.should be_false
      end

      it "returns the list of datasets" do
        datasets = schema.refresh_datasets(account)
        datasets.map(&:name).should match_array(['table', 'new_table', 'new_view'])
      end

      it "sets the refreshed_at timestamp" do
        expect {
          schema.refresh_datasets(account)
        }.to change(schema, :refreshed_at)
      end

      context "when a limit and sort are passed to refresh" do
        let(:options) { {:limit => 2, :sort => [{"lower(relname)" => "asc"}]} }

        it "passes limit and sort to greenplum connection" do
          schema.refresh_datasets(account, options)
        end
      end

      context "when trying to create a duplicate record" do
        let(:duped_dataset) { Dataset.new({:name => dataset.name, :schema_id => schema.id}, :without_protection => true) }
        before do
          stub.proxy(GpdbTable).find_or_initialize_by_name_and_schema_id(anything, anything) do |table|
            table.persisted? ? duped_dataset : table
          end
        end

        it "keeps going when caught by rails validations" do
          expect { schema.refresh_datasets(account) }.to change { GpdbTable.count }.by(1)
          schema.datasets.find_by_name('new_table').should be_present
          schema.datasets.find_by_name('new_view').should be_present
        end

        it "keeps going when not caught by rails validations" do
          mock(duped_dataset).save! { raise ActiveRecord::RecordNotUnique.new("boooo!", Exception.new) }

          expect { schema.refresh_datasets(account) }.to change { GpdbTable.count }.by(1)
          schema.datasets.find_by_name('new_table').should be_present
          schema.datasets.find_by_name('new_view').should be_present
        end

        it "returns the list of datasets without duplicates" do
          mock(duped_dataset).save! { raise ActiveRecord::RecordInvalid.new(duped_dataset) }

          datasets = schema.refresh_datasets(account)
          datasets.size.should == 2
          datasets.map(&:name).should match_array(['new_table', 'new_view'])
        end
      end

      it "does not re-create datasets that already exist in our database" do
        expect do
          schema.refresh_datasets(account)
        end.to change(Dataset, :count).by(2)
        expect {
          schema.refresh_datasets(account)
        }.to_not change(Dataset, :count)
      end

      it "does not reindex unmodified datasets" do
        schema.refresh_datasets(account)
        dont_allow(Sunspot).index.with_any_args
        schema.refresh_datasets(account)
      end
    end

    context "with stale records that now exist" do
      before do
        dataset.mark_stale!
        mock(schema).class_for_type('r') { GpdbTable }
      end

      let(:found_datasets) { [{:type => "r", :name => dataset.name, :master_table => 't'}] }

      it "clears the stale flag" do
        schema.refresh_datasets(account)
        dataset.reload.should_not be_stale
      end

      it "increments the dataset counter on the schema" do
        expect do
          schema.refresh_datasets(account)
        end.to change { dataset.schema.reload.active_tables_and_views.count }.by(1)
      end
    end

    context "with records missing" do
      let(:found_datasets) { [] }

      it "mark missing records as stale" do
        schema.refresh_datasets(account, :mark_stale => true)

        dataset.reload.should be_stale
        dataset.stale_at.should be_within(5.seconds).of(Time.current)
      end

      it "decrements the dataset counter on the schema" do
        expect {
          schema.refresh_datasets(account, :mark_stale => true)
        }.not_to change { schema.reload.active_tables_and_views_count }
      end

      it "does not update stale_at time" do
        Timecop.freeze(1.year.ago) do
          dataset.mark_stale!
        end
        schema.refresh_datasets(account, :mark_stale => true)

        dataset.reload.stale_at.should be_within(5.seconds).of(1.year.ago)
      end

      it "does not mark missing records if option not set" do
        schema.refresh_datasets(account)

        dataset.should_not be_stale
      end
    end

    context "with force_index option set" do
      let(:found_datasets) do
        [
            {:type => "r", :name => dataset.name, :master_table => 't'},
            {:type => "v", :name => "new_view", :master_table => 'f'},
            {:type => "r", :name => "new_table", :master_table => 't'}
        ]
      end

      before do
        mock(schema).class_for_type('v').at_least(1) { GpdbDataset }
        mock(schema).class_for_type('r').at_least(1) { GpdbTable }
      end

      it "reindexes unmodified datasets" do
        schema.refresh_datasets(account)
        mock(Sunspot).index(is_a(Dataset)).times(3)
        schema.refresh_datasets(account, :force_index => true)
      end
    end

    context "when the DataSourceConnection has a problem" do
      let(:found_datasets) { raise DataSourceConnection::Error }

      it "should return an empty array" do
        schema.refresh_datasets(account).should == []
      end

      it "should still mark the schema as refreshed" do
        expect {
          schema.refresh_datasets(account)
        }.to change(schema, :refreshed_at)
      end
    end
  end

  describe "#dataset_count" do
    let(:connection) { Object.new }
    let(:options) { {} }
    let(:account) { "foo" }
    let(:schema) { schemas(:default) }

    before do
      connection = Object.new
      stub(schema).connect_with(account) { connection }
      stub(connection).datasets_count(options) { 3 }
    end

    it "returns the number of total entries" do
      schema.dataset_count(account, options).should == 3
    end
  end

  describe '.visible_to' do
    let(:parent) { nil }
    let(:account) { nil }

    it 'gets a list of schemas (alias for refresh)' do
      mock(Schema).refresh(account, parent) { ["schema1", "schema2"] }
      Schema.visible_to(account, parent).should == ["schema1", "schema2"]
    end
  end
end