require 'spec_helper'
require 'timeout'

describe CancelableQuery do
  let(:sql) { "Select 1 as a" }
  let(:check_id) { '0.1234' }
  let(:cancelable_query) { CancelableQuery.new(connection, check_id) }

  describe ".execute" do
    let(:connection) { Object.new }
    let(:options) { {:warnings => true}.merge(extra_options) }
    let(:extra_options) { {} }
    let(:results) { GreenplumSqlResult.new }

    before do
      mock(connection).prepare_and_execute_statement(CancelableQuery.format_sql_and_check_id(sql, check_id), options) { results }
    end

    it "calls to the connection" do
      cancelable_query.execute(sql).should == results
    end

    context "when a limit is passed" do
      let(:extra_options) { {:limit => 123} }
      it "should pass the limit along" do
        cancelable_query.execute(sql, :limit => 123)
      end
    end

    context "when a timeout is passed" do
      let(:extra_options) { {:timeout => 100} }
      it "passes the timeout option through to the greenplum connection" do
        cancelable_query.execute(sql, :timeout => 100)
      end
    end
  end

  context "with a real database connection", :greenplum_integration do
    let(:account) { GreenplumIntegration.real_account }
    let(:gpdb_data_source) { account.data_source }
    let(:check_id) { '54321' }

    describe "#cancel" do
      it "cancels the query and throws a query error when the query is cancelled" do
        cancel_thread = Thread.new do
          cancel_connection = gpdb_data_source.connect_with(account)
          wait_until { get_running_queries_by_check_id(cancel_connection).present? }
          CancelableQuery.new(cancel_connection, check_id).cancel
        end

        query_connection = gpdb_data_source.connect_with(account)
        expect {
          CancelableQuery.new(query_connection, check_id).execute("SELECT pg_sleep(15)")
        }.to raise_error GreenplumConnection::QueryError

        get_running_queries_by_check_id(query_connection).should be_nil

        cancel_thread.join
      end
    end

    describe "busy?" do
      let(:connection) { gpdb_data_source.connect_with(account) }

      after do
        CancelableQuery.new(connection, check_id).cancel
      end

      it "returns true when the cancelable query is running" do
        CancelableQuery.new(connection, check_id).busy?.should == false

        Thread.new do
          query_connection = gpdb_data_source.connect_with(account)
          CancelableQuery.new(query_connection, check_id).execute("SELECT pg_sleep(15)")
        end

        wait_until { get_running_queries_by_check_id(connection).present? }

        CancelableQuery.new(connection, check_id).busy?.should == true
      end
    end

    def get_running_queries_by_check_id(conn)
      query = "select current_query from pg_stat_activity;"
      conn.fetch(query).find { |row| row[:current_query].include? check_id }
    end

    def wait_until
      Timeout::timeout 5.seconds do
        until yield
          sleep 0.1
        end
      end
    end
  end

  describe "format_sql_and_check_id" do
    it "comments the check_id before the sql" do
      CancelableQuery.format_sql_and_check_id("select 1", 123).should == "/*123*/select 1"
    end
  end
end
