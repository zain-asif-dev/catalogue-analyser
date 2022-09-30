# frozen_string_literal: true

require 'active_support'
require_relative 'base_service'
require_relative '../modules/services_helper_methods'

# AmazonOffersDetail to get amazon selling
class AmazonOffersDetail < BaseService
  BASE_URL = 'https://www.amazon.com/gp/offer-listing/'
  include ServicesHelperMethods
  def initialize(entries)
    super()
    initialize_common(entries, 100)
    @proxy_usage = true
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
    change_proxy(agent_object_var) if @proxy_usage
    while (vendor_asin = remaining_data)
      next if vendor_asin[:asin].blank?

      begin
        @result_array.find { |entry| entry[:asin] == vendor_asin[:asin] }.merge!(process_query(agent_object_var, vendor_asin[:asin]))
      rescue StandardError => e
        exception_printer(e)
      end
    end
    Thread.exit
  end

  def process_query(agent, asin)
    url = BASE_URL + asin
    offers_page = send_request(agent, url)
    return { asin: asin, amazon_selling: !offers_page.xpath("//img[@alt='amazon.com']").empty? } if offers_page.present? && offers_page

    { asin: asin, status: "processing : AmazonOfferDeail : No data found from url! URL is #{url}" }
  end

  def remaining_data
    @search_key_semaphore.synchronize do
      puts "Remaining: AmazonOffersDetail #{@_cached_records.count}"
      vendor_asin = @_cached_records.shift
      vendor_asin.present? ? vendor_asin : false
    end
  end
end
