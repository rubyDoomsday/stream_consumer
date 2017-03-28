# required for implementation
require 'rubygems'
require 'eventmachine'
require 'json'
require 'em-http'
require 'em-eventsource'

# required for demonstration purposes
require 'pry' # for debugging
require 'active_support/all' # for time zone helpers
require 'colorize' # needed for pretty output

Time.zone    = 'Eastern Time (US & Canada)'
USERNAME     = 'test'.freeze
TOKEN        = ENV['TOKEN']
STREAM_HOST  = ENV['STREAM_HOST']

# custom error
class StreamServiceError < StandardError
  def initialize(data)
    @data = data
  end
end

# resource manger
class Resource
  attr_accessor :token

  def initialize(token: TOKEN, date: Time.zone.now.to_date)
    @token  = token
    @date   = date
  end

  def connect
    set_poke_action
    set_data_action
    set_error_action
    stream.retry = 5
    EventMachine.run do
      stream.start
      puts "Listening to: #{stream.url}".green
    end
  end

  private

  # process errors example
  def set_error_action
    stream.error do |error|
      puts "\n#{Time.now} - Serivce Interrupted: #{error}".red
      unless error.downcase.include?('reconnecting')
        sleep(30)
        puts "Recovering from failure: #{stream.url}".red
        stream.start
      end
    end
  end

  # process data example
  def set_data_action
    stream.on 'data' do |event|
      begin
        puts 'event: data'.green
        puts event.to_s.green
        puts ''
      rescue => e
        puts "Print Data Error: #{event}\nERROR: #{e}"
      end
    end
  end

  # process poke example
  def set_poke_action
    stream.on 'poke' do |poke|
      puts "event: poke -- #{poke}".yellow
    end
  end

  def stream
    @service ||= EventMachine::EventSource.new(url, nil, headers)
  end

  def url
    @host ||= "#{STREAM_HOST}/connect?date=#{@date}"
  end

  def headers
    {
      'Content-Type' => 'application/json',
      'Accept' => 'text/event-stream',
      'Token' => TOKEN,
      'Service-Name' => USERNAME
    }
  end
end

# execution
resource = Resource.new
machine = Thread.new { resource.connect }
machine.join