require 'spec_helper'

describe DatasetsController do
  let(:user) { schema.data_source.owner }
  let(:instance_account) { schema.data_source.account_for_user!(user) }
  let(:schema) { schemas(:default) }
  let(:table) { datasets(:table) }

  before do
    log_in user
  end

  context "#index" do
    context "with stubbed datasource" do
      before do
        stub(Schema).find(schema.id.to_s) { schema }
        stub(schema).refresh_datasets(anything, options) do
          [dataset1, dataset2, dataset3]
        end
        stub(schema).dataset_count { 122 }
      end
      let(:options) { {:limit => per_page} }
      let(:per_page) { 50 }

      shared_examples :works do
        context "without any filter" do
          it 'returns all the datasets in that schema' do
            get :index, :schema_id => schema.to_param

            response.code.should == "200"
            decoded_response.length.should == 3
            decoded_response.map(&:object_name).should match_array([dataset1.name, dataset2.name, dataset3.name])
          end

          context "pagination" do
            let(:per_page) { 1 }

            it "paginates results" do
              get :index, :schema_id => schema.to_param, :per_page => per_page
              decoded_response.length.should == 1
            end
          end

          it "sorts the datasets by name" do
            get :index, :schema_id => schema.to_param
            # stub checks for valid SQL with sorting
          end
        end

        context "with a name filter" do
          let(:options) { {:name_filter => 'view', :limit => 50} }
          it "filters datasets by name" do
            get :index, :schema_id => schema.to_param, :filter => 'view'
            # stub checks for valid SQL with sorting and filtering
          end
        end

        context 'with a type filter' do
          let(:options) { {:tables_only => true, :limit => 50 } }

          it 'returns datasets of that type' do
            get :index, :schema_id => schema.to_param, :tables_only => true
          end
        end
      end

      context "for an oracle schema" do
        let(:dataset1) { datasets(:oracle_table) }
        let(:dataset2) { datasets(:oracle_view) }
        let(:dataset3) { datasets(:other_oracle_table) }
        let(:schema) { schemas(:oracle) }

        it_should_behave_like :works

        it "saves a single dataset fixture until the show page works", :fixture do
          get :index, :schema_id => schema.to_param
          save_fixture "oracleDataset.json", { :response => response.decoded_body["response"].first }
        end
      end

      context "for a greenplum schema" do
        let(:dataset1) { datasets(:table) }
        let(:dataset2) { datasets(:view) }
        let(:dataset3) { datasets(:other_table) }

        it_should_behave_like :works
      end
    end

    context "with real greenplum", :greenplum_integration do
      let(:user) { users(:admin) }
      let(:schema) { GreenplumIntegration.real_database.schemas.find_by_name('test_schema') }

      context "when searching" do
        before do
          get :index, :schema_id => schema.to_param, :filter => 'CANDY', :page => "1", :per_page => "5"
        end

        it "presents the correct count / pagination information" do
          decoded_pagination.records.should == 7
          decoded_pagination.total.should == 2
        end

        it "returns sandbox datasets that aren't on the first page of unfiltered results" do
          decoded_response.map(&:object_name).should include('candy_empty')
        end
      end
    end
  end

  describe "#show" do
    before do
      any_instance_of(GpdbTable) do |dataset|
        stub(dataset).verify_in_source(user) { true }
      end
    end

    context "when dataset is valid in GPDB" do
      it "should retrieve the db object for a schema" do
        mock.proxy(Dataset).find_and_verify_in_source(table.id, user)

        get :show, :id => table.to_param

        response.code.should == "200"
        decoded_response.object_name.should == table.name
        decoded_response.object_type.should == "TABLE"
      end

      context "when the user does not have permission" do
        let(:user) { users(:not_a_member) }

        it "should return forbidden" do
          get :show, :id => table.to_param

          response.code.should == "403"
        end
      end

      generate_fixture "dataset.json" do
        get :show, :id => table.to_param
      end
    end

    context "when dataset is not valid in GPDB" do
      it "should raise an error" do
        stub(Dataset).find_and_verify_in_source(table.id, user) { raise ActiveRecord::RecordNotFound.new }

        get :show, :id => table.to_param

        response.code.should == "404"
      end
    end
  end
end