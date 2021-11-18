# frozen_string_literal: true

require 'json'
require 'active_support'
require_relative 'base_service'
require_relative '../modules/services_helper_methods'

# JungleScoutEstSale to get sales rank per month
class JungleScoutEstSale < BaseService
  include ServicesHelperMethods
  def initialize(entries, proxy_usage = true)
    super()
    initialize_common(entries, THREAD_COUNT)
    @proxy_usage = proxy_usage
  end

  def start
    return if @_cached_records.blank?

    # puts "Proxy usage: #{@proxy_usage}"
    @threads = []
    (0...@thread_size).each do
      @threads << Thread.new { do_scrap(agent_object) }
    end
    @threads.each(&:join)
  rescue StandardError => e
    exception_printer(e)
  end

  def do_scrap(agent_object_var)
    agent = agent_object_var

    while (vendor_asin = remaining_data)
      begin
        @result_array.find { |entry| entry[:asin] == vendor_asin[:asin] }.merge!(process_query(agent, vendor_asin))
      rescue StandardError => e
        exception_printer(e)
      end
    end

    # puts  'Scraper thread is finished.'
    Thread.exit
  end

  def process_query(agent, vendor_asin)
    headers = headers_hash
    outer_category = vendor_asin[:outer_category].to_s.gsub(' ', '+').gsub('&', '%26').gsub(',', '%2C')
    salesrank = vendor_asin[:salesrank]
    url = "https://wsq14g5lpc.execute-api.us-east-1.amazonaws.com/prod/sales?rank=#{salesrank}&category=#{outer_category}&store=us"
    result = send_request(agent, url, nil, headers)
    return import_sales_rank_for_asin(result, vendor_asin) if result.present?

    sales_rank_error(vendor_asin, url)
  end

  def headers_hash
    {
      'authority' => 'wsq14g5lpc.execute-api.us-east-1.amazonaws.com',
      'method' => 'GET',
      'scheme' => 'https',
      'accept' => 'application/json, text/javascript, */*; q=0.01',
      'accept-encoding' => 'gzip, deflate, br',
      'accept-language' => 'en-GB,en;q=0.9',
      'origin' => 'https://www.junglescout.com',
      'referer' => 'https://www.junglescout.com/',
      'sec-fetch-dest' => 'blank',
      'sec-fetch-mode' => 'cors',
      'sec-fetch-site' => 'same-site'
    }
  end

  def import_sales_rank_for_asin(result, vendor_asin)
    result = JSON.parse(result.body)
    return sales_rank_error(vendor_asin, result) unless result['status']

    sales_per_month = result['estSalesResult'] == 'N.A.' ? 0 : result['estSalesResult'].to_i
    { asin: vendor_asin[:asin], salespermonth: sales_per_month }
  end

  def sales_rank_error(vendor_asin, url)
    { asin: vendor_asin[:asin], status: "salesrank problem : JungleScoutEstSale : URL is  #{url}" }
  end

  def remaining_data
    @search_key_semaphore.synchronize do
      puts "Remaining: JungleScoutEstSale #{@_cached_records.count}"
      vendor_asin = @_cached_records.shift
      vendor_asin.present? ? vendor_asin : false
    end
  end
end
