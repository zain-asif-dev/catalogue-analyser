# frozen_string_literal: true

require 'json'
require 'active_support'
require_relative 'fetch_services/fetch_lowest_price_listing_service'
require_relative 'base_service'
require_relative '../modules/services_helper_methods'

# LowestPriceListingParseService
class LowestPriceListingParseService < BaseService
  include ServicesHelperMethods
  def initialize(entries, users)
    super()
    return if entries.blank?

    initialize_semaphores
    initialize_defined_variables
    @entries = entries.select { |entry| entry['status'] != 'error' && !entry['asin'].nil? }
    @users = users
    @_cached_records = Array.new(@entries.to_a)
    @user_count = @users.count
  end

  def initialize_defined_variables
    @thread_size = THREAD_COUNT
    @result_array = []
    @current_user_index = 0
  end

  def initialize_semaphores
    @search_key_semaphore = Mutex.new
    @search_user_semaphore = Mutex.new
    @data_set_semaphore = Mutex.new
  end

  def start
    return if @_cached_records.blank?

    #   @file_progress =  @file_progress + 10
    #   puts "file_progress-----------------#{@file_progress}--------------------"
    #   message = update_file_progress(@file['id'], @file_progress)
    #   puts "-------------------#{message}-----------------------"
    #   return @file_progress
    # end

    @threads = []
    (0...@thread_size).each do
      @threads << Thread.new { do_scrap }
    end
    @threads.each(&:join)
    @result_array.flatten
    # message = update_service_time_after_processed(@file['id'], 'lowest_price_last_processed_at')
    # puts "-------------------#{message}-----------------------"
    # @file_progress =  @file_progress + 10
    # puts "file_progress-----------------#{@file_progress}--------------------"
    # message = update_file_progress(@file['id'], @file_progress)
    # puts "-------------------#{message}-----------------------"
    # @file_progress
  rescue StandardError => e
    exception_printer(e)
    # error_message = "LowestPriceListingParseService----------#{e.message.first(180)}"
    # update_error_message_in_file(@file['id'], error_message)
    # ExceptionNotifier.notify_exception(
    #   e,
    #   data: { file: file, error: e.message.first(200)}
    # )
    # message = update_service_time_after_processed(@file['id'], 'lowest_price_last_processed_at')
    # puts "-------------------#{message}-----------------------"
    # puts "*********** Died ************"
  end

  def send_fetch_and_process_request(user, retries, current_entries)
    @result_array << FetchLowestPriceListingService.new(user, @users, current_entries).fetch_and_process_data(10)
  rescue StandardError => e
    exception_printer(e)
    retries += 1
    retry if retries <= 3
  end

  def remaining_data
    @search_key_semaphore.synchronize do
      puts "Remaining: FOR LowestPriceListingParseService #{@_cached_records.count}"
      return false if @_cached_records.blank?

      return @_cached_records.shift(5)
    end
  end
end
