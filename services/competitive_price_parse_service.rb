# frozen_string_literal: true

require 'active_support'
require 'json'
require_relative 'base_service'
require_relative 'fetch_services/fetch_competitive_pricing_data_service'
require_relative '../modules/services_helper_methods'

# CompetitivePriceParseService with 64 threads
class CompetitivePriceParseService < BaseService
  include ServicesHelperMethods
  def initialize(entries, users)
    super()
    return if entries.blank?

    initialize_common(entries, THREAD_COUNT, users)
  end

  def send_fetch_and_process_request(user, retries, current_entries)
    merge_same_asin_hash(
      @result_array,
      FetchCompetitivePricingDataService.new(user, @users, current_entries).fetch_and_process_data(20)&.flatten
    )
  end

  def remaining_data
    @search_key_semaphore.synchronize do
      puts "Remaining: FetchCompetitivePricingDataService #{@_cached_records.count}"
      @_cached_records.blank? ? false : @_cached_records.shift(20)
    end
  end
end
