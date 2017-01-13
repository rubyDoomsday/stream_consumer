# required for implementation
require 'rubygems'
require 'eventmachine'
require 'json'
require 'em-http'

# required for demonstration purposes
require 'pry' # for debugging
require 'active_support/all' # for time zone helpers
require 'colorize' # needed for pretty output

Time.zone    = 'Eastern Time (US & Canada)'
STREAM_HOST  = ENV['STREAM_HOST']
CUSTOMER_ID  = ENV['CUSTOMER_ID']
USERNAME     = ENV['USERNAME']
TOKEN        = ENV['TOKEN']

# Stream Service
class StreamService
  attr_accessor :id, :date, :callbacks, :buffer, :url

  # @param stream_id [String] id of the validic stream
  # @param date [String] date as represented YYYY-MM-DD
  def initialize(stream_id, date: Time.zone.now.to_date)
    @id = stream_id
    @date = date
    @url = "#{STREAM_HOST}/streams/connect/#{@id}/#{@date}"
    @buffer = []
    @callbacks = {}
  end

  # event handler
  # @param name [String] name of event type
  # @param block [Proc] action(s) act on error event data
  def on_event(name, &block)
    @callbacks[name] ||= []
    @callbacks[name] << block
  end

  # connects to SSE stream and listens for data
  def listen
    http = EM::HttpRequest.new(url)
                          .get(head: { 'X-Consumer-Username' => USERNAME,
                                       'X-Consumer-Custom-ID' => CUSTOMER_ID,
                                       'Token' => TOKEN,
                                       'Service-Name' => 'test' })

    http.headers { |header| handle_headers(header) }
    http.stream  { |chunk| handle_stream(chunk) }
    http.errback { |error| handle_error(error) }
  end

  private

  # error handler
  # @param header [String] http header
  def handle_headers(header)
    unless header.status == 200
      @callbacks['errors'].each do |error|
        error.call("failed with status: #{headers.status}")
      end
    end
  end

  # stream handler
  # @param chunk [String] stream data section
  def handle_stream(chunk)
    while index = chunk.index(/\r\n\r\n|\n\n/)
      raw_data = chunk.slice!(0..index)
      types = derive('event', raw_data)
      datas = derive('data', raw_data)

      types.zip(datas).each do |type, data|
        @buffer << Event.new(type, data, raw_data)
      end
    end
    process_buffer
  rescue StreamServiceError
    EM.add_timer(5) { listen }
  rescue => e
    puts "Sorry Dave, I can't do that\n#{e}\n#{raw_data}"
  end

  # error handler
  # @param error [String] http error
  def handle_error(error)
    @callbacks['errors'].each { |e| e.call("http error: #{error}") }
    EM.add_timer(5) { listen }
  end

  # runs event handlers off the queued processed events
  def process_buffer
    while processed_event = @buffer.slice!(0)
      next unless @callbacks.key?(processed_event.type)
      @callbacks[processed_event.type].each { |c| c.call(processed_event) }
    end
  end

  # derives the value of the "key: value" string
  # @param label [String] key
  # @param raw_data [String] unprocessed data off stream
  # @return [Array] e.g. "event: poke\nevent:data" >> ["poke", "data"]
  def derive(label, raw_data)
    parts = raw_data.split(/\r?\n/).select do |piece|
      piece.starts_with?("#{label}:")
    end
    parts.map { |p| p.sub("#{label}: ", '') }
  end

  # Event object
  class Event
    attr_accessor :time, :type, :data, :raw

    def initialize(type, data, raw)
      @time = Time.zone.now
      @type = type
      @data = JSON.parse(data)
      @raw = raw
    end
  end
end

class StreamServiceError < StandardError
  def initialize(data)
    @data = data
  end
end

EM.run do
  stream = StreamService.new('5876d5750b11e70001dfd45c')

  # process poke example
  # stream.on_event 'poke' do |poke|
  #   puts poke.type.to_s.yellow
  # end

  # process data example
  stream.on_event 'data' do |event|
    puts "data received #{event.time}:\n#{JSON.pretty_generate(event.data)}".green
  end

  # additional process data example
  stream.on_event 'data' do |event|
    puts "RAW:#{event.raw}".blue
  end

  # process errors example
  stream.on_event 'error' do |error|
    raise StreamServiceError.new(error.data['error'])
  end

  # connect to stream
  stream.listen
end
