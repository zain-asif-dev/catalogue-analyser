# frozen_string_literal: true

require 'dotenv/load'
require 'mechanize'
require_relative '../user_agent'
require 'json'

# Base Service for all classes to handle threading
class BaseService
  THREAD_COUNT = 64

  def agent_object
    agent = Mechanize.new
    agent.read_timeout = 3
    agent.open_timeout = 3
    agent.keep_alive = false
    agent.verify_mode = OpenSSL::SSL::VERIFY_NONE
    agent.user_agent = UserAgent.random
    agent.idle_timeout = 3
    agent.pluggable_parser.default = Mechanize::Page
    agent
  end

  def change_proxy(agent)
    ip = random_proxy.split(':').first
    port = random_proxy.split(':').last.to_i
    agent.set_proxy(ip, port)
  end

  def refresh_agent(agent)
    agent.reset
    agent.user_agent = UserAgent.random
  end

  def send_request(agent, uri, params = nil, headers = {})
    tries = 0
    max_tries = 10
    page = nil?
    agent.verify_mode = OpenSSL::SSL::VERIFY_NONE if uri.include?('https')
    begin
      page = params.nil? ? agent.get(uri, [], nil, headers) : agent.post(uri, params, headers)
      while (page.body.include? 're not a robot') && (tries < max_tries)
        # puts 're not a robot'
        refresh_agent(agent)
        change_proxy(agent) if @proxy_usage
        page = params.nil? ? agent.get(uri, [], nil, headers) : agent.post(uri, params, headers)
        tries += 1
      end
    rescue Mechanize::ResponseCodeError => e
      puts "Response error: HTTP #{e.response_code} from #{uri}, proxy: #{agent.proxy_addr}"
      refresh_agent(agent)
      tries += 1
      if (tries < max_tries) && (e.response_code.to_s != '404')
        change_proxy(agent) if @proxy_usage

        retry
      end
    rescue StandardError => e
      puts "Message: #{e.message} from #{uri}, proxy: #{agent.proxy_addr}"
      refresh_agent(agent)

      tries += 1
      if tries < max_tries
        change_proxy(agent) if @proxy_usage
        retry
      end
    end
    page
  end

  def user_index
    @current_user_index += 1
    @current_user_index = 0 if @current_user_index == @user_count
    @current_user_index
  end

  def rescue_exceptions
    yield
  rescue StandardError => e
    puts "Error: #{e}"
    false
  end

  private

  def random_proxy
    ['95.211.175.167:13400', '108.59.14.200:13402'].sample
  end
end
