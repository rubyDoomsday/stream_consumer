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
USERNAME     = ENV['USERNAME']
CUSTOMER_ID  = ENV['CUSTOMER_ID']
TOKEN        = ENV['TOKEN']
STREAM_HOST  = ENV['STREAM_HOST']
STREAM_ID    = ENV['STREAM_ID']

# custom error
class StreamServiceError < StandardError
  def initialize(data)
    @data = data
  end
end

# resource manger
class Resource
  attr_accessor :token, :id

  def initialize(token: TOKEN, id: nil, date: Time.zone.now.to_date)
    raise ArgumentError.new('id cannot be nil') unless id.present?
    @token  = token
    @id     = id
    @date   = date
  end

  def connect
    set_poke_action
    set_data_action
    set_error_action
    EventMachine.run { stream.listen }
  end

  private

  # process errors example
  def set_error_action
    stream.on_event 'error' do |error|
      raise StreamServiceError.new(error.raw)
    end
  end

  # process data example x 2
  def set_data_action
    stream.on_event 'data' do |event|
      puts "\n#{event.time} PROCESSED:\n#{JSON.pretty_generate(event.data)}".green
    end

    stream.on_event 'data' do |event|
      puts "\nRAW:#{event.raw}".blue
    end
  end

  # process poke example
  def set_poke_action
    stream.on_event 'poke' do |poke|
      print '.'.yellow
    end
  end

  def stream
    @service ||= StreamService.new(url, headers)
  end

  def url
    @host ||= "#{STREAM_HOST}/streams/connect/#{@id}/#{@date}"
  end

  def headers
    {
      'X-Consumer-Username' => USERNAME,
      'X-Consumer-Custom-ID' => CUSTOMER_ID,
      'Content-Type' => 'application/json',
      'Accept' => 'text/event-stream',
      'Token' => TOKEN,
      'Service-Name' => 'test'
    }
  end
end

# Stream Service
class StreamService
  attr_accessor :callbacks, :buffer, :url, :headers

  ERROR_TYPE = 'error'.freeze

  # @param stream_id [String] id of the validic stream
  # @param date [String] date as represented YYYY-MM-DD
  def initialize(url, headers)
    raise ArgumentError.new('url is required') unless url.present?
    raise ArgumentError.new('headers are required') unless headers.present?
    @url = url
    @headers = headers
    @buffer = ''
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
    puts 'Listening'.green
    http = EM::HttpRequest.new(url).get(head: headers)
    http.headers { |header| handle_headers(header) }
    http.stream  { |chunk| handle_stream(chunk) }
    http.errback do |error|
      require 'pry'
      binding.pry
      event = Event.new(ERROR_TYPE, error, error)
      handle_error(event)
    end
  end

  private

  # error handler
  # @param header [String] http header
  def handle_headers(header)
    unless header.status == 200
      event = Event.new(ERROR_TYPE, header, header)
      handle_error(event)
    end
  end

  # error handler
  # @param error [String] http error
  def handle_error(error)
    puts "IT BROKE: #{error.raw}".red
    EM.add_timer(5) { listen }
  end

  # stream handler
  # @param chunk [String] stream data section
  def handle_stream(chunk)
    @buffer += chunk
    events = process_buffer
    process_events(events)
  rescue => e
    raise RuntimeError.new("Sorry Dave, I can't do that\n#{e}\n#{raw_data}")
  end

  # processes raw data off the buffer
  def process_buffer
    events = []
    while index = @buffer.index(/\r\n\r\n|\n\n/)
      raw_data = @buffer.slice!(0..index)
      types = derive('event', raw_data)
      datas = derive('data', raw_data)

      types.zip(datas).each do |type, data|
        events << Event.new(type, data, raw_data)
      end
    end
    events
  end

  # runs event handlers off the queued processed events
  def process_events(events)
    while processed_event = events.slice!(0)
      handle_error(processed_event) if processed_event.type == ERROR_TYPE
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

# execution
resource = Resource.new(id: STREAM_ID)
resource.connect
