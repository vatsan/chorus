require 'spec_helper'

describe GnipDataSourcesController do
  before do
    @user = users(:owner)
    log_in @user
  end

  let(:gnip_data_source) { gnip_data_sources(:default) }

  describe "#create" do
    context "with valid credentials" do
      before do
        stub(Gnip::DataSourceRegistrar).create!(anything, @user) { gnip_data_source }
      end

      it "reports that the data source was created with the correct owner" do
        post :create
        response.code.should == "201"
        decoded_response.owner.id.should == @user.id
        decoded_response.password.should be_nil
      end
    end

    context "with invalid credentials" do
      before do
        stub(Gnip::DataSourceRegistrar).create!(anything, @user) { raise ApiValidationError }
      end

      it "raises an error" do
        post :create
        response.code.should == "422"
      end
    end

    context "accepts non-nested parameters" do
      let(:params) do
        {
            :name => "new_gnip_data_source",
            :description => "some description",
            :stream_url => "http://www.example.com",
            :username => "gnip_username",
            :password => "gnip_password"
        }

      end

      it "nests the params" do
        stub(Gnip::DataSourceRegistrar).create!(params.stringify_keys, anything) { gnip_data_source }

        post :create, params
        response.code.should == "201"
      end
    end
  end

  describe "#index" do
    let(:gnip_data_source) { gnip_data_sources(:default) }

    it "should return correct response code" do
      get :index
      response.code.should == "200"
      decoded_response.length.should == 2
      decoded_response[0].id.should == gnip_data_source.id
      decoded_response[0].owner.id.should == gnip_data_source.owner_id
    end

    it_behaves_like "a paginated list"
    it_behaves_like :succinct_list
  end

  describe '#show' do
    let(:gnip_data_source) { gnip_data_sources(:default) }

    it 'presents the gnip data source' do
      get :show, :id => gnip_data_source.to_param
      response.code.should == '200'
      decoded_response['name'].should == gnip_data_source.name
    end

    generate_fixture 'gnipDataSource.json' do
      get :show, :id => gnip_data_source.to_param
    end
  end

  describe '#update' do
    let(:gnip_data_source) { gnip_data_sources(:default) }
    let(:params) { { :id => gnip_data_source.id } }

    describe "authorization" do
      context "when user is the data source owner" do
        before do
          log_in gnip_data_source.owner
          stub(Gnip::DataSourceRegistrar).update!(gnip_data_source.id.to_s, anything) { gnip_data_source }
        end

        it "allows updating" do
          put :update, params
          response.should be_success
        end
      end

      context "when the user is not the data source owner" do
        before do
          log_in users(:no_collaborators)
          stub(Gnip::DataSourceRegistrar).update!(gnip_data_source.id.to_s, anything) { gnip_data_source }
        end

        it "prevents updating" do
          put :update, params
          response.should be_forbidden
        end
      end

      context "when the user is an admin" do
        before do
          log_in users(:admin)
          stub(Gnip::DataSourceRegistrar).update!(gnip_data_source.id.to_s, anything) { gnip_data_source }
        end

        it "allows updating" do
          put :update, params
          response.should be_success
        end
      end
    end

    context "With valid credentials" do
      before do
        stub(Gnip::DataSourceRegistrar).update!(gnip_data_source.id.to_s, anything) { gnip_data_source }
      end

      it 'correctly updates the gnip data source' do
        put :update, params

        response.code.should == '200'
        decoded_response.description.should_not be_blank
        decoded_response.password.should be_blank
      end
    end

    context "With Invalid credentials" do
      before do
        stub(Gnip::DataSourceRegistrar).update!(gnip_data_source.id.to_s, anything) { raise(ApiValidationError) }
      end
      it "raise an error" do
        post :update, params
        response.code.should == "422"
      end
    end

  end
end