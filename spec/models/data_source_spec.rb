require 'spec_helper'

describe DataSource do
  describe 'scopes' do
    describe '#accessible_to' do
      let(:permitted_data_source) { data_sources(:owners) }
      let(:prohibited_data_source) { data_sources(:admins) }
      let(:online_data_source) { data_sources(:online) }
      let(:offline_data_source) { data_sources(:offline) }

      let(:user) { users(:owner) }

      it "returns only online data sources that the user can access" do
        DataSource.accessible_to(user).should include(online_data_source)
        DataSource.accessible_to(user).should_not include(offline_data_source)
        DataSource.accessible_to(user).should include(permitted_data_source)
        DataSource.accessible_to(user).should_not include(prohibited_data_source)
      end
    end
  end

  it_behaves_like "a notable model" do
    let!(:note) do
      Events::NoteOnDataSource.create!({
          :actor => users(:owner),
          :data_source => model,
          :body => "This is the body"
      }, :as => :create)
    end

    let!(:model) { FactoryGirl.create(:gpdb_data_source) }
  end

  describe 'creating a DataSource' do
    before do
      any_instance_of(DataSource) do |data_source|
        stub(data_source).valid_db_credentials? { true }
      end
    end

    it 'enqueues a refresh job' do
      stub(QC.default_queue).enqueue_if_not_queued.any_times # for other jobs
      mock(QC.default_queue).enqueue_if_not_queued('DataSource.refresh', anything, hash_including('new' => true))
      FactoryGirl.create(:data_source)
    end
  end

  describe 'automatic reindexing' do
    let(:data_source) { data_sources(:oracle) }

    before do
      stub(Sunspot).index.with_any_args
    end

    context 'making the data source shared' do
      it 'enqueues a reindex job' do
        mock(data_source).solr_reindex_later
        data_source.shared = true
        data_source.save
      end
    end

    context 'making the data source un-shared' do
      let(:data_source) { data_sources(:shared) }

      it 'enqueues a reindex job' do
        mock(data_source).solr_reindex_later
        data_source.shared = false
        data_source.save
      end
    end

    context 'not changing the shared state' do
      it 'doesnt reindex' do
        dont_allow(data_source).solr_reindex_later
        data_source.update_attributes(:name => 'foo')
      end
    end
  end

  describe '#solr_reindex_later' do
    let(:data_source) { data_sources(:owners) }

    it 'enqueues a job' do
      mock(QC.default_queue).enqueue_if_not_queued('DataSource.reindex_data_source', data_source.id)
      data_source.solr_reindex_later
    end
  end

  describe '#reindex_data_source' do
    let(:data_source) { data_sources(:owners) }

    before do
      stub(Sunspot).index.with_any_args
    end

    it 'reindexes itself' do
      mock(Sunspot).index(data_source)
      DataSource.reindex_data_source(data_source.id)
    end

    it 'should reindex all of its datasets' do
      mock(Sunspot).index(is_a(Dataset)).times(data_source.datasets.count)
      DataSource.reindex_data_source(data_source.id)
    end
  end

  describe '.refresh' do
    let(:data_source) { data_sources(:owners) }

    before do
      any_instance_of(DataSource) do |data_source|
        stub(data_source).refresh { @refreshed_data_source = true }
      end
    end

    it 'calls refresh on the data source' do
      DataSource.refresh(data_source.id)
      @refreshed_data_source.should be_true
    end
  end

  describe '#refresh' do
    let(:data_source) { data_sources(:owners) }

    it 'refreshes databases for the data source' do
      mock(data_source).refresh_databases({})
      data_source.refresh
    end

    context 'when new is set' do
      it 'refreshes the databases, skipping dataset solr indexing and then refreshes the schemas forcing the dataset solr indexing' do
        mock(data_source).refresh_databases(hash_including(:skip_dataset_solr_index => true))
        mock(data_source).refresh_schemas(hash_including(:force_index => true))
        data_source.refresh(:new => true)
      end
    end
  end

  describe '#refresh_databases_later' do
    let(:data_source) { data_sources(:owners) }

    it 'should enqueue a job' do
      mock(QC.default_queue).enqueue_if_not_queued('DataSource.refresh_databases', data_source.id)
      data_source.refresh_databases_later
    end
  end

  describe '#account_for_user!' do
    let(:user) { users(:owner) }

    context 'shared data source' do
      let(:data_source) { data_sources(:shared) }
      let(:owner_account) { data_source.owner_account }

      it 'should return the same account for everyone' do
        data_source.account_for_user!(user).should == owner_account
        data_source.account_for_user!(data_source.owner).should == owner_account
      end
    end

    context 'individual data source' do
      let(:data_source) { data_sources(:owners) }
      let!(:owner_account) { InstanceAccount.find_by_data_source_id_and_owner_id(data_source.id, data_source.owner.id) }
      let!(:user_account) { InstanceAccount.find_by_data_source_id_and_owner_id(data_source.id, users(:the_collaborator).id) }

      it 'should return the account for the user' do
        data_source.account_for_user!(data_source.owner).should == owner_account
        data_source.account_for_user!(user_account.owner).should == user_account
      end
    end

    context 'missing account' do
      let(:data_source) { data_sources(:owners) }

      it 'raises an exception' do
        expect { data_source.account_for_user!(users(:no_collaborators)) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe '#account_for_user' do
    let(:data_source) { data_sources(:owners) }

    context 'missing account' do
      it 'returns nil' do
        data_source.account_for_user(users(:no_collaborators)).should be_nil
      end
    end
  end

  describe "search fields" do
    it "indexes text fields" do
      DataSource.should have_searchable_field :name
      DataSource.should have_searchable_field :description
    end
  end

  describe ".reindex_data_source" do
    let(:data_source) { data_sources(:owners) }

    before do
      stub(Sunspot).index.with_any_args
    end

    it "reindexes itself" do
      mock(Sunspot).index(data_source)
      DataSource.reindex_data_source(data_source.id)
    end

    it "should reindex all of it's datasets" do
      mock(Sunspot).index(is_a(Dataset)).times(data_source.datasets.count)
      DataSource.reindex_data_source(data_source.id)
    end
  end

  describe ".solr_reindex_later" do
    let(:data_source) { data_sources(:owners) }
    it "should enqueue a job" do
      mock(QC.default_queue).enqueue_if_not_queued("DataSource.reindex_data_source", data_source.id)
      data_source.solr_reindex_later
    end
  end

  describe ".owned_by" do
    let(:owner) { users(:owner) }
    let!(:gpdb_shared_data_source) { data_sources(:shared) }
    let!(:gpdb_owned_data_source) { data_sources(:owners) }
    let!(:oracle_data_source) {
      ds = data_sources(:oracle)
      ds.owner = users(:the_collaborator)
      ds.save!
    }

    context "for owners" do
      it "includes owned data sources" do
        DataSource.owned_by(owner).should include gpdb_owned_data_source
      end

      it "excludes other users' data sources" do
        DataSource.owned_by(owner).should_not include oracle_data_source
      end

      it "excludes shared data sources" do
        DataSource.owned_by(owner).should_not include gpdb_shared_data_source
      end
    end

    context "for non-owners" do
      it "excludes all data sources" do
        DataSource.owned_by(FactoryGirl.build_stubbed(:user)).should be_empty
      end
    end

    context "for admins" do
      it "includes all data sources" do
        DataSource.owned_by(users(:evil_admin)).count.should == DataSource.count
      end
    end
  end

  it_should_behave_like "taggable models", [:data_sources, :default]
end