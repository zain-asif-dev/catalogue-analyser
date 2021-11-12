# frozen_string_literal: true

require 'json'
require 'active_support'
require_relative 'base_service'
require_relative 'fetch_fee_estimate_service'
require_relative '../modules/services_helper_methods'

# FeeEstimateParseService
class FeeEstimateParseService < BaseService
  include ServicesHelperMethods
  def initialize(entries, users)
    super()
    return if entries.blank?

    initialize_defined_variables(THREAD_COUNT)
    initialize_semaphores
    @entries = entries.select { |entry| entry['status'] != 'error' and !entry['asin'].nil? }
    @users = users
    @_cached_records = Array.new(@entries)
    @user_count = @users.count
  end

  def start
    return if @_cached_records.blank?

    #   @file_progress =  @file_progress + 10
    #   puts "file_progress-----------------#{@file_progress}--------------------"
    #   message= update_file_progress(@file['id'], @file_progress)
    #   puts "-------------------#{message}-----------------------"
    #   return @file_progress
    # end

    @threads = []
    (0...@thread_size).each do
      @threads << Thread.new { do_scrap }
    end
    @threads.each(&:join)
    FetchFeeEstimateService.parse_data(@data_set)
    # message = update_service_time_after_processed(@file['id'], 'estimate_fee_last_processed_at')
    # puts "-------------------#{message}-----------------------"
    # @file_progress =  @file_progress + 10
    # puts "file_progress-----------------#{@file_progress}--------------------"
    # message= update_file_progress(@file['id'], @file_progress)
    # puts "-------------------#{message}-----------------------"
    # @file_progress
  rescue StandardError => e
    exception_printer(e)
    # error_message = "FeeEstimateParseService----------#{ex.message.first(180)}"
    # update_error_message_in_file(@file['id'], error_message)
    # ExceptionNotifier.notify_exception(
    #   ex,
    #   data: { file_upload_id: @file.id, error: ex.message.first(200)}
    # )
    # message = update_service_time_after_processed(@file['id'], 'estimate_fee_last_processed_at')
    # puts "-------------------#{message}-----------------------"
    # puts '*********** Died ************'
  end

  def send_fetch_and_process_request(user, retries, current_entries)
    @result_array << FetchFeeEstimateService.new(user, @users, current_entries.map { |e| e['asin'] }).fetch_and_process_data(10)
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
