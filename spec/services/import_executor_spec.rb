require 'spec_helper'
require 'fakefs/spec_helpers'

describe ImportExecutor do
  let(:user) { users(:owner) }
  let(:source_dataset) { datasets(:table) }
  let(:destination) { workspaces(:public) }
  let(:sandbox) { destination.sandbox }
  let(:destination_table_name) { import.to_table }
  let(:database_url) { sandbox.database.connect_with(account).db_url }
  let(:account) { sandbox.data_source.account_for_user!(user) }

  let!(:import_created_event) do
    Events::WorkspaceImportCreated.by(user).add(
      :workspace => destination,
      :dataset => nil,
      :destination_table => destination_table_name,
      :reference_id => import.id,
      :reference_type => Import.name,
      :source_dataset => source_dataset
    )
  end

  let(:import) do
    FactoryGirl.build(:import,
                      :user => user,
                      :workspace => destination,
                      :source_dataset => source_dataset).tap { |i| i.save(:validate => false) }
  end
  let(:import_failure_message) { "" }

  describe ".run" do
    context "when the import has already been run" do
      before do
        import.success = true
        import.save!
      end

      it "skips the import" do
        any_instance_of ImportExecutor do |executor|
          mock(executor).run.with_any_args.times(0)
        end
        ImportExecutor.run(import.id)
      end
    end
  end

  describe "#run" do
    def mock_copier
      mock(TableCopier).new(anything) do |*args|
        raise import_failure_message if import_failure_message.present?
        yield *args if block_given?
        Object.new.tap { |o| stub(o).start }
      end
    end

    before do
      any_instance_of(Schema) do |schema|
        stub(schema).refresh_datasets.with_any_args do
          FactoryGirl.create(:gpdb_table, :name => destination_table_name, :schema => sandbox)
        end
      end
    end

    let(:copier_start) do
      mock_copier
      ImportExecutor.new(import).run
    end

    it "creates a new table copier and runs it" do
      copier_start
    end

    it "sets the started_at time" do
      expect {
        copier_start
      }.to change(import, :started_at).from(nil)
      import.started_at.should be_within(1.hour).of(Time.current)
    end

    it "uses the import id and created_at time in the pipe_name" do
      mock_copier do |attributes|
        attributes[:pipe_name].should == "#{import.created_at.to_i}_#{import.id}"
      end
      ImportExecutor.run(import.id)
    end

    context "when the import succeeds" do
      it_behaves_like :import_succeeds, :copier_start
    end

    context "when the import fails" do
      let(:import_failure_message) { "some crazy error" }
      let(:run_failing_import) do
        expect {
          copier_start
        }.to raise_error import_failure_message
      end

      it_behaves_like :import_fails_with_message, :run_failing_import, "some crazy error"
    end

    context "where the import source dataset has been deleted" do
      before do
        source_dataset.destroy
        import.reload # reload the deleted source dataset
      end

      let(:error_message) { "Original source dataset #{source_dataset.scoped_name} has been deleted" }
      let(:copier_start) {
        ImportExecutor.new(import).run
      }

      it "raises an error" do
        expect {
          copier_start
        }.to raise_error error_message
      end

      it "creates a WorkspaceImportFailed" do
        expect {
          expect {
            copier_start
          }.to raise_error error_message
        }.to change(Events::WorkspaceImportFailed, :count).by(1)

        event = Events::WorkspaceImportFailed.last
        event.error_message.should == error_message
      end
    end

    context "where the workspace has been deleted" do
      let(:error_message) { "Destination workspace #{destination.name} has been deleted" }

      before do
        destination.destroy
        import.reload # reload the deleted source dataset
      end

      let(:copier_start) {
        ImportExecutor.new(import).run
      }

      it "raises an error" do
        expect {
          copier_start
        }.to raise_error error_message
      end

      it "creates a WorkspaceImportFailed" do
        expect {
          expect {
            copier_start
          }.to raise_error error_message
        }.to change(Events::WorkspaceImportFailed, :count).by(1)

        event = Events::WorkspaceImportFailed.last
        event.error_message.should == error_message
        event.workspace.should == destination
      end
    end

    context "when the source and destinations are in different greenplum databases" do
      let(:source_dataset) { datasets(:searchquery_table) }

      it "should create a CrossDatabaseTableCopier to run the import" do
        dont_allow(TableCopier).new.with_any_args
        ran = false
        any_instance_of(CrossDatabaseTableCopier) do |copier|
          stub(copier).start { ran = true }
        end
        ImportExecutor.new(import).run
        ran.should be_true
      end
    end

    context 'when the import is into a schema' do
      let!(:import) do
        import = FactoryGirl.build(:schema_import, :user => users(:owner),
                                   :schema => schemas(:default),
                                   :to_table => "new_table_for_import",
                                   :created_at => '2012-09-03 23:00:00-07',
                                   :source_dataset_id => datasets(:oracle_table).id, )
        import.save!(:validate => false)
        import
      end
      let(:event) {  }

      it 'creates an OracleTableCopier to run the import' do
        dont_allow(TableCopier).new.with_any_args
        ran = false
        any_instance_of(OracleTableCopier) do |copier|
          stub(copier).start { ran = true }
        end
        ImportExecutor.new(import).run
        ran.should be_true
      end

      it 'updates the SchemaImportCreated event' do
        event = Events::SchemaImportCreated.find_for_import(import)

        any_instance_of(OracleTableCopier) do |copier|
          mock(copier).start
        end

        expect do
          ImportExecutor.new(import).run
        end.to change { event.reload.dataset.try(:name) }.from(nil).to(import.to_table)
      end
    end

    context "when the table copier requires authorization" do
      let(:source_dataset) { datasets(:oracle_table) }
      let(:copier) { Object.new }
      let(:stream_key) { 'f00baa' }
      let(:public_url) { 'myServer.com' }
      let(:stream_url) do
        Rails.application.routes.url_helpers.external_stream_url(:dataset_id => source_dataset.id,
                                                                    :row_limit => import.sample_count,
                                                                    :host => ChorusConfig.instance.public_url,
                                                                    :port => ChorusConfig.instance.server_port,
                                                                    :stream_key => stream_key
        )
      end

      let(:copier_params) do
        {
            :source_dataset => source_dataset,
            :stream_url => stream_url
        }
      end

      before do
        stub(copier).start
        stub(ChorusConfig.instance).public_url { public_url }
      end

      it "generates a login key in the import and passes in a stream url to the copier" do
        mock(OracleTableCopier).new(hash_including(copier_params)) { copier }
        stub(import).stream_key { stream_key }
        mock(import).generate_key
        ImportExecutor.new(import).run
      end

      it "erases the stream_key after running" do
        stub(OracleTableCopier).new.with_any_args { copier }
        ImportExecutor.new(import).run
        import.reload.stream_key.should be_nil
      end

      describe "when the public_url is not set" do
        let(:public_url) { nil }
        let(:import_failure_message) { "Please set public_url in chorus.properties" }
        let(:run_failing_import) do
          expect {
            ImportExecutor.new(import).run
          }.to raise_error import_failure_message
        end

        it_behaves_like :import_fails_with_message, :run_failing_import, "Please set public_url in chorus.properties"
      end
    end
  end
end
