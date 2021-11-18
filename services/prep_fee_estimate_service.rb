# frozen_string_literal: true

require 'active_support'
require 'dotenv/load'
require 'json'
require_relative 'base_service'
require_relative 'fetch_prep_fee_estimate_service'
class PrepFeeEstimateService < BaseService
  include ServicesHelperMethods
  def initialize(entries, users)
    super()
    return if entries.blank?

    initialize_common(entries, THREAD_COUNT, users)
  end

  def start
    return if @_cached_records.blank?

    @threads = []
    (0...@thread_size).each do
      @threads << Thread.new { do_scrap }
    end
    @threads.each(&:join)
    # puts "Finished!!!!!!!!!!!!!!!!!"
    # message = update_service_time_after_processed(@file["id"], "prep_details_last_processed_at")
    # #puts "-------------------#{message}-----------------------"
    # @file_progress =  @file_progress + 10
    # #puts "file_progress-----------------#{@file_progress}--------------------"
    # message= update_file_progress(@file["id"], @file_progress)
    # #puts "-------------------#{message}-----------------------"
    # @file_progress
  rescue StandardError => e
    exception_printer(e)
  end

  def send_fetch_and_process_request(user, retries, current_entries)
    merge_same_asin_hash(
      @result_array,
      FetchPrepFeeEstimateService.new(agent, @users, current_entries.map { |e| e['asin'] }).get_data.flatten
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
