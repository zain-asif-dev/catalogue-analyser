# frozen_string_literal: true

require 'json'
require 'active_support'
require_relative 'base_service'
require_relative 'fetch_services/fetch_matching_product_data_service'
require_relative '../modules/services_helper_methods'

# MatchingProductParseService with 64 threads
class MatchingProductParseService < BaseService
  include ServicesHelperMethods
  def initialize(entries, users)
    super()
    return if entries.blank?

    initialize_defined_variables(THREAD_COUNT)
    initialize_semaphores
    @entries = entries.reject { |entry| entry['status'] == 'error' }
    @users = users
    @_cached_records = Array.new(@entries.to_a)
    @user_count = @users.count
  end

  def start
    @threads = []
    (0...@thread_size).each do
      @threads << Thread.new { do_scrap }
    end
    @threads.each(&:join)
    @result_array.flatten
    # FetchMatchingProductDataService.new(@data_set.flatten, @entries, @result_array).map_data
    # message = update_service_time_after_processed(@file['id'], 'matching_last_processed_at')
    # # puts "-------------------#{message}-----------------------"
    # @file_progress += 15

    # # puts "file_progress-----------------#{@file_progress}--------------------"
    # message = update_file_progress(@file['id'], @file_progress)
    # # puts "-------------------#{message}-----------------------"
    # @file_progress
  rescue StandardError => e
    exception_printer(e)
    # error_message = "MatchingProductParseService----------#{e.message.first(180)}"
    # update_error_message_in_file(@file['id'], error_message)
  end

  def send_fetch_and_process_request(user, retries, current_entries)
    @result_array << FetchMatchingProductDataService.new(user, @users, current_entries).fetch_and_process_data(5)
  rescue StandardError => e
    exception_printer(e)
    retries += 1
    retry if retries <= 3
  end

  def remaining_data
    @search_key_semaphore.synchronize do
      puts "Remaining: FOR MatchingProductParseService #{@_cached_records.count}"
      return false if @_cached_records.blank?

      return @_cached_records.shift(5)
    end
  end
end
