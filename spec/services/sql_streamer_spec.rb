require 'spec_helper'

describe SqlStreamer do
  let(:sql) { "select 1;" }
  let(:row_limit) { nil }
  let(:options) { { :quiet_null => false } }
  let(:streamer) { SqlStreamer.new(sql, connection, options) }
  let(:streamer_options) { { :quiet_null => false } }

  let(:streamed_data) { [
      {:id => 1, :something => 'hello'},
      {:id => 2, :something => 'cruel' },
      {:id => 3, :something => 'world'}
  ] }

  let(:connection) {
    obj = Object.new
    mock(obj).stream_sql(sql, streamer_options) do |sql, options, block|
      streamed_data.each do |row|
        block.call row
      end
      true
    end

    obj
  }

  describe "#enum" do
    it "returns an enumerator that yields the header and rows from the sql in csv" do
      check_enumerator(streamer.enum)
    end

    context "when the headers are hidden" do
      let(:options) {{:show_headers => false}}

      it "should not yield the header row" do
        check_enumerator(streamer.enum, false)
      end
    end

    context "with special characters in the data" do
      let(:streamed_data) {
        [{
             :id => 1,
             :double_quotes => %Q{with"double"quotes},
             :single_quotes => %Q{with'single'quotes},
             :comma => 'with,comma'
         }]
      }

      it "escapes the characters in the csv" do
        enumerator = streamer.enum.to_a
        first_record = enumerator[1]

        first_record.should == %Q{1,"with""double""quotes",with'single'quotes,"with,comma"\n}
      end

      describe "when the sql streamer has greenplum as target" do
        let(:streamer) { SqlStreamer.new(sql, connection, { target_is_greenplum: true }) }

        let(:streamed_data) do
          [{
             :id => 1,
             :newline => '\n',
             :carriage_return => '\r',
             :null => '\0'
           }]
        end

        it "converts special characters to whitespace or empty string" do
          enumerator = streamer.enum.to_a
          first_record = enumerator[1]
          first_record.should == "1, , ,\"\"\n"
        end
      end
    end

    context "with row_limit" do
      let(:options) { { :row_limit => 2 } }
      let(:streamer_options) { { :limit => 2, :quiet_null => false } }

      it "uses the limit" do
        enumerator = streamer.enum
        enumerator.next
        finish_enumerator(enumerator)
      end
    end

    context "with quiet null" do
      let(:options) { { :quiet_null => true } }
      let(:streamer_options) { { :quiet_null => true } }

      it "uses the limit" do
        enumerator = streamer.enum
        enumerator.next
        finish_enumerator(enumerator)
      end
    end

    context "for connection errors" do
      let(:connection) {
        obj = Object.new
        mock(obj).stream_sql(sql, streamer_options) do |sql, options, block|
          raise GreenplumConnection::DatabaseError, StandardError.new("Some friendly error message")
        end

        obj
      }

      it "returns the error message" do
        enumerator = streamer.enum
        enumerator.next.should == "Some friendly error message"
        finish_enumerator enumerator
      end
    end

    context "for results with no rows" do
      let(:streamed_data) { [] }

      it "returns the error message" do
        enumerator = streamer.enum
        enumerator.next.should == "The query returned no rows"
        finish_enumerator(enumerator)
      end
    end

    def check_enumerator(enumerator, show_headers=true)
      results = enumerator.to_a

      if show_headers
        results.length.should eq(4)
        results[0].should == "id,something\n"
        results[1].should == "1,hello\n"
        results[2].should == "2,cruel\n"
        results[3].should == "3,world\n"
      else
        results.length.should eq(3)
        results[0].should == "1,hello\n"
        results[1].should == "2,cruel\n"
        results[2].should == "3,world\n"
      end
    end

    def finish_enumerator(enum)
      while true
        enum.next
      end
    rescue
    end
  end
end