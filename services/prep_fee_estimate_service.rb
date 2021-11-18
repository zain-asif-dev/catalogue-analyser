# frozen_string_literal: true

require 'active_support'
require 'dotenv/load'
require 'json'
require_relative 'base_service'
require_relative 'fetch_services/fetch_prep_fee_estimate_service'
require_relative '../modules/services_helper_methods'

# PrepFeeEstimateService
class PrepFeeEstimateService < BaseService
  include ServicesHelperMethods
  def initialize(entries, users)
    super()
    return if entries.blank?

    initialize_common(entries, THREAD_COUNT, users)
  end

  def send_fetch_and_process_request(user, retries, current_entries)
    merge_same_asin_hash(
      @result_array,
      FetchPrepFeeEstimateService.new(user, @users, current_entries).parse_data.flatten
    )
  rescue StandardError => e
    exception_printer(e)
    retries += 1
    retry if retries <= 3
  end

  def remaining_data
    @search_key_semaphore.synchronize do
      puts "Remaining: FeeEstimateParseService #{@_cached_records.count}"
      current_entries = @_cached_records.shift(50)
      current_entries.present? ? current_entries : false
    end
  end
end
